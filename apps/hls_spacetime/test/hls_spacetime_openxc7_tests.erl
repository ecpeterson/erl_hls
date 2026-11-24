-module(hls_spacetime_openxc7_tests).
-include_lib("eunit/include/eunit.hrl").

%% Exercise the offline entry point without installing either vendor's implementation tools.
-spec placement_test() -> ok.
placement_test() ->
    Dir = filename:join(os:getenv("TMPDIR", "/tmp"),
        "spacetime-openxc7-" ++ integer_to_list(erlang:system_time(nanosecond))),
    ok = file:make_dir(Dir),
    try
        {Manifest, Route} = fixture(Dir),
        Build = write_manifest(Dir, Manifest),
        Physical = hls_spacetime_openxc7:read(Dir, Build, Route),
        #{cells := [Absent, Missing, Pad, Power]} = Physical,
        ?assertMatch(#{placement := unplaced, site := null, bel := null, x := null, y := null}, Absent),
        ?assertMatch(#{placement := unknown, properties := #{<<"NEXTPNR_BEL">> := <<"lost/X">>},
                       x := null, y := null}, Missing),
        ?assertMatch(#{placement := placed, site := <<"io">>, bel := <<"IOB33/PAD">>, x := 2, y := 4}, Pad),
        ?assertMatch(#{placement := placed, site := null, tile := <<"T">>, bel := <<"VCC">>}, Power),
        {ok, [Trace]} = file:consult("apps/hls_spacetime/test_data/spacetime_example.term"),
        Claims = #{bindings => [], generated => []},
        %% This fixture generated both artifacts locally; qualify a synthetic join as synthetic.
        ?assertEqual(native_measurement, maps:get(evidence, Physical)),
        Synthetic = Physical#{evidence := synthetic_fixture},
        #{physical := #{bindings := Bindings}} = hls_spacetime_import:attach(Trace#{build := Build}, Synthetic, Claims),
        ?assert(lists:all(fun(#{disposition := D}) -> D =:= unmapped end, Bindings)),
        Other = Build#{implementation := <<"another-implementation">>},
        ?assertError({spacetime, physical_build_mismatch},
            hls_spacetime_import:attach(Trace#{build := Other}, Synthetic, Claims)),
        ?assertError({openxc7_import, build_mismatch}, hls_spacetime_openxc7:read(Dir, Other, Route)),
        ?assertError({openxc7_import, checkpoint_mismatch}, hls_spacetime_openxc7:read(Dir, Build, <<"other">>)),
        lists:foreach(fun(Change) ->
            Modified = write_manifest(Dir, maps:merge(Manifest, Change)),
            ?assertException(error, _, hls_spacetime_openxc7:read(Dir, Modified, Route))
        end, [#{complete => false}, #{cells => 3}, #{unresolved => 1},
              #{limits => #{cells => 3, bytes => 65536}}, #{bytes => 65537}]),
        Build = write_manifest(Dir, Manifest),
        ok = file:write_file(filename:join(Dir, "synth.json"), <<"[]">>),
        ?assertError({openxc7_import, {file_identity, <<"synth.json">>}},
                     hls_spacetime_openxc7:read(Dir, Build, Route))
    after ok = file:del_dir_r(Dir) end.

%% The pinned tiny witness checks every native cell against the independent Project X-Ray tilegrid.
-spec native_placement_test_() -> list().
native_placement_test_() ->
    case os:getenv("OPENXC7_PLACEMENT_FIXTURE") of
        false -> [];
        Dir -> [{timeout, 30, fun() -> native_placement(Dir) end}]
    end.

%% Size- and digest-consistent tables still cannot claim whole-design routing for a subset.
-spec whole_route_census_test() -> ok.
whole_route_census_test() ->
    Dir = filename:join(os:getenv("TMPDIR", "/tmp"),
        "spacetime-route-census-" ++ integer_to_list(erlang:system_time(nanosecond))),
    ok = file:make_dir(Dir),
    try
        {M, Checkpoint} = fixture(Dir),
        Net = #{id => <<"d">>, aliases => [], nodes => [], pips => [], pin_attachments => [], issues => []},
        Routes = #{schema => 1, objects => 1, unresolved => 0, nets => [Net]},
        Check = fun(All) ->
            Requested = case All of true -> []; false -> [<<"d">>] end,
            Extra = #{<<"route-request.json">> => json:encode(#{all => All, nets => Requested}),
                <<"routes.json">> => json:encode(Routes), <<"fixed-routes.txt">> => <<>>,
                <<"native-pins.json">> => <<"{}">>, <<"openxc7_pins.py">> => <<>>},
            Files = maps:merge(maps:get(files, M), maps:map(fun(Name, Bytes) ->
                ok = file:write_file(filename:join(Dir, Name), Bytes),
                #{bytes => iolist_size(Bytes), sha256 => hash(Bytes)}
            end, Extra)),
            Manifest = M#{files := Files, bytes := lists:sum([N || #{bytes := N} <- maps:values(Files)]),
                limits := (maps:get(limits, M))#{route_objects => 10}, routing => #{objects => 1, unresolved => 0}},
            hls_spacetime_openxc7:read(Dir, write_manifest(Dir, Manifest), Checkpoint)
        end,
        ?assertMatch(#{nets := [#{id := <<"d">>}]}, Check(false)),
        ?assertError({openxc7_import, route_net_census}, Check(true))
    after ok = file:del_dir_r(Dir) end.

%% Compare the raw packed LUT/FF connection, complete census, BEL spelling and grid coordinates.
-spec native_placement(file:filename()) -> ok.
native_placement(Dir) ->
    {ok, [#{build := Build, checkpoint := Route}]} = file:consult(filename:join(Dir, "identity.term")),
    #{cells := Cells} = hls_spacetime_openxc7:read(Dir, Build, Route),
    {ok, Bytes} = file:read_file(filename:join(Dir, "routed.json")),
    #{<<"modules">> := #{<<"top">> := #{<<"cells">> := Packed}}} = json:decode(Bytes),
    #{<<"invert">> := #{<<"type">> := <<"SLICE_LUTX">>, <<"connections">> := #{<<"O6">> := [D]}},
      <<"state">> := #{<<"type">> := <<"SLICE_FFX">>, <<"connections">> := #{<<"D">> := [D]}}} = Packed,
    ?assertEqual(9, map_size(Packed)),
    ?assertEqual(lists:sort(maps:keys(Packed)), lists:sort([I || #{id := I} <- Cells])),
    {ok, Grid} = file:read_file(os:getenv("OPENXC7_TILEGRID")),
    Tiles = json:decode(Grid),
    lists:foreach(fun(#{id := Id, kind := Kind, tile := Tile, site := Site, bel := Bel, x := X, y := Y}) ->
        #{<<"type">> := Kind, <<"attributes">> := #{<<"NEXTPNR_BEL">> := Native}} = maps:get(Id, Packed),
        #{<<"grid_x">> := X, <<"grid_y">> := Y, <<"sites">> := Sites} = maps:get(Tile, Tiles),
        Prefix = case Site of null -> Tile; _ -> ?assert(is_map_key(Site, Sites)), Site end,
        ?assertEqual(Native, <<Prefix/binary, "/", Bel/binary>>)
    end, Cells).

%% A synthetic export covers tile-owned, nested, missing and unplaced BELs in the same census.
-spec fixture(file:filename()) -> {map(), binary()}.
fixture(Dir) ->
    Cell = fun(Attrs) -> #{type => <<"primitive">>, attributes => Attrs} end,
    Packed = #{absent => Cell(#{}), missing => Cell(#{'NEXTPNR_BEL' => <<"lost/X">>}),
        pad => Cell(#{'NEXTPNR_BEL' => <<"io/IOB33/PAD">>}), power => Cell(#{'NEXTPNR_BEL' => <<"T/VCC">>})},
    Top = #{cells => Packed, netnames => #{d => #{}, q => #{}},
        settings => #{'arch.name' => <<"xilinx">>, route => <<"00000000000000000000000000000001">>}},
    Loc = #{tile => <<"T">>, x => 2, y => 4},
    Files = maps:map(fun(File, Data) ->
        ok = file:write_file(filename:join(Dir, File), Data),
        #{bytes => iolist_size(Data), sha256 => hash(Data)}
    end, #{<<"design.v">> => <<"rtl">>, <<"design.xdc">> => <<>>, <<"synth.json">> => <<"{}">>,
        <<"routed.json">> => json:encode(#{modules => #{top => Top}}),
        <<"locations.json">> => json:encode(#{io => Loc#{site => <<"io">>}, 'T' => Loc#{site => null}})}),
    F = maps:get(<<"design.v">>, Files),
    Tool = #{build => #{commit => <<"fixture">>}, launcher => F, executable => F},
    Manifest = #{format => openxc7_placement, schema => 1, complete => true, files => Files,
        bytes => lists:sum([N || #{bytes := N} <- maps:values(Files)]), cells => 4, unresolved => 2,
        limits => #{bytes => 65536, cells => 4}, source => <<"s">>, observation => <<"o">>,
        part => <<"test">>, chipdb => F, synth => <<"synth">>, nextpnr_args => [<<"--write">>],
        tools => #{yosys => Tool, nextpnr => Tool}},
    {Manifest, maps:get(sha256, maps:get(<<"routed.json">>, Files))}.

%% Refresh expected identities for intentional negative mutations of a trusted fixture manifest.
-spec write_manifest(file:filename(), map()) -> hls_observation_build:build().
write_manifest(Dir, Manifest) ->
    Data = json:encode(Manifest),
    ok = file:write_file(filename:join(Dir, "manifest.json"), Data),
    hls_observation_build:new(<<"s">>, hash(<<"rtl">>), <<"o">>, hash(Data)).

%% Use the same raw-byte digest convention as the external capture producer.
-spec hash(iodata()) -> binary().
hash(Data) -> binary:encode_hex(crypto:hash(sha256, Data), lowercase).
