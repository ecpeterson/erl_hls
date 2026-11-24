#!/usr/bin/env escript
%% Reuse the archived interpretation only after the complete two-state trace and exact new RTL agree.
-mode(compile).

%% Bind a verified replay of the logical N2 recording to its own implementation and join its cells.
-spec main([string()]) -> ok.
main([SourceBundle, Run, Output]) ->
    {ok, [#{build := Build, checkpoint := Checkpoint}]} =
        file:consult(filename:join([Run, "native", "identity.term"])),
    {ok, Receipt} = file:read_file(filename:join([Run, "replay", "result.json"])),
    #{observation := Observation, source := Source} = Build,
    Observation = digest(Receipt),
    #{<<"cycles">> := 2369, <<"taps">> := 581, <<"tap_bits_per_cycle">> := 17877,
      <<"trace_sha256">> := <<"bbe6ea76fd2d5a788ac8605b44697da07297c359d47d6cd2507fcf4e1b878933">>,
      <<"rtl_sha256">> := Inputs} = json:decode(Receipt),
    {ok, Manifest} = file:read_file(filename:join([Run, "native", "manifest.json"])),
    #{<<"files">> := Files, <<"source_files">> := Order} = json:decode(Manifest),
    Inputs = [maps:get(<<"sha256">>, maps:get(F, Files)) || F <- Order],
    {ok, Zipped} = file:read_file(SourceBundle),
    Raw = zlib:gunzip(Zipped),
    <<"38fdabd2e1b5a5ea53d20f8a02205d62a37ce1e95fc433f9ed75c01e8e9eb119">> = digest(Raw),
    [{module, M} = code:ensure_loaded(M) || M <- [hls_spacetime, hls_spacetime_storage, hls_target_physical]],
    #{<<"physical">> := null, <<"build">> := #{<<"source">> := Source, <<"rtl">> := Core}} = Wire = json:decode(Raw),
    [Core | _] = Inputs,
    Expected = Wire#{<<"build">> := maps:from_list([{atom_to_binary(K), V} || {K, V} <- maps:to_list(Build)])},
    Bundle = (typed(bundle, maps:remove(<<"build">>, Wire)))#{build => Build},
    Expected = json:decode(iolist_to_binary(hls_spacetime:encode(Bundle))),
    Joined = hls_spacetime_openxc7:join(Bundle, filename:join(Run, "native"), Checkpoint),
    _ = hls_spacetime_artifact:write_bundle(Joined, Output),
    ok.

%% Only the hash-pinned historical recording is admitted. Native IDs and dynamic port names stay binary.
-spec typed(atom(), term()) -> term().
typed(ports, Map) -> maps:map(fun(_, V) -> binary_to_existing_atom(V) end, Map);
typed(_, Map) when is_map(Map) ->
    maps:from_list([{binary_to_existing_atom(K), typed(binary_to_existing_atom(K), V)} || {K,V} <- maps:to_list(Map)]);
typed(K, Rows) when is_list(Rows) -> [typed(K, R) || R <- Rows];
typed(K, <<"0x", Digits/binary>>) when K =:= mask; K =:= read_mask -> binary_to_integer(Digits, 16);
typed(producer, <<"root">>) -> root;
typed(evidence, <<"simulation_witness">>) -> simulation_witness;
typed(K, V) when K =:= format; K =:= unit; K =:= kind; K =:= origin; K =:= reset; K =:= collision ->
    binary_to_existing_atom(V);
typed(_, V) -> V.

%% The implementation manifest binds SHA-256 over the original bytes of each staged artifact.
-spec digest(binary()) -> binary().
digest(Bytes) -> binary:encode_hex(crypto:hash(sha256, Bytes), lowercase).
