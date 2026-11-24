-module(hls_spacetime_import).
-include_lib("kernel/include/file.hrl").
-moduledoc """
Reads the bounded native Vivado census exported by export_spacetime.tcl and attaches explicit physical bindings to an execution recording. The caller verifies remote collection/checkpoint hashes; the reader checks the supplied identities, complete table coverage and native references. It never derives causality or upgrades a name match into a supported binding.
""".
%% Offline native evidence boundary; neither runs Vivado nor writes files.
-export([read/3, attach/3]).
-export_type([claims/0]).

-doc "Reviewed generated-object descriptions and binding dispositions. Omitted resources are explicitly unmapped; callers must substantiate supported associations independently of signal spelling.".
-type claims() :: #{
    generated := [hls_spacetime_physical:generated()],
    bindings := [hls_spacetime_physical:binding()]
}.

%% These are importer ceilings, independent of producer-advertised limits.
-define(MAX_BYTES, 268435456).
-define(MAX_RECORDS, 2000000).

-doc "Reads a complete native export directory and requires exact source/RTL/observation and checkpoint digest agreement. Checks every table's header, row/byte counters, aggregate caps and primitive references. Unknown values remain null. Malformed or missing evidence raises an import/physical/SDF-contract or JSON decoding error. The caller owns evidence authenticity and collection hash verification.".
-spec read(file:filename_all(), hls_observation_build:build(), binary()) ->
    hls_spacetime_physical:physical().
read(Directory, ExpectedBuild, ExpectedCheckpoint) ->
    try
        read_checked(Directory, ExpectedBuild, ExpectedCheckpoint)
    catch
        error:{badmatch, _} -> fail(malformed_export);
        error:{badkey, Key} -> fail({missing_field, Key});
        error:function_clause -> fail(malformed_export)
    end.

%% Structural record matches remain private to the external import error boundary.
-spec read_checked(file:filename_all(), hls_observation_build:build(), binary()) ->
    hls_spacetime_physical:physical().
read_checked(Directory, ExpectedBuild, ExpectedCheckpoint) ->
    Manifest = manifest(Directory),
    #{
        <<"format">> := <<"spacetime_physical_export">>,
        <<"schema">> := 1,
        <<"complete">> := true,
        <<"build">> := RawBuild,
        <<"checkpoint">> := #{<<"sha256">> := Checkpoint},
        <<"tool">> := Tool,
        <<"part">> := Part,
        <<"tables">> := Tables,
        <<"reports">> := Reports,
        <<"records">> := Records,
        <<"bytes">> := Bytes
    } = Manifest,
    Build = build(RawBuild),
    require(hls_observation_build:match(ExpectedBuild, Build) =:= ok, build_mismatch),
    require(Checkpoint =:= ExpectedCheckpoint, checkpoint_mismatch),
    Specs = tables(),
    require(
        lists:sort(maps:keys(Tables)) =:= lists:sort([Name || {Name, _} <- Specs]), table_inventory
    ),
    Sizes = [
        size(Directory, Name, maps:get(<<"bytes">>, Meta))
     || {Name, Meta} <- maps:to_list(Tables)
    ],
    ReportSizes = report_sizes(Directory, Reports),
    Sdf = maps:get(<<"sdf">>, Manifest),
    SdfSizes = sdf_sizes(Directory, Sdf),
    require(
        is_integer(Bytes) andalso Bytes =:= lists:sum(Sizes ++ ReportSizes ++ SdfSizes) andalso
            Bytes =< ?MAX_BYTES,
        byte_count
    ),
    Count = lists:sum([count(maps:get(<<"rows">>, M)) || M <- maps:values(Tables)]),
    require(Count =:= Records andalso Count =< ?MAX_RECORDS, record_count),
    Data = maps:from_list([
        {Name, rows(Directory, Name, Header, maps:get(Name, Tables))}
     || {Name, Header} <- Specs
    ]),
    Cells = cells(Data),
    Nets = nets(Data),
    Native = (native(Data, Manifest, Part, Tool, Bytes, Records))#{
        sdf => maps:from_list([{Corner, read_sdf(Directory, Corner, Sdf)} || Corner <- [fast, slow]])
    },
    property_counts(Manifest, Cells, maps:get(net_delays, Native)),
    Catalogue = #{
        build => Build,
        checkpoint => Checkpoint,
        evidence => native_measurement,
        coordinate_unit => tile_grid,
        cells => Cells,
        nets => Nets,
        generated => [],
        bindings => [],
        native => Native
    },
    _ = hls_spacetime_physical:validate(Build, #{}, Catalogue),
    Catalogue.

-doc "Attaches a checked catalogue and explicit claims while preserving all execution events, versions and dependencies. Supplies an unmapped disposition for each omitted semantic resource. Validates the complete result; names-only candidates should be ambiguous, never direct/distributed.".
-spec attach(hls_spacetime:bundle(), hls_spacetime_physical:physical(), claims()) ->
    hls_spacetime:bundle().
attach(Bundle = #{resources := Resources}, Catalogue, #{
    generated := Generated, bindings := Bindings
}) ->
    Claimed = maps:from_list([{maps:get(resource, B), true} || B <- Bindings]),
    Missing = [
        #{
            resource => Id,
            generated => [],
            cells => [],
            disposition => unmapped,
            evidence => <<"No independently qualified physical correspondence supplied">>
        }
     || #{id := Id} <- Resources, not maps:is_key(Id, Claimed)
    ],
    Result = Bundle#{
        physical => Catalogue#{generated => Generated, bindings => Bindings ++ Missing}
    },
    _ = hls_spacetime:validate(Result),
    Result.

