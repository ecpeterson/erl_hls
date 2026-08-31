%%%% xls_topology_family_dslx
%%%%
%%%% Lowers one regular two-dimensional actor family into compact DSLX.

-module(xls_topology_family_dslx).
-moduledoc """
Generates the first compact regular-family DSLX backend.

The accepted subset is deliberately the phi torus shape: one rectangular
two-dimensional family, wrapped same-family translations, and one or more
scalar external outputs. Exact actors, startup traffic, cross-family routes,
and route fanout remain outside this backend.

The generated source contains one reusable node proc and nested `unroll_for!`
spawns over channel arrays. Its source size therefore follows the number of
family rules rather than the number of family members. XLS still elaborates
one actor and the required bounded queues per coordinate.

Each compact lane relation becomes one channel array. When two ports alias one
destination, both router arms use the same array element, preserving the
actor's source-ordered egress. A scalar external is fed by a fair polling merge
whose statically indexed receive sites are unrolled; runtime channel indexing
is not supported by the pinned XLS build.
""".

-export([emit/2]).

-define(U32_MAX, 16#ffffffff).

-doc "Emits deterministic regular-family DSLX from a normalized plan.".
-spec emit(hls_topology:plan(), xls_topology_dslx:profile()) -> iolist().
emit(Plan, Profile) ->
    render(lower(Plan, Profile)).

%%%
%%% Validation and annotation
%%%

lower(Plan, Profile) ->
    ok = require_empty(actors, Plan),
    ok = require_empty(routes, Plan),
    ok = require_empty(startup, Plan),
    Family = require_one_family(maps:get(families, Plan, [])),
    [Width, Height] = require_two_dimensional_shape(Family),
    ok = validate_dimensions(maps:get(id, Family), Width, Height),
    FamilyId = maps:get(id, Family),
    Module = maps:get(module, Family),
    ModuleName = identifier(Module, family_module),
    Interface = hls_actor_interface:from_module(Module),
    Externals = annotate_externals(require_externals(
        maps:get(externals, Plan, [])
    )),
    ExternalIndex = maps:from_list([
        {maps:get(id, External), External} || External <- Externals
    ]),
    Relations = maps:get(route_relations, Plan, []),
    ok = validate_relations(Relations, FamilyId),
    LaneRelations = derive_lane_relations(Relations),
    case maps:get(lane_relations, Plan, '$missing') of
        LaneRelations -> ok;
        CachedLanes -> error({inconsistent_dslx_family_plan_lanes,
            LaneRelations, CachedLanes})
    end,
    Lanes = annotate_lanes(
        LaneRelations,
        FamilyId,
        [Width, Height],
        ExternalIndex
    ),
    ok = validate_lane_ports(Lanes, maps:get(outputs, Family)),
    ok = validate_external_lanes(Externals, Lanes),
    Physical = validate_profile(Profile),
    #{
        name => maps:get(name, Physical),
        depth => maps:get(channel_depth, Physical),
        family => Family#{
            module_name => ModuleName,
            egress_depth => max(
                1,
                hls_actor_interface:max_entry_effects(Interface)
            )
        },
        width => Width,
        height => Height,
        lanes => Lanes,
        family_lanes => [
            Lane || Lane <- Lanes,
            maps:get(kind, Lane) =:= family
        ],
        externals => Externals
    }.

require_empty(Field, Plan) ->
    case maps:get(Field, Plan, '$missing') of
        [] -> ok;
        Value -> error({unsupported_dslx_family_section, Field, Value})
    end.

require_one_family([Family]) -> Family;
require_one_family(Families) ->
    error({unsupported_dslx_family_count, length(Families)}).

require_two_dimensional_shape(Family) ->
    case maps:get(shape, Family) of
        [Width, Height] -> [Width, Height];
        Shape -> error({unsupported_dslx_family_shape,
            maps:get(id, Family), Shape})
    end.

