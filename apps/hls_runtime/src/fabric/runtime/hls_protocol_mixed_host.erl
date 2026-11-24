-module(hls_protocol_mixed_host).
-moduledoc "Applies retained host routes for an explicit-start BEAM/RTL partition inside hls_protocol_mixed_stream. Connects the actual BEAM actors and validates control and event records; it performs no source planning, actor forwarding or private runtime introspection.".

%% Actor service attachment and startup.
-export([service/3, connect/3, startup/1]).

%% Retained control and event conversion.
-export([controls/2, external/4, native_event/3]).

-doc "Describes a dedicated sealed virtual source service from a validated mixed-application artifact, existing central owner and exact real BEAM actors. The owner must check source_bind against these targets before any actor is connected.".
-spec service(hls_deployment_artifact:artifact(), pid(), #{non_neg_integer() => pid()}) ->
    hls_node:service().
service(Artifact, Owner, Pids) ->
    #{actors := Actors, targets := Targets} =
        hls_deployment_artifact:descriptor(mixed_application, Artifact),
    true = lists:sort(maps:keys(Actors)) =:= lists:sort(maps:keys(Pids)),
    #{
        name => source,
        source => #{owner => Owner, senders => maps:values(Pids), targets => Targets}
    }.

-doc "Connects previously configured BEAM actors to their bound native/external virtual PIDs. Call once from the exclusive input owner, after distribution attachment and startup/control admission, before requesting hardware start. Any partial failure is ambiguous and requires retiring the entire activation; never reconnect or replay.".
-spec connect(map(), #{non_neg_integer() => pid()}, map()) -> ok.
connect(#{actors := Actors}, Pids, Handles) ->
    lists:foreach(
        fun({I, #{module := Module, outputs := Outputs}}) ->
            Bound = maps:map(fun(_, Destination) -> maps:get(Destination, Handles) end, Outputs),
            ok = Module:connect(maps:get(I, Pids), Bound)
        end,
        lists:sort(maps:to_list(Actors))
    ),
    ok.

-doc "Validates a source rectangle and returns its shared wire payload plus actual BEAM recipient indices. The central owner must admit the record to every listed actor before transmitting the command, preserving order with later start/control. No per-recipient record copies or implicit broadcast to excluded actors.".
-spec controls(map(), hls_partition_wire:rectangle()) -> {binary(), [non_neg_integer()], tuple()}.
controls(#{application := Application, actors := Actors}, Command) ->
    {Payload, Recipients, Record} = hls_protocol_application_codec:delivery(Application, Command),
    {Payload, [I || I <- Recipients, is_map_key(I, Actors)], Record}.

-doc "Enumerates bound BEAM startup records in their original actor-local order. They must pass the same exclusive admission path as controls and native messages before connection/start.".
-spec startup(map()) -> [{non_neg_integer(), tuple()}].
startup(#{actors := Actors}) ->
    [
        {I, Record}
     || {I, #{startup := Records}} <- lists:sort(maps:to_list(Actors)), Record <- Records
    ].

-doc "Checks a real BEAM external output against its exact sender actor, declared destination and retained output schema, without reloading its interface or actor packer. Returns a canonical typed application event. This relies on admitted source behavior for source-field meaning; cookie authentication does not isolate a malicious BEAM process.".
-spec external(map(), non_neg_integer(), atom(), tuple()) -> {atom(), tuple()}.
external(
    #{
        actors := Actors,
        application := #{devices := #{board := Binding = #{host := Host, events := Events}}}
    },
    Index,
    Id,
    Record
) ->
    #{outputs := Outputs, schemas := Schemas, output_schemas := OutputSchemas} = maps:get(
        Index, Actors
    ),
    Ports = [P || {P, {external, E}} <- maps:to_list(Outputs), E =:= Id],
    true = Ports =/= [],
    Name = element(1, Record),
    true = lists:any(fun(P) -> lists:member(Name, maps:get(P, OutputSchemas, [])) end, Ports),
    #{selector := Tag, codec := Codec} = maps:get(Name, Schemas),
    Payload = hls_codec:align(hls_record_codec:pack(Codec, Record), 32),
    [Endpoint] = [E || {E, #{id := J}} <- maps:to_list(Events), J =:= Id],
    {Id, Record} = hls_partition_wire:event(Binding, {Endpoint, Host}, {Tag, 0, 0}, Payload).

-doc "Decodes a canonical native external frame using the original shared application schema and physical port order. Rejects nonzero padding/flags or unknown ports. Logical source fields retain their admitted source meaning; no extra global chronology is introduced.".
-spec native_event(map(), byte(), non_neg_integer()) -> {atom(), tuple()}.
native_event(
    #{application := Application, mixed := #{external_count := ExternalCount}}, Index, Frame
) ->
    true = Index < ExternalCount,
    hls_protocol_application_codec:event(Application, board, Index, Frame).