%% Only a final complete manifest authenticates the producer's table inventory.
-spec manifest(file:filename_all()) -> map().
manifest(Directory) ->
    File = filename:join(Directory, "manifest.json"),
    {ok, #file_info{size = Size}} = file:read_file_info(File),
    require(Size =< 65536, manifest_limit),
    {ok, Bytes} = file:read_file(File),
    json:decode(Bytes).

%% Translate only fixed schema keys, never external names into atoms.
-spec build(map()) -> hls_observation_build:build().
build(#{<<"source">> := Source, <<"rtl">> := Rtl, <<"observation">> := Observation}) ->
    Build = #{source => Source, rtl => Rtl, observation => Observation},
    case hls_observation_build:validate(Build) of
        ok -> Build;
        {error, _Reason} -> fail(malformed_export)
    end.

%% File bytes are checked before allocating parsed row tables.
-spec size(file:filename_all(), binary(), non_neg_integer()) -> non_neg_integer().
size(Directory, Name, Expected) ->
    {ok, #file_info{size = Actual, type = regular}} = file:read_file_info(
        filename:join(Directory, Name)
    ),
    require(
        is_integer(Expected) andalso Actual =:= Expected andalso Actual =< ?MAX_BYTES,
        {file_size, Name}
    ),
    Actual.

%% Native complete timing reports remain sidecars; their bounded byte coverage is still mandatory.
-spec report_sizes(file:filename_all(), map()) -> [non_neg_integer()].
report_sizes(Directory, Reports) ->
    Names = [<<"timing-max.rpt">>, <<"timing-min.rpt">>],
    require(lists:sort(maps:keys(Reports)) =:= Names, report_inventory),
    [size(Directory, N, maps:get(<<"bytes">>, maps:get(N, Reports))) || N <- Names].

%% Both whole-design corner files use fixed names; producer paths cannot escape the catalogue.
-spec sdf_sizes(file:filename_all(), map()) -> [non_neg_integer()].
sdf_sizes(Directory, Sdf) ->
    require(lists:sort(maps:keys(Sdf)) =:= [<<"fast">>, <<"slow">>], sdf_inventory),
    [
        begin
            Name = <<"timing-", Corner/binary, ".sdf">>,
            #{
                <<"file">> := Name,
                <<"bytes">> := Bytes,
                <<"process_corner">> := Corner,
                <<"mode">> := <<"sta">>
            } = maps:get(Corner, Sdf),
            size(Directory, Name, Bytes)
        end
     || Corner <- [<<"fast">>, <<"slow">>]
    ].

%% SDF keeps its own model, units, conditions and transition records, apart from scalar query data.
-spec read_sdf(file:filename_all(), fast | slow, map()) -> map().
read_sdf(Directory, Corner, Sdf) ->
    #{<<"file">> := Name, <<"sha256">> := Hash} = maps:get(atom_to_binary(Corner), Sdf),
    Parsed = hls_spacetime_sdf:read(
        filename:join(Directory, Name),
        #{corner => Corner, mode => sta, sha256 => Hash}
    ),
    (hls_spacetime_sdf:describe(Parsed))#{file => Name}.

%% Negative or extravagant producer counts cannot drive an allocation.
-spec count(term()) -> non_neg_integer().
count(N) when is_integer(N), N >= 0, N =< ?MAX_RECORDS -> N;
count(_) -> fail(record_count).

%% The fixed native exchange grammar is independent of application-specific resource names.
-spec tables() -> [{binary(), [binary()]}].
tables() ->
    [
        {<<"cells.tsv">>, [
            <<"name">>,
            <<"ref">>,
            <<"site">>,
            <<"bel">>,
            <<"tile">>,
            <<"x">>,
            <<"y">>,
            <<"clock_region">>,
            <<"placement">>
        ]},
        {<<"cell-properties.tsv">>, [<<"cell">>, <<"properties">>]},
        {<<"nets.tsv">>, [
            <<"name">>, <<"route_status">>, <<"type">>, <<"flat_pin_count">>, <<"timing_status">>
        ]},
        {<<"aliases.tsv">>, [<<"name">>, <<"canonical">>]},
        {<<"pins.tsv">>, [<<"net">>, <<"pin">>, <<"cell">>, <<"ref_pin">>, <<"direction">>]},
        {<<"ports.tsv">>, [<<"net">>, <<"port">>, <<"direction">>]},
        {<<"net-delays.tsv">>, [
            <<"net">>,
            <<"delay">>,
            <<"fast_min_ps">>,
            <<"fast_max_ps">>,
            <<"slow_min_ps">>,
            <<"slow_max_ps">>
        ]},
        {<<"delay-properties.tsv">>, [<<"net">>, <<"delay">>, <<"properties">>]},
        {<<"paths.tsv">>, [
            <<"id">>,
            <<"delay_type">>,
            <<"startpoint">>,
            <<"endpoint">>,
            <<"start_clock">>,
            <<"end_clock">>,
            <<"slack_ns">>,
            <<"datapath_ns">>,
            <<"requirement_ns">>,
            <<"logic_levels">>
        ]},
        {<<"path-properties.tsv">>, [<<"path">>, <<"property">>, <<"value">>]},
        {<<"path-members.tsv">>, [<<"path">>, <<"kind">>, <<"name">>]},
        {<<"issues.tsv">>, [<<"stage">>, <<"object">>, <<"reason">>]}
    ].

%% Each table has one exact header and exactly the finalized number of rows.
-spec rows(file:filename_all(), binary(), [binary()], map()) -> [[binary()]].
rows(Directory, Name, Header, #{<<"rows">> := Count}) ->
    {ok, F} = file:open(filename:join(Directory, Name), [read, raw, binary, {read_ahead, 65536}]),
    try
        require(line(F) =:= Header, {header, Name}),
        rows(F, Name, length(Header), Count, [])
    after
        ok = file:close(F)
    end.

%% The next unexpected row fails before a falsely short manifest can hide content.
-spec rows(file:io_device(), binary(), pos_integer(), non_neg_integer(), [[binary()]]) ->
    [[binary()]].
rows(F, Name, Width, Remaining, Acc) ->
    case {line(F), Remaining} of
        {eof, 0} ->
            lists:reverse(Acc);
        {eof, _} ->
            fail({short_table, Name});
        {_, 0} ->
            fail({long_table, Name});
        {Fields, N} ->
            require(length(Fields) =:= Width, {columns, Name}),
            rows(F, Name, Width, N - 1, [Fields | Acc])
    end.

%% Backslash quoting preserves tabs/newlines in native property values without losing row boundaries.
-spec line(file:io_device()) -> [binary()] | eof.
line(F) ->
    case file:read_line(F) of
        eof ->
            eof;
        {ok, B} ->
            require(byte_size(B) =< 1048577 andalso binary:last(B) =:= $\n, line_limit),
            [
                unescape(V, [])
             || V <- binary:split(binary:part(B, 0, byte_size(B) - 1), <<"\t">>, [global])
            ];
        {error, E} ->
            fail({read, E})
    end.

%% Only the exporter's four quoting forms are meaningful; no shell/Tcl evaluation occurs.
-spec unescape(binary(), [byte()]) -> binary().
unescape(<<>>, Acc) ->
    B = list_to_binary(lists:reverse(Acc)),
    require(unicode:characters_to_binary(B) =:= B, utf8),
    B;
unescape(<<$\\, $\\, Rest/binary>>, Acc) ->
    unescape(Rest, [$\\ | Acc]);
unescape(<<$\\, $t, Rest/binary>>, Acc) ->
    unescape(Rest, [$\t | Acc]);
unescape(<<$\\, $n, Rest/binary>>, Acc) ->
    unescape(Rest, [$\n | Acc]);
unescape(<<$\\, $r, Rest/binary>>, Acc) ->
    unescape(Rest, [$\r | Acc]);
unescape(<<$\\, _/binary>>, _) ->
    fail(escape);
unescape(<<C, Rest/binary>>, Acc) when C =/= $\r, C =/= $\n -> unescape(Rest, [C | Acc]);
unescape(_, _) ->
    fail(raw_control).

%% Native properties retain exact strings; duplicate keys do not silently replace evidence.
-spec properties([[binary()]]) -> map().
properties(Rows) ->
    lists:foldl(
        fun([Object, Key, Value], Acc) ->
            Values = maps:get(Object, Acc, #{}),
            require(not maps:is_key(Key, Values), {duplicate_property, Object, Key}),
            Acc#{Object => Values#{Key => Value}}
        end,
        #{},
        Rows
    ).

%% Compact rows preserve all native properties while avoiding repeated long object identities.
-spec property_maps([{term(), binary()}]) -> #{term() => #{binary() => binary()}}.
property_maps(Rows) ->
    lists:foldl(
        fun({Object, Encoded}, Acc) ->
            require(not maps:is_key(Object, Acc), {duplicate_property_object, Object}),
            Acc#{Object => property_map(Object, Encoded)}
        end,
        #{},
        Rows
    ).

%% Decoder callbacks reject duplicate JSON keys before constructing a map.
-spec property_map(term(), binary()) -> #{binary() => binary()}.
property_map(Object, Encoded) ->
    Decoders = #{
        object_start => fun(_) -> #{} end,
        object_push => fun(Key, Value, Acc) -> property(Object, Key, Value, Acc) end,
        object_finish => fun(Map, Outer) -> {Map, Outer} end
    },
    try json:decode(Encoded, ok, Decoders) of
        {Map, ok, <<>>} when is_map(Map) -> Map;
        _ -> fail({property_json, Object})
    catch
        error:{spacetime_import, _} = Reason -> error(Reason);
        error:_ -> fail({property_json, Object})
    end.

%% Native property values are strings, including empty strings; nested JSON is unsupported.
-spec property(term(), term(), term(), map()) -> map().
property(Object, Key, Value, Acc) ->
    require(
        is_binary(Key) andalso byte_size(Key) > 0 andalso is_binary(Value),
        {property_string, Object, Key}
    ),
    require(not maps:is_key(Key, Acc), {duplicate_property, Object, Key}),
    Acc#{Key => Value}.

%% A compact property map is mandatory for every object, even when it is empty.
-spec property_objects(map(), [term()], atom()) -> ok.
property_objects(Properties, Objects, Kind) ->
    require(lists:sort(maps:keys(Properties)) =:= lists:sort(Objects), {property_coverage, Kind}).

%% Property-pair diagnostics do not replace the serialized row and byte ceilings.
-spec property_counts(map(), [map()], [map()]) -> ok.
property_counts(#{<<"counts">> := Counts}, Cells, Delays) ->
    CellPairs = lists:sum([map_size(maps:get(properties, C)) || C <- Cells]),
    DelayPairs = lists:sum([map_size(maps:get(properties, D)) || D <- Delays]),
    require(maps:get(<<"cell_property_pairs">>, Counts) =:= CellPairs, cell_property_count),
    require(maps:get(<<"delay_property_pairs">>, Counts) =:= DelayPairs, delay_property_count).

%% Constants without a physical site remain installed cells with explicitly absent coordinates.
-spec cells(map()) -> [map()].
cells(Data) ->
    Props = property_maps([
        {Cell, Encoded}
     || [Cell, Encoded] <- maps:get(<<"cell-properties.tsv">>, Data)
    ]),
    Cells = [
        begin
            Base = #{
                id => Name,
                kind => Ref,
                properties => maps:get(Name, Props, #{}),
                tile => Tile,
                clock_region => Region
            },
            case Placement of
                <<"placed">> ->
                    Base#{
                        placement => placed,
                        site => Site,
                        bel => Bel,
                        x => integer(X),
                        y => integer(Y)
                    };
                <<"unplaced">> ->
                    require(
                        [Site, Bel, Tile, X, Y] =:= [<<>>, <<>>, <<>>, <<>>, <<>>],
                        {unplaced_fields, Name}
                    ),
                    Base#{placement => unplaced, site => null, bel => null, x => null, y => null};
                _ ->
                    fail({placement, Name, Placement})
            end
        end
     || [Name, Ref, Site, Bel, Tile, X, Y, Region, Placement] <- maps:get(<<"cells.tsv">>, Data)
    ],
    property_objects(Props, [maps:get(id, C) || C <- Cells], cell_properties),
    Cells.

%% Primitive pins are canonical-net members; top-level ports remain separate native endpoints.
-spec nets(map()) -> [map()].
nets(Data) ->
    Pins = lists:foldl(
        fun([Net, Pin, Cell, Ref, Dir], Acc) ->
            P = #{cell => Cell, pin => Ref, direction => direction(Dir), native => Pin},
            maps:update_with(Net, fun(Ps) -> [P | Ps] end, [P], Acc)
        end,
        #{},
        maps:get(<<"pins.tsv">>, Data)
    ),
    Names = [Name || [Name, _, _, _, _] <- maps:get(<<"nets.tsv">>, Data)],
    only_objects(Pins, Names, pin_net),
    [#{id => Name, pins => lists:reverse(maps:get(Name, Pins, []))} || Name <- Names].

%% No property/member row may refer to an object absent from its authoritative table.
-spec only_objects(map(), [term()], atom()) -> ok.
only_objects(Associated, Objects, Kind) ->
    Index = maps:from_list([{O, true} || O <- Objects]),
    lists:foreach(
        fun(O) -> require(maps:is_key(O, Index), {unknown_object, Kind, O}) end,
        maps:keys(Associated)
    ).

%% Numeric columns use explicit null only when the native query supplied no value.
-spec integer(binary()) -> non_neg_integer().
integer(B) ->
    case re:run(B, <<"^(0|[1-9][0-9]*)$">>, [{capture, none}]) of
        match -> binary_to_integer(B);
        nomatch -> fail({integer, B})
    end.

%% Native delays are decimal values; unsupported prose such as N/A is not numeric zero.
-spec number(binary()) -> number() | null.
number(<<>>) ->
    null;
number(B) ->
    require(byte_size(B) =< 64, {number, B}),
    try
        binary_to_float(B)
    catch
        error:badarg ->
            try
                binary_to_integer(B)
            catch
                error:badarg -> fail({number, B})
            end
    end.

%% Vivado uses uppercase directions; native ports may be bidirectional.
-spec direction(binary()) -> input | output | inout.
direction(<<"IN">>) -> input;
direction(<<"OUT">>) -> output;
direction(<<"INOUT">>) -> inout;
direction(D) -> fail({direction, D}).

%% Extra native context remains typed and validated, rather than discarded after placement import.
-spec native(map(), map(), binary(), binary(), non_neg_integer(), non_neg_integer()) -> map().
native(Data, Manifest, Part, Tool, Bytes, Records) ->
    DelayProperties = property_maps([
        {{Net, Delay}, Encoded}
     || [Net, Delay, Encoded] <- maps:get(<<"delay-properties.tsv">>, Data)
    ]),
    Delays = [
        #{
            net => Net,
            id => Id,
            fast_min_ps => number(FMin),
            fast_max_ps => number(FMax),
            slow_min_ps => number(SMin),
            slow_max_ps => number(SMax),
            properties => maps:get({Net, Id}, DelayProperties, #{})
        }
     || [Net, Id, FMin, FMax, SMin, SMax] <- maps:get(<<"net-delays.tsv">>, Data)
    ],
    property_objects(
        DelayProperties, [{maps:get(net, D), maps:get(id, D)} || D <- Delays], delay_properties
    ),
    #{
        part => Part,
        tool => Tool,
        whole_rtl => maps:get(<<"whole_rtl">>, Manifest, null),
        net_delay_basis => maps:get(<<"net_delay_basis">>, Manifest),
        sampled_nets => maps:get(<<"sampled_nets">>, Manifest),
        export_bytes => Bytes,
        export_records => Records,
        ports => [
            #{net => Net, port => Port, direction => direction(Dir)}
         || [Net, Port, Dir] <- maps:get(<<"ports.tsv">>, Data)
        ],
        aliases => [#{id => Name, net => Net} || [Name, Net] <- maps:get(<<"aliases.tsv">>, Data)],
        net_annotations => [
            #{
                net => Name,
                route_status => Status,
                type => Type,
                flat_pin_count => integer(Pins),
                timing_status => Timing
            }
         || [Name, Status, Type, Pins, Timing] <- maps:get(<<"nets.tsv">>, Data)
        ],
        net_delays => Delays,
        paths => paths(Data),
        issues => [
            #{stage => Stage, object => Object, reason => Reason}
         || [Stage, Object, Reason] <- maps:get(<<"issues.tsv">>, Data)
        ]
    }.

%% Complete native reports accompany sampled static paths; membership does not assert dynamic causality.
-spec paths(map()) -> [map()].
paths(Data) ->
    Props = properties(maps:get(<<"path-properties.tsv">>, Data)),
    Members = lists:foldl(
        fun([Id, Kind, Name], A) ->
            maps:update_with(
                Id,
                fun(M) -> [#{kind => Kind, name => Name} | M] end,
                [#{kind => Kind, name => Name}],
                A
            )
        end,
        #{},
        maps:get(<<"path-members.tsv">>, Data)
    ),
    Paths = [
        #{
            id => Id,
            delay_type => Type,
            startpoint => Start,
            endpoint => End,
            start_clock => SC,
            end_clock => EC,
            slack_ns => number(Slack),
            datapath_ns => number(Delay),
            requirement_ns => number(Requirement),
            logic_levels =>
                case Levels of
                    <<>> -> null;
                    _ -> integer(Levels)
                end,
            properties => maps:get(Id, Props, #{}),
            members => lists:reverse(maps:get(Id, Members, []))
        }
     || [Id, Type, Start, End, SC, EC, Slack, Delay, Requirement, Levels] <- maps:get(
            <<"paths.tsv">>, Data
        )
    ],
    Ids = [maps:get(id, P) || P <- Paths],
    only_objects(Props, Ids, path_properties),
    only_objects(Members, Ids, path_members),
    Paths.

%% Import diagnostics describe evidence failures without returning a partial claimed catalogue.
-spec require(boolean(), term()) -> ok.
require(true, _) -> ok;
require(false, Reason) -> fail(Reason).

%% All parser-owned contract failures use one boundary tag.
-spec fail(term()) -> no_return().
fail(Reason) -> error({spacetime_import, Reason}).