validate_dimensions(_FamilyId, Width, Height)
        when is_integer(Width), Width > 0, Width =< ?U32_MAX,
             is_integer(Height), Height > 0, Height =< ?U32_MAX ->
    ok;
validate_dimensions(FamilyId, Width, Height) ->
    error({unsupported_dslx_family_dimensions,
        FamilyId, [Width, Height], ?U32_MAX}).

require_externals([_ | _] = Externals) -> Externals;
require_externals([]) -> error({unsupported_dslx_family_external_count, 0}).

validate_relations(Relations, FamilyId) ->
    lists:foreach(
        fun(Relation = #{source := Source = {SourceFamily, _Port}}) ->
            case SourceFamily of
                FamilyId -> ok;
                _ -> error({unsupported_relation_source, Source})
            end,
            case Relation of
                #{delivery := direct, recipients := [Recipient]} ->
                    validate_relation_recipient(Source, Recipient, FamilyId);
                #{delivery := Delivery, recipients := Recipients} ->
                    error({unsupported_route, Source, Delivery, Recipients})
            end
        end,
        Relations
    ).

validate_relation_recipient(
        _Source,
        {family, FamilyId, {translate, [_DX, _DY], wrap}},
        FamilyId) ->
    ok;
validate_relation_recipient(_Source, {external, _ExternalId}, _FamilyId) ->
    ok;
validate_relation_recipient(Source, Recipient, _FamilyId) ->
    error({unsupported_dslx_family_recipient, Source, Recipient}).

derive_lane_relations(Relations) ->
    LanePorts = lists:foldl(
        fun(Relation, Acc0) ->
            {SourceFamily, Port} = maps:get(source, Relation),
            lists:foldl(
                fun(Destination, Acc) ->
                    Key = {SourceFamily, Destination},
                    maps:update_with(
                        Key,
                        fun(Ports) -> [Port | Ports] end,
                        [Port],
                        Acc
                    )
                end,
                Acc0,
                maps:get(recipients, Relation)
            )
        end,
        #{},
        Relations
    ),
    [
        #{
            source => SourceFamily,
            destination => Destination,
            source_ports => lists:sort(Ports)
        }
        || {{SourceFamily, Destination}, Ports} <-
               lists:sort(maps:to_list(LanePorts))
    ].

annotate_externals(Externals) ->
    [
        begin
            case maps:get(direction, External) of
                out -> ok;
                Direction -> error({unsupported_dslx_family_external_direction,
                    maps:get(id, External), Direction})
            end,
            External#{
                index => Index,
                output_name => [identifier(
                    maps:get(id, External),
                    external_id
                ), "_out"]
            }
        end
        || {Index, External} <- lists:enumerate(0, Externals)
    ].

annotate_lanes(Lanes, FamilyId, Shape, ExternalIndex) ->
    [
        annotate_lane(Index, Lane, FamilyId, Shape, ExternalIndex)
        || {Index, Lane} <- lists:enumerate(0, Lanes)
    ].

annotate_lane(Index, Lane, FamilyId, Shape, ExternalIndex) ->
    case maps:get(source, Lane) of
        FamilyId -> ok;
        Source -> error({unsupported_dslx_lane_source, Source})
    end,
    Stem = ["lane_", integer_to_list(Index)],
    Base = Lane#{index => Index, stem => Stem},
    case maps:get(destination, Lane) of
        {family, FamilyId, {translate, [DX, DY], wrap}} ->
            Base#{
                kind => family,
                inverse_shift => [
                    inverse_shift(DX, lists:nth(1, Shape)),
                    inverse_shift(DY, lists:nth(2, Shape))
                ]
            };
        {external, ExternalId} ->
            case maps:find(ExternalId, ExternalIndex) of
                {ok, External} ->
                    Base#{kind => external, external => External};
                error ->
                    error({unknown_dslx_family_lane_external, ExternalId})
            end;
        Destination ->
            error({unsupported_dslx_lane_destination, Destination})
    end.

