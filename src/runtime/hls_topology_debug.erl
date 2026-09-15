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
-export([decode_info/1, decode_observation/2, manifest_fingerprint/1]).

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

-spec query(map(), non_neg_integer(), timeout()) -> {ok, map()} | {error, term()}.
query(#{client := Pid, resources := Resources}, Id, Timeout) when Id >= 0, Id < tuple_size(Resources) ->
    case hls_debug:query(Pid, 16#11, <<Id:32/little>>, Timeout) of
        {ok, Bytes} -> decode_observation(Bytes, element(Id+1, Resources));
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

decode_observation(<<Id:32/little, Cycle:64/little, Value:128/little>>,
        #{<<"id">> := Id, <<"width">> := Width} = Resource) when Value bsr Width =:= 0 ->
    Sample = #{id => Id, cycle => Cycle, value => Value},
    case Resource of
        #{<<"kind">> := <<"channel">>} ->
            {ok, Sample#{valid => Value band 1 =/= 0, ready => Value band 2 =/= 0}};
        #{<<"kind">> := <<"fifo">>, <<"capacity">> := Capacity} when Value =< Capacity ->
            {ok, Sample#{occupancy => Value, free_slots => Capacity-Value}};
        #{<<"kind">> := <<"actor">>, <<"phases">> := Phases, <<"failures">> := Failures} ->
            case actor_observation(Sample#{value := Value band 16#ffffffff}, Phases, Failures) of
                {ok, Actor} ->
                    case mailbox_observation(Actor#{value := Value}, Resource) of
                        {ok, Sample0} -> reduction_observation(Sample0, Resource);
                        Error -> Error
                    end;
                Error -> Error
            end;
        _ -> {error, invalid_resource_value}
    end;
decode_observation(_, _) -> {error, malformed_topology_observation}.

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

mailbox_observation(Sample = #{value := Value}, #{<<"mailbox_capacity">> := Capacity}) ->
    Word = (Value bsr 32) band 16#ffffff,
    Count = Word band 255,
    Postponed = (Word bsr 8) band 255,
    Phase = (Word bsr 21) band 3,
    case Word of
        0 -> {ok, (maps:merge(Sample, maps:from_keys(
            [message_queue_len, postponed, free_slots, reserved, in_flight,
             mail_candidate, entry_candidate, waiting_for_egress, egress_busy, scheduler_phase], undefined)))#{
                mailbox_initialized => false}};
        _ when Word band (1 bsl 23) =/= 0, Phase < 3,
                Count =< Capacity, Postponed =< Count ->
            {ok, Sample#{mailbox_initialized => true, message_queue_len => Count,
                postponed => Postponed, free_slots => Capacity-Count, reserved => 0,
                in_flight => Word band (1 bsl 16) =/= 0,
                mail_candidate => Word band (1 bsl 17) =/= 0,
                entry_candidate => Word band (1 bsl 18) =/= 0,
                waiting_for_egress => Word band (1 bsl 19) =/= 0,
                egress_busy => Word band (1 bsl 20) =/= 0,
                scheduler_phase => element(Phase+1, {boot, startup, run})}};
        _ -> {error, invalid_mailbox_observation}
    end;
mailbox_observation(Sample = #{value := Value}, _Resource) when (Value bsr 32) band 16#ffffff =:= 0 ->
    {ok, Sample};
mailbox_observation(_, _) -> {error, invalid_mailbox_observation}.

reduction_observation(Sample = #{initialized := false, value := Value}, _Resource)
        when Value bsr 56 =:= 0 ->
    {ok, Sample#{reduction => undefined}};
reduction_observation(Sample = #{initialized := true, value := Value},
        #{<<"reduction">> := #{<<"fields">> := Fields, <<"sites">> := Sites}, <<"failures">> := Failures}) ->
    Read = fun(Name) ->
        #{<<"observation_offset">> := Offset, <<"width">> := Width} = maps:get(Name, Fields),
        (Value bsr Offset) band ((1 bsl Width)-1)
    end,
    case Read(<<"status">>) of
        0 -> {ok, Sample#{reduction => idle}};
        Status when Status =:= 1; Status =:= 2 ->
            Id = Read(<<"site">>),
            Remaining = Read(<<"remaining">>),
            Code = Read(<<"failure">>),
            case {[S || S = #{<<"id">> := I} <- Sites, I =:= Id], failure_details(Code, Failures)} of
                {[#{<<"phase">> := Phase, <<"name">> := Name,
                    <<"population">> := Population = #{<<"size">> := Size}}], {ok, Failure}}
                        when Remaining =< Size, (Status =:= 1 andalso Remaining > 0) orelse
                            (Status =:= 2 andalso Remaining =:= 0) ->
                    {ok, Sample#{reduction => #{status => element(Status, {open, complete}),
                        phase => Phase, name => Name, key => Read(<<"key">>),
                        population => population(Population), received => Size-Remaining,
                        remaining => Remaining, failure => Failure}}};
                _ -> {error, invalid_reduction_observation}
            end;
        _ -> {error, invalid_reduction_observation}
    end;
reduction_observation(Sample = #{initialized := true, value := Value}, _Resource) when Value bsr 56 =:= 0 ->
    {ok, Sample#{reduction => idle}};
reduction_observation(_, _) -> {error, invalid_reduction_observation}.

population(#{<<"mode">> := <<"count">>, <<"size">> := Size}) -> {count, Size};
population(#{<<"mode">> := <<"members">>, <<"members">> := Members}) -> {members, Members}.

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
