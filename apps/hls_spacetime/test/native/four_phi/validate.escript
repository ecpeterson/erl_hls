#!/usr/bin/env escript
%% Validate this local producer's bounded JSON with the ordinary Erlang artifact writer.
-mode(compile).

-spec main([string()]) -> ok.
main([Source, Destination]) ->
    {ok, Bytes} = file:read_file(Source),
    true = byte_size(Bytes) =< 16 * 1024 * 1024,
    ok = code:ensure_modules_loaded(
        [hls_spacetime, hls_spacetime_storage, hls_target_physical, hls_spacetime_artifact]),
    Bundle = typed(undefined, json:decode(Bytes)),
    _ = hls_spacetime_artifact:write_bundle(Bundle, Destination),
    ok.

%% Schema keys are existing atoms. Port and native property names stay binaries.
-spec typed(atom(), term()) -> term().
typed(ports, Map) -> maps:map(fun(_, V) -> binary_to_existing_atom(V) end, Map);
typed(properties, Map) -> Map;
typed(_, Map) when is_map(Map) ->
    maps:from_list([{binary_to_existing_atom(K), typed(binary_to_existing_atom(K), V)}
                    || {K,V} <- maps:to_list(Map)]);
typed(Key, List) when is_list(List) -> [typed(Key, V) || V <- List];
typed(mask, <<"0x", Digits/binary>>) -> binary_to_integer(Digits, 16);
typed(producer, <<"root">>) -> root;
typed(evidence, <<"simulation_witness">>) -> simulation_witness;
typed(evidence, <<"native_measurement">>) -> native_measurement;
typed(kind, V) when V =:= <<"bram">>; V =:= <<"logic">>; V =:= <<"write">>;
                    V =:= <<"read_request">>; V =:= <<"read_result">> -> binary_to_existing_atom(V);
typed(K, V) when K =:= format; K =:= unit; K =:= origin; K =:= reset; K =:= collision;
                 K =:= disposition; K =:= coordinate_unit; K =:= direction; K =:= status ->
    binary_to_existing_atom(V);
typed(_, V) -> V.