inverse_shift(0, _Size) -> zero;
inverse_shift(Offset, _Size) when Offset > 0 ->
    {minus, Offset};
inverse_shift(Offset, _Size) ->
    {plus, -Offset}.

validate_lane_ports(Lanes, Outputs) ->
    Ports = lists:append([
        maps:get(source_ports, Lane) || Lane <- Lanes
    ]),
    case {lists:sort(Ports), lists:sort(Outputs)} of
        {Same, Same} -> ok;
        _ -> error({inconsistent_dslx_family_lane_ports,
            lists:sort(Outputs), lists:sort(Ports)})
    end.

validate_external_lanes(Externals, Lanes) ->
    lists:foreach(
        fun(External) ->
            Id = maps:get(id, External),
            Matches = [
                Lane || Lane <- Lanes,
                maps:get(kind, Lane) =:= external,
                maps:get(id, maps:get(external, Lane)) =:= Id
            ],
            case Matches of
                [_] -> ok;
                _ -> error({unsupported_dslx_family_external_lane_count,
                    Id, length(Matches)})
            end
        end,
        Externals
    ).

validate_profile(Profile) when is_map(Profile) ->
    Required = lists:sort([channel_depth, name]),
    Keys = lists:sort(maps:keys(Profile)),
    case {Required -- Keys, Keys -- Required} of
        {[], []} -> ok;
        {Missing, Unknown} ->
            error({invalid_dslx_profile_keys, Missing, Unknown})
    end,
    Name = identifier(maps:get(name, Profile), topology_name),
    case maps:get(channel_depth, Profile) of
        Depth when is_integer(Depth), Depth > 0, Depth =< ?U32_MAX -> ok;
        Depth -> error({invalid_dslx_channel_depth, Depth})
    end,
    Profile#{name := Name};
validate_profile(Profile) ->
    error({invalid_dslx_profile, Profile}).

identifier(Name, Context) when is_atom(Name) ->
    identifier(atom_to_list(Name), Context);
identifier(Name, Context) when is_list(Name) ->
    case re:run(Name, "^[a-z][a-z0-9_]*$", [{capture, none}]) of
        match ->
            case lists:member(Name, reserved_identifiers()) of
                true -> error({reserved_dslx_identifier, Context, Name});
                false -> Name
            end;
        nomatch -> error({invalid_dslx_identifier, Context, Name})
    end;
identifier(Name, Context) ->
    error({invalid_dslx_identifier, Context, Name}).

reserved_identifiers() ->
    [
        "as", "const", "else", "enum", "fn", "for", "if", "import",
        "in", "let", "match", "proc", "pub", "spawn", "struct",
        "type", "while"
    ].

%%%
%%% Rendering
%%%

render(Spec) ->
    [
        preamble(Spec),
        family_router(Spec),
        frame_grid_mux(maps:get(externals, Spec)),
        family_node(Spec),
        family_torus(Spec),
        top_proc(Spec)
    ].

preamble(Spec) ->
    Family = maps:get(family, Spec),
    [
        "// ", maps:get(name, Spec), ".x\n",
        "// Auto-generated by xls_topology_dslx from compact Erlang family ",
        "rules.\n",
        "// Manual changes will be overwritten.\n",
        "//\n",
        "// One reusable node and nested unroll_for! spawns retain regular ",
        "source structure.\n",
        "// Scalar external streams use fair polling over statically indexed ",
        "family lanes.\n\n",
        "import axis;\n",
        "import ", maps:get(module_name, Family), ";\n\n",
        "const CHANNEL_DEPTH = u32:", integer_to_list(maps:get(depth, Spec)),
        ";\n",
        "const WIDTH = u32:", integer_to_list(maps:get(width, Spec)), ";\n",
        "const HEIGHT = u32:", integer_to_list(maps:get(height, Spec)),
        ";\n\n"
    ].

