-module(hls_topology_debug).
-moduledoc """
Passive current-state queries for generated topologies.

Open a session with the manifest emitted alongside the instrumented RTL and an
`hls_debug` client registered at endpoint 2. Queries observe one resource at a
clock edge without involving application processes. `inspect_waits/3` follows blocked
channels, reads encountered FIFO occupancies, then rechecks its observations.
Repeated observations suggest a stable wait; they do not prove continuous
blocking between queries or establish an actor's semantic next dependency.
""".
-export([open/2, info/1, query/2, query/3, resource/2, inspect_waits/3, write_wait_report/4]).
-export([decode_info/1, decode_observation/2, decode_observation/3, with_actor_observer/2, actor_fields/1, mailbox_observation/2, manifest_fingerprint/1]).

-define(TIMEOUT, 10000).

info(Pid) ->
    case hls_debug:query(Pid, 16#10, <<>>, ?TIMEOUT) of
        {ok, Reply} -> decode_info(Reply);
        Error -> Error
    end.

-spec open(pid(), map()) -> {ok, map()} | {error, term()}.
open(Pid, Manifest) ->
    case info(Pid) of
        {ok, #{fingerprint := Hash, resources := Count, channels := Channels, queues := Queues, actors := Actors}} ->
            case Manifest of
                #{<<"schema">> := 5, <<"fingerprint">> := Hash,
                  <<"resources">> := Resources, <<"probes">> := Probes}
                        when length(Resources) =:= Count, length(Probes) =:= Channels ->
                    case manifest_fingerprint(Manifest) =:= Hash andalso
                            [maps:get(<<"id">>, R) || R <- Resources] =:= lists:seq(0, Count-1) andalso
                            [maps:get(<<"id">>, P) || P <- Probes] =:= lists:seq(0, Channels-1) andalso
                            [maps:get(<<"kind">>, R) || R <- Resources] =:=
                                lists:duplicate(Channels, <<"channel">>) ++
                                lists:duplicate(Queues, <<"fifo">>) ++ lists:duplicate(Actors, <<"actor">>) of
                        true -> {ok, #{client => Pid, manifest => Manifest,
                            resources => list_to_tuple(Resources)}};
                        false -> {error, corrupt_topology_manifest}
                    end;
                _ -> {error, topology_manifest_mismatch}
            end;
        Error -> Error
    end.

-spec query(map(), non_neg_integer()) -> {ok, map()} | {error, term()}.
query(Session, Id) -> query(Session, Id, ?TIMEOUT).

