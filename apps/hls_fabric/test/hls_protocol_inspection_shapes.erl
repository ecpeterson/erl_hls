-module(hls_protocol_inspection_shapes).
-moduledoc "Small process-inspection fixtures compared with independently unpacked typed state.".
-export([write/2]).

-doc "Writes ordinary actors, packed projections and typed-state reference properties into a fresh directory. These compiler shapes do not claim a connected application or admission.".
-spec write(file:filename(), file:filename()) -> ok.
write(Compiler, Stage) ->
    ok = file:make_dir(Stage),
    Cases = [{plain, "apps/hls_fabric/test/hls_local_actor_fixture.erl"},
        {scalar, filename:join(Compiler, "test_data/hls_statem_reduction_lower_fixture.erl")},
        {gather, filename:join(Compiler, "test_data/xls_statem_gather_fixture.erl")},
        {gather_sites, filename:join(Compiler, "test_data/xls_statem_gather_sites_fixture.erl")}],
    lists:foreach(fun({Name, File}) -> write_case(Name, File, Stage) end, Cases).

%% Use the public actor and inspection emitters, then append a typed reference to the actor module.
-spec write_case(atom(), file:filename(), file:filename()) -> ok.
write_case(Name, File, Stage) ->
    Actor = #{program := Program} = hls_local_actor:compile(File, []),
    Spec = xls_actor_program:spec(Program),
    Directory = filename:join(Stage, atom_to_list(Name)),
    ok = file:make_dir(Directory),
    ActorFile = filename:join(Directory, "actor.x"),
    Manifest = hls_local_actor:write(Actor, ActorFile),
    #{<<"resources">> := [Resource]} = hls_protocol_inspection:write(#{
        bundle => #{topology => #{actors => [#{id => Name, module => Name}]}, modules => #{Name => Actor}},
        receivers => [#{index => 0, module => Name, manifest => Manifest}]}, Directory),
    {ok, Source} = file:read_file(ActorFile),
    file:write_file(filename:join(Directory, "shape.x"), [Source, reference(Spec, Resource)], [exclusive]).

%% The reply manifest supplies destinations; the reference never reads packed source offsets.
-spec reference(map(), map()) -> iodata().
reference(Spec, Resource) ->
    Fields = maps:get(<<"fields">>, maps:get(<<"reduction">>, Resource, #{}), #{}),
    Pieces = ["(bits[128]:1 << u32:25)", "(m.phase as bits[128])",
        "((m.enter_pending as bits[128]) << u32:8)", "((m.failure as bits[128]) << u32:9)"] ++
        [["((", collection_field(binary_to_existing_atom(Name), Width, Spec),
            " as bits[128]) << u32:", integer_to_list(Offset), ")"] ||
            {Name, #{<<"width">> := Width, <<"observation_offset">> := Offset}} <- lists:sort(maps:to_list(Fields)), Width > 0],
    ["\nimport process_observation as view;\n",
        "// All raw machine bits and both flags; typed unpacking supplies the reference metadata.\n",
        "pub fn metadata(raw: MachineBits, initialized: bool, reset: bool) -> bool {\n",
        "  let m = local_machine(raw, u32:0);\n",
        "  let expected = if reset || !initialized { bits[128]:0 } else { ", lists:join(" | ", Pieces), " };\n",
        "  view::observe_0(raw, initialized, reset) == expected\n}\n"].

%% Active gathers take priority; idle gathers expose scalar metadata or zero when no scalar exists.
-spec collection_field(atom(), pos_integer(), map()) -> iodata().
collection_field(Name, Width, #{reductions := Reduction, gathers := Gather}) ->
    Type = ["bits[", integer_to_list(Width), "]"],
    Scalar = case Reduction of
        none -> [Type, ":0"];
        _ -> scalar_field(Name, Type, Reduction)
    end,
    case Gather of
        none -> Scalar;
        _ ->
            Value = ["(m.gather.progress.", atom_to_list(Name), " as ", Type, ")"],
            Count = case Reduction of none -> 0; #{sites := Sites} -> length(Sites) end,
            Indexed = case Name of
                site -> ["(", Value, " + ", Type, ":", integer_to_list(Count), ")"];
                _ -> Value
            end,
            ["(if m.gather.progress.status != GatherStatus::IDLE { ", Indexed,
                " } else { ", Scalar, " })"]
    end.

%% Count-only scalar folds have no expected-member mask in their typed state.
-spec scalar_field(atom(), iodata(), map()) -> iodata().
scalar_field(expected, Type, Reduction) ->
    case xls_statem_reduction_ir:has_runtime_members(Reduction) of
        false -> [Type, ":0"];
        true -> ["(m.reduction.expected as ", Type, ")"]
    end;
scalar_field(Name, Type, _) -> ["(m.reduction.", atom_to_list(Name), " as ", Type, ")"].
