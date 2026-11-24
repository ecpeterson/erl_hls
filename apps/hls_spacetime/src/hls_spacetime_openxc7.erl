-module(hls_spacetime_openxc7).
-moduledoc "Offline placement import from a retained openXC7 implementation. The producer owns native extraction and tool provenance.".
-include_lib("kernel/include/file.hrl").
-export([read/3, join/3]).

-define(MAX_BYTES, 64 * 1024 * 1024).
-define(MAX_CELLS, 100000).

-doc "Reads the complete, uncompressed placement export for an independently supplied build and routed-JSON digest. Rechecks the fixed file inventory, bounds, SHA-256 identities and packed cell census. Keeps unknown placements explicit. Raises on missing, malformed or mismatched evidence.".
-spec read(file:filename_all(), hls_observation_build:build(), binary()) ->
    hls_target_physical:physical().
read(Directory, Expected, Checkpoint) ->
    {Catalogue, _Claims} = load(Directory, Expected, Checkpoint),
    Catalogue.

-doc "Joins a trace to its exact implementation and checkpoint using the producer's explicitly requested storage-word qualifications. Resources without qualifications stay unmapped. Rejects width, evidence or identity mismatches.".
-spec join(hls_spacetime:bundle(), file:filename_all(), binary()) -> hls_spacetime:bundle().
join(Bundle = #{build := Build}, Directory, Checkpoint) ->
    {Catalogue, Claims} = load(Directory, Build, Checkpoint),
    hls_spacetime_import:attach(Bundle, Catalogue, Claims).

%% Read and verify the catalogue and optional bit claims from the same bounded inventory.
-spec load(file:filename_all(), hls_observation_build:build(), binary()) ->
    {hls_target_physical:physical(), hls_spacetime_import:claims()}.
load(Directory, Expected, Checkpoint) ->
    Raw = bounded_file(Directory, <<"manifest.json">>, 1024 * 1024),
    Manifest =
        #{
            <<"format">> := <<"openxc7_placement">>,
            <<"schema">> := 1,
            <<"complete">> := true,
            <<"files">> := Files,
            <<"bytes">> := Total,
            <<"cells">> := Count,
            <<"unresolved">> := Unresolved,
            <<"source">> := Source,
            <<"observation">> := Observation,
            <<"limits">> := #{<<"bytes">> := ByteLimit, <<"cells">> := CellLimit},
            <<"part">> := Part,
            <<"chipdb">> := Chipdb,
            <<"synth">> := Synth,
            <<"nextpnr_args">> := Args,
            <<"tools">> := #{<<"yosys">> := Yosys, <<"nextpnr">> := Pnr}
        } = decode(Raw),
    check(
        is_binary(Part) andalso byte_size(Part) > 0 andalso is_binary(Synth) andalso
            byte_size(Synth) > 0 andalso is_list(Args) andalso Args =/= [] andalso
            lists:all(fun is_binary/1, Args),
        provenance
    ),
    check(valid_identity(Chipdb) andalso valid_tool(Yosys) andalso valid_tool(Pnr), provenance),
    check(in_range(ByteLimit, 1, ?MAX_BYTES) andalso in_range(Total, 1, ByteLimit), bytes),
    check(in_range(CellLimit, 1, ?MAX_CELLS) andalso in_range(Count, 0, CellLimit), cells),
    PlacementFiles = [
        <<"design.v">>, <<"design.xdc">>, <<"locations.json">>, <<"routed.json">>, <<"synth.json">>
    ],
    RouteFiles =
        case maps:is_key(<<"routing">>, Manifest) of
            false ->
                [];
            true ->
                [
                    <<"route-request.json">>,
                    <<"native-pins.json">>,
                    <<"fixed-routes.txt">>,
                    <<"routes.json">>
                ]
        end,
    TimingFiles =
        case maps:is_key(<<"timing">>, Manifest) of
            true -> [<<"timing.json">>];
            false when RouteFiles =/= [] -> [<<"openxc7_pins.py">>];
            false -> []
        end,
    StorageFiles =
        case maps:is_key(<<"storage">>, Manifest) of
            true ->
                check(maps:is_key(<<"timing">>, Manifest), storage_without_timing),
                [<<"storage.json">>];
            false ->
                []
        end,
    Names = lists:sort(PlacementFiles ++ RouteFiles ++ TimingFiles ++ StorageFiles),
    check(lists:sort(maps:keys(Files)) =:= Names, file_inventory),
    Sizes = [Size || #{<<"bytes">> := Size} <- maps:values(Files), in_range(Size, 0, Total)],
    check(length(Sizes) =:= length(Names) andalso lists:sum(Sizes) =:= Total, bytes),
    #{<<"design.v">> := #{<<"sha256">> := Rtl}, <<"routed.json">> := #{<<"sha256">> := Route}} =
        Files,
    Build = hls_observation_build:new(Source, Rtl, Observation, digest(Raw)),
    check(hls_observation_build:match(Expected, Build) =:= ok, build_mismatch),
    check(Route =:= Checkpoint, checkpoint_mismatch),
    Data = maps:map(fun(Name, Meta) -> verified(Directory, Name, Meta) end, Files),
    #{<<"modules">> := #{<<"top">> := #{<<"settings">> := Settings, <<"cells">> := Packed}}} =
        decode(maps:get(<<"routed.json">>, Data)),
    check(
        maps:get(<<"arch.name">>, Settings) =:= <<"xilinx">> andalso
            maps:get(<<"route">>, Settings) =:= <<"00000000000000000000000000000001">>,
        post_route
    ),
    check(map_size(Packed) =:= Count, cells),
    check_timing(Data, Manifest, Packed),
    Locations = decode(maps:get(<<"locations.json">>, Data)),
    Cells = [cell(Id, C, Locations) || {Id, C} <- lists:sort(maps:to_list(Packed))],
    Used = [
        Prefix
     || #{properties := #{<<"NEXTPNR_BEL">> := Bel}, placement := placed} <- Cells,
        [Prefix, _] <- [binary:split(Bel, <<"/">>)]
    ],
    check(lists:usort(Used) =:= lists:sort(maps:keys(Locations)), location_inventory),
    check(Count - length(Used) =:= Unresolved, unresolved),
    Catalogue = #{
        build => Build,
        checkpoint => Route,
        evidence => native_measurement,
        coordinate_unit => tile_grid,
        cells => Cells,
        nets => nets(Data, Manifest),
        generated => [],
        bindings => []
    },
    _ = hls_target_physical:validate(Build, #{}, Catalogue),
    {Catalogue, claims(Data, Manifest)}.

%% A producer may qualify several recorded resources against one generated word.
-spec claims(map(), map()) -> hls_spacetime_import:claims().
claims(#{<<"storage.json">> := Raw}, #{
    <<"storage">> := #{<<"words">> := Words, <<"bits">> := Bits, <<"unknown">> := Missing},
    <<"limits">> := #{<<"timing_objects">> := Limit}
}) ->
    Rows = decode(Raw),
    Bindings = [binding(Row) || Row <- Rows],
    All = lists:append([maps:get(bits, B) || B <- Bindings]),
    check(
        length(Rows) =:= Words andalso length(All) =:= Bits andalso Bits =< Limit andalso
            length([ok || #{status := unknown} <- All]) =:= Missing,
        storage_count
    ),
    Signals = lists:usort([N || #{<<"net">> := N} <- Rows]),
    #{generated => [#{id => N, source => N} || N <- Signals], bindings => Bindings};
claims(Data, _) when not is_map_key(<<"storage.json">>, Data) -> #{generated => [], bindings => []}.

%% Only fully qualified multi-cell words have a distributed disposition.
-spec binding(map()) -> hls_target_physical:binding().
binding(#{<<"net">> := Net, <<"resource">> := Resource, <<"bits">> := Raw}) ->
    Bits = [bit(B) || B <- Raw],
    Supported = [C || #{status := supported, cell := C} <- Bits],
    Cells = lists:usort(Supported),
    Status =
        case Cells of
            [] -> unmapped;
            _ when length(Supported) =/= length(Bits) -> ambiguous;
            [_] -> direct;
            _ -> distributed
        end,
    #{
        resource => Resource,
        generated => [Net],
        cells => Cells,
        bits => Bits,
        disposition => Status,
        evidence => <<"Declared RTL word; per-bit packed FDRE qualification in storage.json">>
    }.

%% Missing primitive evidence supplies no physical endpoint.
-spec bit(map()) -> map().
bit(#{<<"status">> := <<"unknown">>, <<"bit">> := I, <<"evidence">> := E}) ->
    #{status => unknown, bit => I, evidence => E};
bit(#{
    <<"status">> := <<"supported">>,
    <<"bit">> := I,
    <<"evidence">> := E,
    <<"cell">> := C,
    <<"pin">> := <<"Q">>,
    <<"edge">> := <<"rising">>,
    <<"initial">> := Init,
    <<"roles">> := #{
        <<"clock">> := <<"CK">>,
        <<"ce">> := <<"CE">>,
        <<"reset">> := <<"SR">>,
        <<"d">> := <<"D">>,
        <<"q">> := <<"Q">>
    }
}) when
    Init =:= 0; Init =:= 1
->
    #{status => supported, bit => I, evidence => E, cell => C, pin => <<"Q">>}.

%% A single-model estimate retains its native unit, cell population and number of absent delays.
-spec check_timing(map(), map(), map()) -> ok.
check_timing(
    #{<<"timing.json">> := Raw},
    #{
        <<"limits">> := #{<<"timing_objects">> := Limit},
        <<"timing">> := #{
            <<"unit">> := <<"ps">>, <<"objects">> := Count, <<"unresolved_delays">> := Missing
        }
    },
    Packed
) ->
    check(in_range(Limit, 1, 100000) andalso in_range(Count, 1, Limit), timing_limit),
    #{
        <<"schema">> := 1,
        <<"unit">> := <<"ps">>,
        <<"objects">> := Count,
        <<"cells">> := Cells,
        <<"sinks">> := Sinks,
        <<"selected_routes">> := Selected
    } = decode(Raw),
    check(lists:sort(maps:keys(Cells)) =:= lists:sort(maps:keys(Packed)), timing_cells),
    Arcs = lists:append([maps:get(<<"arcs">>, C) || C <- maps:values(Cells)]),
    Ports = lists:append([maps:values(maps:get(<<"ports">>, C)) || C <- maps:values(Cells)]),
    ClockRows = lists:sum([length(maps:get(<<"clocks">>, P)) || P <- Ports]),
    RouteRows = lists:sum([
        length(maps:get(<<"aliases">>, N)) + length(maps:get(<<"pins">>, N)) +
            map_size(maps:get(<<"wires">>, N))
     || N <- maps:values(Selected)
    ]),
    check(
        map_size(Cells) + length(Ports) + ClockRows + length(Arcs) + length(Sinks) + RouteRows =:=
            Count,
        timing_count
    ),
    check(length([ok || #{<<"delay_ps">> := null} <- Arcs ++ Sinks]) =:= Missing, missing_delays);
check_timing(Data, _, _) when not is_map_key(<<"timing.json">>, Data) -> ok.

%% Selected routed nets carry measured packed pins; graph geometry stays in the verified sidecar.
-spec nets(map(), map()) -> [map()].
nets(#{<<"timing.json">> := Timing} = Data, Manifest) ->
    _ = nets(maps:remove(<<"timing.json">>, Data), Manifest),
    #{<<"cells">> := Cells} = decode(Timing),
    Pins = [
        {Net, #{
            cell => Cell,
            pin => Port,
            native => <<Cell/binary, "/", Port/binary>>,
            direction => direction(Dir)
        }}
     || {Cell, #{<<"ports">> := Ports}} <- maps:to_list(Cells),
        {Port, #{<<"net">> := Net, <<"direction">> := Dir}} <- maps:to_list(Ports)
    ],
    Groups = maps:groups_from_list(
        fun({Net, _}) -> Net end, fun({_, Pin}) -> Pin end, lists:sort(Pins)
    ),
    [#{id => N, pins => Ps} || {N, Ps} <- lists:sort(maps:to_list(Groups))];
nets(#{<<"routes.json">> := Raw}, #{
    <<"routing">> := #{<<"objects">> := Count, <<"unresolved">> := Gaps},
    <<"limits">> := #{<<"route_objects">> := Limit}
}) ->
    check(in_range(Limit, 1, 100000) andalso in_range(Count, 0, Limit), route_limit),
    #{<<"schema">> := 1, <<"nets">> := Rows, <<"objects">> := Count, <<"unresolved">> := Gaps} = decode(
        Raw
    ),
    Sizes = [
        1 + length(Aliases) + length(Nodes) + length(Pips) + length(Pins) + length(Issues) +
            lists:sum([length(maps:get(<<"wires">>, N)) || N <- Nodes])
     || #{
            <<"aliases">> := Aliases,
            <<"nodes">> := Nodes,
            <<"pips">> := Pips,
            <<"pin_attachments">> := Pins,
            <<"issues">> := Issues
        } <- Rows
    ],
    check(length(Sizes) =:= length(Rows) andalso lists:sum(Sizes) =:= Count, route_count),
    check(lists:sum([length(maps:get(<<"issues">>, R)) || R <- Rows]) =:= Gaps, route_gaps),
    [
        #{
            id => maps:get(<<"id">>, R),
            pins => [
                #{cell => Cell, pin => Port, native => Native, direction => direction(Dir)}
             || #{
                    <<"cell">> := Cell,
                    <<"port">> := Port,
                    <<"pin">> := Native,
                    <<"direction">> := Dir
                } <-
                    maps:get(<<"pin_attachments">>, R),
                Cell =/= null
            ]
        }
     || R <- Rows
    ];
nets(Data, _) when not is_map_key(<<"routes.json">>, Data) -> [].

%% The nextpnr post-route hook records whether each port is the driver or a user of this net.
-spec direction(binary()) -> input | output | inout.
direction(<<"IN">>) -> input;
direction(<<"OUT">>) -> output;
direction(<<"INOUT">>) -> inout.

%% Coordinates belong to the chipdb tile. I/O BEL suffixes can themselves contain slashes.
-spec cell(binary(), map(), map()) -> map().
cell(Id, #{<<"type">> := Kind, <<"attributes">> := Attrs}, Locations) ->
    Base = #{
        id => Id, kind => Kind, properties => Attrs, site => null, bel => null, x => null, y => null
    },
    case maps:get(<<"NEXTPNR_BEL">>, Attrs, <<>>) of
        <<>> ->
            Base#{placement => unplaced};
        Full when is_binary(Full) ->
            case binary:split(Full, <<"/">>) of
                [Prefix, Bel] when Prefix =/= <<>>, Bel =/= <<>>, is_map_key(Prefix, Locations) ->
                    #{<<"site">> := Site, <<"tile">> := Tile, <<"x">> := X, <<"y">> := Y} = maps:get(
                        Prefix, Locations
                    ),
                    check(
                        Site =:= Prefix orelse (Site =:= null andalso Tile =:= Prefix),
                        location_prefix
                    ),
                    Base#{
                        placement => placed, site => Site, tile => Tile, bel => Bel, x => X, y => Y
                    };
                _ ->
                    Base#{placement => unknown}
            end
    end.