family_router(Spec) ->
    Family = maps:get(family, Spec),
    Module = maps:get(module_name, Family),
    Lanes = maps:get(lanes, Spec),
    Outputs = maps:get(outputs, Family),
    PortIndex = maps:from_list(lists:append([
        [{Port, Lane} || Port <- maps:get(source_ports, Lane)]
        || Lane <- Lanes
    ])),
    [
        "proc FamilyRouter {\n",
        "  egress_in: chan<", Module, "::Egress> in;\n",
        [["  ", lane_output(Lane), ": chan<axis::Frame> out;\n"]
            || Lane <- Lanes],
        "\n",
        config_signature(
            [["egress_in: chan<", Module, "::Egress> in"] |
                [[lane_output(Lane), ": chan<axis::Frame> out"]
                    || Lane <- Lanes]],
            2
        ),
        "    (egress_in",
        [[", ", lane_output(Lane)] || Lane <- Lanes],
        ")\n  }\n\n",
        "  init { () }\n\n",
        "  next(state: ()) {\n",
        "    let (tok, egress) = recv(join(), egress_in);\n",
        "    let _route_tok = match egress.port {\n",
        [
            begin
                Lane = maps:get(Port, PortIndex),
                ["      ", Module, "::OutputPort::", uppercase(Port),
                    " => send(tok, ", lane_output(Lane),
                    ", egress.frame),\n"]
            end
            || Port <- Outputs
        ],
        "    };\n",
        "    state\n  }\n}\n\n"
    ].

frame_grid_mux([]) -> [];
frame_grid_mux(_Externals) ->
    %% DSLX writes array dimensions from inner to outer. Consequently
    %% `[GRID_HEIGHT][GRID_WIDTH]` has `GRID_WIDTH` outer elements and
    %% supports the coordinate order `frame_in[x][y]` used below.
    """
    proc FrameArrayMux<INPUT_COUNT: u32> {
      frame_in: chan<axis::Frame>[INPUT_COUNT] in;
      frame_out: chan<axis::Frame> out;

      config(
          frame_in: chan<axis::Frame>[INPUT_COUNT] in,
          frame_out: chan<axis::Frame> out
      ) {
        (frame_in, frame_out)
      }

      init { u32:0 }

      next(cursor: u32) {
        let (tok, received, frame) =
          unroll_for! (candidate, acc):
              (u32, (token, u1, axis::Frame)) in u32:0..INPUT_COUNT {
            let selected = cursor == candidate;
            let (next_tok, next_frame, valid) = recv_if_non_blocking(
              acc.0,
              frame_in[candidate],
              selected,
              zero!<axis::Frame>());
            (
              next_tok,
              acc.1 | valid,
              if valid { next_frame } else { acc.2 }
            )
          }((join(), u1:0, zero!<axis::Frame>()));
        let _done = send_if(tok, frame_out, received, frame);
        if cursor + u32:1 == INPUT_COUNT {
          u32:0
        } else {
          cursor + u32:1
        }
      }
    }

    proc FrameGridMux<GRID_WIDTH: u32, GRID_HEIGHT: u32> {
      config(
          frame_in: chan<axis::Frame>[GRID_HEIGHT][GRID_WIDTH] in,
          frame_out: chan<axis::Frame> out
      ) {
        let (column_p, column_c) =
          chan<axis::Frame, CHANNEL_DEPTH>[GRID_WIDTH]("grid_column");
        unroll_for! (x, _): (u32, ()) in u32:0..GRID_WIDTH {
          spawn FrameArrayMux<GRID_HEIGHT>(frame_in[x], column_p[x]);
        }(());
        spawn FrameArrayMux<GRID_WIDTH>(column_c, frame_out);
        ()
      }

      init { () }
      next(state: ()) { state }
    }

    """.