-doc "Reads and decodes one manifest resource through the verified debug session.".
-spec query(map(), non_neg_integer(), timeout()) -> {ok, map()} | {error, term()}.
query(#{client := Pid, resources := Resources} = Session, Id, Timeout) when Id >= 0, Id < tuple_size(Resources) ->
    case hls_debug:query(Pid, 16#11, <<Id:32/little>>, Timeout) of
        {ok, Bytes} -> decode_observation(Bytes, element(Id+1, Resources), maps:get(actor_observer, Session, ?MODULE));
        Error -> Error
    end;
query(_, Id, _) -> {error, {unknown_resource, Id}}.

-doc "Selects a physical resource for the common hls_debug inspection interface.".
resource(Session = #{resources := Resources}, Id) when Id >= 0, Id < tuple_size(Resources) ->
    {ok, {resource, Session, Id}};
resource(_, Id) -> {error, {unknown_resource, Id}}.

decode_info(<<5:32/little, Count:32/little, Channels:32/little, Queues:32/little,
        Actors:32/little, Hash:32/binary>>) when Channels > 0, Count =:= Channels + Queues + Actors ->
    {ok, #{schema => 5, resources => Count, channels => Channels, queues => Queues, actors => Actors,
        fingerprint => string:lowercase(binary:encode_hex(Hash))}};
decode_info(_) -> {error, unsupported_topology_info}.

-doc "Decodes a query reply using the dedicated actor observation format.".
-spec decode_observation(binary(), map()) -> {ok, map()} | {error, term()}.
decode_observation(Bytes, Resource) -> decode_observation(Bytes, Resource, ?MODULE).

-doc "Decodes a query reply with an explicitly selected actor-mailbox decoder.".
-spec decode_observation(binary(), map(), module()) -> {ok, map()} | {error, term()}.
decode_observation(<<Id:32/little, Cycle:64/little, Value:128/little>>,
        #{<<"id">> := Id, <<"width">> := Width} = Resource, Observer) when Value bsr Width =:= 0 ->
    Sample = #{id => Id, cycle => Cycle, value => Value},
    case Resource of
        #{<<"kind">> := <<"channel">>} ->
            {ok, Sample#{valid => Value band 1 =/= 0, ready => Value band 2 =/= 0}};
        #{<<"kind">> := <<"fifo">>, <<"capacity">> := Capacity} when Value =< Capacity ->
            {ok, Sample#{occupancy => Value, free_slots => Capacity-Value}};
        #{<<"kind">> := <<"actor">>, <<"phases">> := Phases, <<"failures">> := Failures} ->
            %% Exclusive input can precede the first callback retirement. The
            %% context-valid bit still gates phase/failure, even if private early
            %% progress already exists; do not decode those bits as an actor.
            Early = maps:get(<<"early_collection">>, maps:get(<<"reduction">>, Resource, #{}), false),
            ActorValue = case Early andalso Value band (1 bsl 25) =:= 0 of
                true -> 0;
                false -> Value band 16#ffffffff
            end,
            case actor_observation(Sample#{value := ActorValue}, Phases, Failures) of
                {ok, Actor} ->
                    case Observer:mailbox_observation(Actor#{value := Value}, Resource) of
                        {ok, Sample0} -> reduction_observation(Sample0, Resource);
                        Error -> Error
                    end;
                Error -> Error
            end;
        _ -> {error, invalid_resource_value}
    end;
decode_observation(_, _, _) -> {error, malformed_topology_observation}.

actor_observation(Sample = #{value := 0}, _Phases, _Failures) ->
    {ok, Sample#{initialized => false, phase => undefined,
        enter_pending => undefined, failed => undefined, failure => undefined}};
actor_observation(Sample = #{value := Value}, Phases, Failures)
        when Value bsr 26 =:= 0, Value band (1 bsl 25) =/= 0, Value band 255 < length(Phases) ->
    Code = (Value bsr 9) band 65535,
    case failure_details(Code, Failures) of
        {ok, Failure} ->
            {ok, Sample#{initialized => true, phase => lists:nth((Value band 255)+1, Phases),
                enter_pending => Value band 256 =/= 0, failed => Code =/= 0, failure => Failure}};
        error -> {error, {invalid_failure_code, Code}}
    end;
actor_observation(_, _, _) -> {error, invalid_resource_value}.

-doc "Decodes the dedicated mailbox word, rejecting invalid capacity or initialization state.".
-spec mailbox_observation(map(), map()) -> {ok, map()} | {error, term()}.
mailbox_observation(Sample = #{value := Value, initialized := Initialized},
        #{<<"mailbox_kind">> := <<"direct">>, <<"mailbox_capacity">> := Capacity}) ->
    Word = (Value bsr 32) band 16#ffffff,
    Count = Word band 255,
    Postponed = (Word bsr 8) band 255,
    Reserved = (Word bsr 16) band 1,
    case Word of
        0 when not Initialized -> {ok, (maps:merge(Sample, maps:from_keys(
            [message_queue_len, postponed, free_slots, reserved], undefined)))#{
                mailbox_initialized => false}};
        _ when Initialized, Word band 16#fe0000 =:= 16#800000,
                Count + Reserved =< Capacity, Postponed =< Count ->
            {ok, Sample#{mailbox_initialized => true, message_queue_len => Count,
                postponed => Postponed, reserved => Reserved,
                free_slots => Capacity-Count-Reserved}};
        _ -> {error, invalid_mailbox_observation}
    end;
mailbox_observation(Sample = #{value := Value}, _Resource) when (Value bsr 32) band 16#ffffff =:= 0 ->
    {ok, Sample};
mailbox_observation(_, _) -> {error, invalid_mailbox_observation}.

%% Membership is read from the same committed sample as its remaining count.
-spec reduction_observation(map(), map()) -> {ok, map()} | {error, term()}.
reduction_observation(Sample = #{initialized := false},
        #{<<"reduction">> := #{<<"early_collection">> := true}}) ->
    {ok, Sample#{reduction => undefined, gather => undefined}};
reduction_observation(Sample = #{initialized := false, value := Value}, _Resource)
        when Value bsr 56 =:= 0 ->
    {ok, Sample#{reduction => undefined, gather => undefined}};
reduction_observation(Sample = #{initialized := true, value := Value},
        #{<<"reduction">> := #{<<"fields">> := Fields, <<"sites">> := Sites} = Reduction, <<"failures">> := Failures}) ->
    Read = fun(Name) ->
        #{<<"observation_offset">> := Offset, <<"width">> := Width} = maps:get(Name, Fields),
        (Value bsr Offset) band ((1 bsl Width)-1)
    end,
    case Read(<<"status">>) of
        0 -> {ok, Sample#{reduction => idle, gather => idle}};
        Status when Status =:= 1; Status =:= 2 ->
            Id = Read(<<"site">>), Remaining = Read(<<"remaining">>),
            Match = [S || S = #{<<"id">> := I} <- Sites, I =:= Id],
            case {Match, failure_details(Read(<<"failure">>), Failures)} of
                {[#{<<"phase">> := Phase, <<"name">> := Name, <<"population">> := Population} = Site], {ok, Failure}} ->
                    Kind = maps:get(<<"kind">>, Site, <<"reduction">>),
                    Early = Kind =:= <<"reduction">> andalso maps:get(<<"early_collection">>, Reduction, false) andalso
                        Status =:= 1 andalso Remaining =:= 0,
                    ProgressResult = case Early of
                        true -> early_population(Population, Fields, Read);
                        false -> collection_population(Kind, Population, Fields, Read, Remaining)
                    end,
                    case ProgressResult of
                        {ok, Progress} when Early orelse (Status =:= 1 andalso Remaining > 0) orelse
                                (Status =:= 2 andalso Remaining =:= 0) ->
                            Collection = Progress#{status => case Early of true -> early; false -> element(Status, {open, complete}) end,
                                phase => Phase, name => Name, key => Read(<<"key">>),
                                remaining => case Early of true -> undefined; false -> Remaining end, failure => Failure},
                            case Kind of
                                <<"gather">> -> {ok, Sample#{reduction => idle, gather => Collection}};
                                <<"reduction">> -> {ok, Sample#{reduction => Collection, gather => idle}}
                            end;
                        _ -> {error, invalid_reduction_observation}
                    end;
                _ -> {error, invalid_reduction_observation}
            end;
        _ -> {error, invalid_reduction_observation}
    end;
reduction_observation(Sample = #{initialized := true, value := Value}, _Resource) when Value bsr 56 =:= 0 ->
    {ok, Sample#{reduction => idle, gather => idle}};
reduction_observation(_, _) -> {error, invalid_reduction_observation}.

%% Gather permits empty captured membership; scalar reduction keeps its nonempty contract.
-spec collection_population(binary(), map(), map(), fun((binary()) -> non_neg_integer()),
    non_neg_integer()) -> {ok, map()} | error.
collection_population(<<"gather">>, #{<<"runtime_mask">> := true} = Population, Fields, Read, Remaining) ->
    case maps:is_key(<<"expected">>, Fields) andalso Read(<<"expected">>) =:= 0 of
        true when Remaining =:= 0 -> member_progress([], 0, Fields, Read, Remaining);
        true -> error;
        false -> reduction_population(Population, Fields, Read, Remaining)
    end;
collection_population(<<"reduction">>, Population, Fields, Read, Remaining) ->
    reduction_population(Population, Fields, Read, Remaining);
collection_population(_, _, _, _, _) -> error.

%% Early input has a bound and identities but no selected runtime population yet.
-spec early_population(map(), map(), fun((binary()) -> non_neg_integer())) -> {ok, map()} | error.
early_population(#{<<"mode">> := <<"members">>, <<"size">> := Capacity} = Population, Fields, Read) ->
    Selection = case maps:get(<<"runtime_mask">>, Population, false) of
        true -> {members_mask, Capacity, pending};
        false -> {members, maps:get(<<"members">>, Population)}
    end,
    Progress = #{population => Selection, received => undefined, missing_members => undefined},
    case {maps:is_key(<<"expected">>, Fields), maps:is_key(<<"seen">>, Fields)} of
        {false, false} -> {ok, Progress};
        {true, false} -> case Read(<<"expected">>) of 0 -> {ok, Progress}; _ -> error end;
        {true, true} ->
            Seen = Read(<<"seen">>),
            case Read(<<"expected">>) =:= 0 andalso Seen > 0 andalso Seen bsr Capacity =:= 0 of
                true ->
                    Arrived = [I || I <- lists:seq(0, Capacity-1), Seen band (1 bsl I) =/= 0],
                    {ok, Progress#{received := length(Arrived), arrived_members => Arrived}};
                false -> error
            end;
        _ -> error
    end;
early_population(_, _, _) -> error.

%% Wide masks that cannot fit the query retain honest remaining counts, never the capacity as population.
-spec reduction_population(map(), map(), fun((binary()) -> non_neg_integer()), non_neg_integer()) -> {ok, map()} | error.
reduction_population(#{<<"runtime_mask">> := true, <<"size">> := Capacity}, Fields, Read, Remaining) ->
    case maps:is_key(<<"expected">>, Fields) of
        false when Remaining =< Capacity ->
            {ok, #{population => {members_mask, Capacity, unavailable}, received => undefined}};
        true ->
            Expected = Read(<<"expected">>),
            Members = [I || I <- lists:seq(0, Capacity - 1), Expected band (1 bsl I) =/= 0],
            case Expected > 0 andalso Expected bsr Capacity =:= 0 andalso Remaining =< length(Members) of
                true -> member_progress([{M, M} || M <- Members], Expected, Fields, Read, Remaining);
                false -> error
            end;
        _ -> error
    end;
reduction_population(#{<<"mode">> := <<"count">>, <<"size">> := Size}, _Fields, _Read, Remaining)
        when Remaining =< Size -> {ok, #{population => {count, Size}, received => Size - Remaining}};
reduction_population(#{<<"mode">> := <<"members">>, <<"members">> := Members}, Fields, Read, Remaining)
        when Remaining =< length(Members) ->
    member_progress(lists:enumerate(0, Members), (1 bsl length(Members)) - 1, Fields, Read, Remaining);
reduction_population(_, _, _, _) -> error.

%% Fixed populations use declaration order; runtime populations supply numeric bit positions.
-spec member_progress([{non_neg_integer(), term()}], non_neg_integer(), map(),
    fun((binary()) -> non_neg_integer()), non_neg_integer()) -> {ok, map()} | error.
member_progress(Slots, Expected, Fields, Read, Remaining) ->
    Members = [Member || {_, Member} <- Slots],
    Progress = #{population => {members, Members}, received => length(Members) - Remaining},
    MaskValid = not maps:is_key(<<"expected">>, Fields) orelse Read(<<"expected">>) =:= Expected,
    case {MaskValid, maps:is_key(<<"seen">>, Fields)} of
        {false, _} -> error;
        {true, false} -> {ok, Progress};
        {true, true} ->
            Seen = Read(<<"seen">>),
            Arrived = [Member || {Index, Member} <- Slots, Seen band (1 bsl Index) =/= 0],
            case Seen band Expected =:= Seen andalso length(Arrived) + Remaining =:= length(Members) of
                true -> {ok, Progress#{arrived_members => Arrived, missing_members => Members -- Arrived}};
                false -> error
            end
    end.

failure_details(0, _) -> {ok, none};
failure_details(Code, Failures) ->
    case maps:find(integer_to_binary(Code), Failures) of
        {ok, #{<<"kind">> := Kind} = Origin} ->
            Detail = #{code => Code, kind => Kind},
            case Origin of
                #{<<"file">> := File, <<"line">> := Line} ->
                    {ok, Detail#{file => File, line => Line}};
                _ -> {ok, Detail}
            end;
        error -> error
    end.

-doc "Follows channel/FIFO IDs with a bounded query budget, then rechecks the visited resources.".
inspect_waits(Session = #{manifest := Manifest}, Seeds, Options) ->
    hls_topology_wait:inspect_waits(Manifest, fun(Id) -> query(Session, Id) end, Seeds, Options).

write_wait_report(Session, Seeds, Options, OutputPath) ->
    case inspect_waits(Session, Seeds, Options) of
        {ok, Report} -> file:write_file(OutputPath, json:encode(Report));
        Error -> Error
    end.

manifest_fingerprint(Manifest) ->
    Bytes = canonical_json(maps:remove(<<"fingerprint">>, Manifest)),
    string:lowercase(binary:encode_hex(crypto:hash(sha256, Bytes))).

canonical_json(Map) when is_map(Map) ->
    ["{", lists:join(",", [[json:encode(Key), ":", canonical_json(Value)]
        || {Key, Value} <- lists:sort(maps:to_list(Map))]), "}"];
canonical_json(List) when is_list(List) ->
    ["[", lists:join(",", [canonical_json(Value) || Value <- List]), "]"];
canonical_json(Value) -> json:encode(Value).

-doc "Attaches a trusted local decoder; the manifest never selects or loads executable code.".
-spec with_actor_observer(map(), module()) -> map().
with_actor_observer(Session, Observer) ->
    {module, Observer} = code:ensure_loaded(Observer),
    true = erlang:function_exported(Observer, mailbox_observation, 2),
    true = erlang:function_exported(Observer, actor_fields, 1),
    Session#{actor_observer => Observer}.

-doc "Lists observation items available on a dedicated actor resource.".
-spec actor_fields(map()) -> [atom()].
actor_fields(Resource) ->
    Base = [initialized, phase, enter_pending, failed, failure, reduction, gather],
    case Resource of
        #{<<"mailbox_kind">> := <<"direct">>} ->
            Base ++ [mailbox_initialized, message_queue_len, postponed, reserved, free_slots];
        _ -> Base
    end.