%% Verify all raw sidecars, including synthesis inputs that do not supply placed cells.
-spec verified(file:filename_all(), binary(), map()) -> binary().
verified(Directory, Name, #{<<"bytes">> := Size, <<"sha256">> := Sha}) ->
    Raw = bounded_file(Directory, Name, Size),
    check(byte_size(Raw) =:= Size andalso digest(Raw) =:= Sha, {file_identity, Name}),
    Raw.

%% An open descriptor pins the inode; reading at most the bound plus one detects growth.
-spec bounded_file(file:filename_all(), binary(), non_neg_integer()) -> binary().
bounded_file(Directory, Name, Limit) ->
    {ok, File} = file:open(filename:join(Directory, Name), [read, raw, binary]),
    try
        {ok, #file_info{type = regular, size = Size}} = file:read_file_info(File),
        check(Size =< Limit, {file_limit, Name}),
        case file:read(File, Size + 1) of
            eof when Size =:= 0 -> <<>>;
            {ok, Bytes} when byte_size(Bytes) =:= Size -> Bytes;
            _ -> error({openxc7_import, {file_changed, Name}})
        end
    after
        ok = file:close(File)
    end.

%% Native JSON object names are identities; duplicate keys cannot overwrite another cell or BEL.
-spec decode(binary()) -> map() | list().
decode(Raw) ->
    Decoders = #{
        object_start => fun(_) -> #{} end,
        object_push => fun(K, V, M) ->
            check(not is_map_key(K, M), {duplicate, K}),
            M#{K => V}
        end,
        object_finish => fun(M, Outer) -> {M, Outer} end
    },
    {Map, ok, <<>>} = json:decode(Raw, ok, Decoders),
    Map.

%% Accept only actual native executable identities and identified package builds.
-spec valid_tool(map()) -> boolean().
valid_tool(#{
    <<"build">> := #{<<"commit">> := Commit}, <<"launcher">> := Launcher, <<"executable">> := Exe
}) ->
    is_binary(Commit) andalso byte_size(Commit) > 0 andalso valid_identity(Launcher) andalso
        valid_identity(Exe);
valid_tool(_) ->
    false.

%% Tool and database files are external inputs, identified by positive size and lowercase SHA-256.
-spec valid_identity(map()) -> boolean().
valid_identity(#{<<"bytes">> := N, <<"sha256">> := Hex}) when
    is_integer(N), N > 0, is_binary(Hex), byte_size(Hex) =:= 64
->
    re:run(Hex, <<"^[0-9a-f]{64}$">>, [{capture, none}]) =:= match;
valid_identity(_) ->
    false.

%% Use raw file digests throughout; formatting changes create a distinct implementation identity.
-spec digest(binary()) -> binary().
digest(Raw) -> binary:encode_hex(crypto:hash(sha256, Raw), lowercase).

%% Resource limits are integers even at the untyped JSON boundary.
-spec in_range(term(), integer(), integer()) -> boolean().
in_range(N, Low, High) -> is_integer(N) andalso N >= Low andalso N =< High.

%% Reject incomplete or inconsistent evidence before publishing a physical catalogue.
-spec check(boolean(), term()) -> ok.
check(true, _) -> ok;
check(false, Reason) -> error({openxc7_import, Reason}).
