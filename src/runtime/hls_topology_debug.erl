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
                #{<<"schema">> := 2, <<"fingerprint">> := Hash,
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

decode_info(<<2:32/little, Count:32/little, Channels:32/little, Queues:32/little,
        Actors:32/little, Hash:32/binary>>) when Channels > 0, Count =:= Channels + Queues + Actors ->
    {ok, #{schema => 2, resources => Count, channels => Channels, queues => Queues, actors => Actors,
        fingerprint => string:lowercase(binary:encode_hex(Hash))}};
decode_info(_) -> {error, unsupported_topology_info}.

decode_observation(<<Id:32/little, Cycle:64/little, Value:32/little>>,
        #{<<"id">> := Id, <<"width">> := Width} = Resource) when Value bsr Width =:= 0 ->
    Sample = #{id => Id, cycle => Cycle, value => Value},
    case Resource of
        #{<<"kind">> := <<"channel">>} ->
            {ok, Sample#{valid => Value band 1 =/= 0, ready => Value band 2 =/= 0}};
        #{<<"kind">> := <<"fifo">>, <<"capacity">> := Capacity} when Value =< Capacity ->
            {ok, Sample#{occupancy => Value, free_slots => Capacity-Value}};
        #{<<"kind">> := <<"actor">>, <<"phases">> := Phases} ->
            actor_observation(Sample, Phases);
        _ -> {error, invalid_resource_value}
    end;
decode_observation(_, _) -> {error, malformed_topology_observation}.

actor_observation(Sample = #{value := 0}, _Phases) ->
    {ok, Sample#{initialized => false, phase => undefined,
        enter_pending => undefined, failed => undefined}};
actor_observation(Sample = #{value := Value}, Phases)
        when Value band 1024 =/= 0, Value band 255 < length(Phases) ->
    {ok, Sample#{initialized => true, phase => lists:nth((Value band 255)+1, Phases),
        enter_pending => Value band 256 =/= 0, failed => Value band 512 =/= 0}};
actor_observation(_, _) -> {error, invalid_resource_value}.

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