family_node(Spec) ->
    Family = maps:get(family, Spec),
    Module = maps:get(module_name, Family),
    FamilyLanes = maps:get(family_lanes, Spec),
    Lanes = maps:get(lanes, Spec),
    Inputs = [[incoming_name(Index), ": chan<axis::Frame> in"]
        || {Index, _Lane} <- lists:enumerate(0, FamilyLanes)],
    Outputs = [[lane_output(Lane), ": chan<axis::Frame> out"]
        || Lane <- Lanes],
    {IngressRoot, MuxCode} = node_mux_tree(length(FamilyLanes)),
    [
        "proc FamilyNode {\n",
        config_signature(Inputs ++ Outputs, 2),
        "    let (actor_req_p, actor_req_c) =\n",
        "      chan<axis::Frame, CHANNEL_DEPTH>(\"actor_req\");\n",
        "    let (actor_admit_p, actor_admit_c) =\n",
        "      chan<u1, CHANNEL_DEPTH>(\"actor_admit\");\n",
        "    let (actor_egress_p, actor_egress_c) =\n",
        "      chan<", Module, "::Egress, u32:",
        integer_to_list(maps:get(egress_depth, Family)),
        ">(\"actor_egress\");\n",
        "    spawn ", Module, "::Service(\n",
        "      actor_req_c, actor_egress_p, actor_admit_p);\n",
        "    spawn FamilyRouter(actor_egress_c",
        [[", ", lane_output(Lane)] || Lane <- Lanes],
        ");\n",
        MuxCode,
        "    spawn axis::ReservedFrame(", IngressRoot,
        ", actor_req_p, actor_admit_c);\n",
        "    ()\n  }\n\n",
        "  init { () }\n",
        "  next(state: ()) { state }\n",
        "}\n\n"
    ].

node_mux_tree(0) ->
    error(unsupported_dslx_family_without_inbound_lanes);
node_mux_tree(Count) ->
    Inputs = [incoming_name(Index) || Index <- lists:seq(0, Count - 1)],
    mux_tree(Inputs, 0, []).

mux_tree([Root], _Level, Code) -> {Root, Code};
mux_tree(Inputs, Level, Code0) ->
    {Next, Code} = mux_round(Inputs, Level, 0, [], []),
    mux_tree(Next, Level + 1, Code0 ++ Code).

mux_round([], _Level, _Pair, Next, Code) ->
    {lists:reverse(Next), Code};
mux_round([Last], _Level, _Pair, Next, Code) ->
    {lists:reverse([Last | Next]), Code};
mux_round([Left, Right | Rest], Level, Pair, Next, Code0) ->
    Stem = ["ingress_mux_", integer_to_list(Level), "_",
        integer_to_list(Pair)],
    Code = Code0 ++ [
        "    let (", Stem, "_p, ", Stem, "_c) =\n",
        "      chan<axis::Frame, CHANNEL_DEPTH>(\"", Stem, "\");\n",
        "    spawn axis::FrameMux2(", Left, ", ", Right, ", ", Stem,
        "_p);\n"
    ],
    mux_round(Rest, Level, Pair + 1, [Stem ++ "_c" | Next], Code).

family_torus(Spec) ->
    Lanes = maps:get(lanes, Spec),
    FamilyLanes = maps:get(family_lanes, Spec),
    Externals = maps:get(externals, Spec),
    [
        "proc FamilyTorus<TORUS_WIDTH: u32, TORUS_HEIGHT: u32> {\n",
        config_signature(
            [[maps:get(output_name, External),
                ": chan<axis::Frame> out"] || External <- Externals],
            2
        ),
        [lane_array(Lane) || Lane <- Lanes],
        "    unroll_for! (x, _): (u32, ()) in u32:0..TORUS_WIDTH {\n",
        "      unroll_for! (y, _): (u32, ()) in u32:0..TORUS_HEIGHT {\n",
        "        spawn FamilyNode(\n",
        node_spawn_arguments(FamilyLanes, Lanes),
        "        );\n",
        "      }(())\n",
        "    }(());\n",
        [external_merge_spawn(External, Lanes) || External <- Externals],
        "    ()\n  }\n\n",
        "  init { () }\n",
        "  next(state: ()) { state }\n",
        "}\n\n"
    ].

lane_array(Lane) ->
    %% As above, the rightmost dimension is the outer x dimension in DSLX.
    Stem = maps:get(stem, Lane),
    [
        "    let (", Stem, "_p, ", Stem, "_c) =\n",
        "      chan<axis::Frame, CHANNEL_DEPTH>",
        "[TORUS_HEIGHT][TORUS_WIDTH](\"", Stem, "\");\n"
    ].

node_spawn_arguments(FamilyLanes, Lanes) ->
    Arguments =
        [family_lane_consumer(Lane) || Lane <- FamilyLanes] ++
        [[maps:get(stem, Lane), "_p[x][y]"] || Lane <- Lanes],
    [
        ["          ", Argument, separator(Index, length(Arguments)), "\n"]
        || {Index, Argument} <- lists:enumerate(0, Arguments)
    ].

family_lane_consumer(Lane) ->
    [DX, DY] = maps:get(inverse_shift, Lane),
    [maps:get(stem, Lane), "_c[", shifted_index("x", DX, "TORUS_WIDTH"),
        "][", shifted_index("y", DY, "TORUS_HEIGHT"), "]"].

shifted_index(Axis, zero, _Size) -> Axis;
shifted_index(Axis, {plus, Offset}, Size) ->
    ["(", Axis, " + u32:", integer_to_list(Offset), ") % ", Size];
shifted_index(Axis, {minus, Offset}, Size) ->
    ["(", Axis, " + ", Size, " - u32:", integer_to_list(Offset),
        ") % ", Size].

external_merge_spawn(External, Lanes) ->
    [Lane] = [
        Candidate || Candidate <- Lanes,
        maps:get(kind, Candidate) =:= external,
        maps:get(id, maps:get(external, Candidate)) =:= maps:get(id, External)
    ],
    [
        "    spawn FrameGridMux<TORUS_WIDTH, TORUS_HEIGHT>(",
        maps:get(stem, Lane), "_c, ", maps:get(output_name, External),
        ");\n"
    ].

top_proc(Spec) ->
    Externals = maps:get(externals, Spec),
    [
        "pub proc Top {\n",
        [["  ", maps:get(output_name, External),
            ": chan<axis::Frame> out;\n"] || External <- Externals],
        "\n",
        config_signature(
            [[maps:get(output_name, External),
                ": chan<axis::Frame> out"] || External <- Externals],
            2
        ),
        "    spawn FamilyTorus<WIDTH, HEIGHT>(",
        join_with(", ", [maps:get(output_name, External)
            || External <- Externals]),
        ");\n",
        "    ", external_tuple(Externals), "\n",
        "  }\n\n",
        "  init { () }\n",
        "  next(state: ()) { state }\n",
        "}\n"
    ].

config_signature(Arguments, Indent) ->
    Padding = lists:duplicate(Indent + 2, $ ),
    [
        lists:duplicate(Indent, $ ), "config(\n",
        [
            [Padding, Argument, separator(Index, length(Arguments)), "\n"]
            || {Index, Argument} <- lists:enumerate(0, Arguments)
        ],
        lists:duplicate(Indent, $ ), ") {\n"
    ].

incoming_name(Index) -> ["incoming_", integer_to_list(Index)].
lane_output(Lane) -> [maps:get(stem, Lane), "_out"].

separator(Index, Arity) when Index + 1 < Arity -> ",";
separator(_Index, _Arity) -> "".

external_tuple([]) -> "()";
external_tuple([External]) -> ["(", maps:get(output_name, External), ",)"];
external_tuple(Externals) ->
    ["(", join_with(", ", [maps:get(output_name, External)
        || External <- Externals]), ")"].

uppercase(Atom) -> string:uppercase(atom_to_list(Atom)).

join_with(_Separator, []) -> [];
join_with(Separator, [First | Rest]) ->
    [First | [[Separator, Item] || Item <- Rest]].
