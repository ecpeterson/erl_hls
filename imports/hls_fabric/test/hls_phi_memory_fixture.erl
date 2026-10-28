-module(hls_phi_memory_fixture).
-moduledoc "Full phi memory witness with global geometry and an initial cutoff on every device.".
-export([fixture/0, fixture/1, write/1, write/2, write/3, write/4, write/5, write/6, write/7, oracle/1, cpu/2]).

-doc "Returns the D3 experiment, split after global family row zero, with cutoff queued before actor activation.".
-spec fixture() -> {hls_topology:plan(), map(), map()}.
fixture() ->
    fixture(d3).

-doc "Selects the established D3 witness, a noisy or quiet board-sized measurement, or the D6 four-neighbor mesh.".
-spec fixture(d3 | board_memory | board_quiet | mesh_memory) -> {hls_topology:plan(), map(), map()}.
fixture(Case) ->
    #{distance := Distance, noise_rate := Rate, options := Options} = config(Case),
    {_, [{control_router, noise, _, Cutoff}]} = phi_memory_experiment:new(Options),
    Spec = #{startup := Startup} = phi_noise_topology:topology(Distance, Rate),
    Seeded = [{Id, case Id of
        {Family, _, _} when Family =:= phi_x; Family =:= phi_z -> Messages;
        _ -> Messages ++ [Cutoff]
    end} || {Id, Messages} <- Startup],
    Plan = #{families := Families} = hls_topology:normalize(Spec#{startup := Seeded}),
    Placement = case Distance of
        N when N rem 2 =:= 0 -> hls_phi_board_geometry:placement(Distance);
        3 -> maps:from_list([{{family, Family, [X, Y]}, case Y of 0 -> 0; _ -> 1 end}
            || #{id := Family} <- Families, X <- lists:seq(0, Distance-1), Y <- lists:seq(0, Distance-1)])
    end,
    {Plan, Placement, Options}.

-doc "Writes independently compilable graphs and their deployment/experiment metadata.".
-spec write(file:filename()) -> ok.
write(Stage) -> write(Stage, direct).

-doc "Writes the same witness with direct actors, family-local RAM executors, or coalesced module-local executors capped at twelve actors each.".
-spec write(file:filename(), direct | shared | coalesced) -> ok.
write(Stage, Mode) -> write(Stage, Mode, d3).

-doc "Writes the selected complete workload at the requested storage placement.".
-spec write(file:filename(), direct | shared | coalesced, d3 | board_memory | board_quiet | mesh_memory) -> ok.
write(Stage, Mode, Case) ->
    write(Stage, Mode, Case, #{}).

-doc "Writes the complete workload with per-module actor caps for coalesced schedulers. Other placements require an empty override map.".
-spec write(file:filename(), direct | shared | coalesced,
    d3 | board_memory | board_quiet | mesh_memory, #{module() => pos_integer()}) -> ok.
write(Stage, Mode, Case, Limits) ->
    write(Stage, Mode, Case, Limits, ordinary).

-doc "Writes matched ordinary or source-fragment reduction hardware. Offloading reuses the public complete-topology proof and aggregate-only actor artifacts.".
-spec write(file:filename(), direct | shared | coalesced,
    d3 | board_memory | board_quiet | mesh_memory, #{module() => pos_integer()}, ordinary | source_fragments) -> ok.
write(Stage, Mode, Case, Limits, ReductionMode) ->
    write(Stage, Mode, Case, Limits, ReductionMode, serial).

-doc "Writes the complete witness with a uniform peer transport; application and actor encodings are unchanged.".
-spec write(file:filename(), direct | shared | coalesced,
    d3 | board_memory | board_quiet | mesh_memory, #{module() => pos_integer()},
    ordinary | source_fragments, hls_partition_links:transport()) -> ok.
write(Stage, Mode, Case, Limits, ReductionMode, Transport) ->
    write(Stage, Mode, Case, Limits, ReductionMode, Transport, false).

-doc "Optionally emits congruent D6 coalesced tiles with wrapper-bound configuration; other fixtures retain independent compilation.".
-spec write(file:filename(), direct | shared | coalesced,
    d3 | board_memory | board_quiet | mesh_memory, #{module() => pos_integer()},
    ordinary | source_fragments, hls_partition_links:transport(), boolean()) -> ok.
write(Stage, Mode, Case, Limits, ReductionMode, Transport, Tile) ->
    true = not Tile orelse (Mode =:= coalesced andalso Case =:= mesh_memory),
    {Plan, Placement, Options} = fixture(Case),
    Direct = hls_partition_links:configure(hls_partition:normalize(Plan, Placement), Transport),
    Scheduled = case Mode of
        direct when map_size(Limits) =:= 0 -> Direct;
        coalesced -> hls_partition_schedule:shared_by_module(Direct, 12, Limits);
        shared when map_size(Limits) =:= 0 ->
            Groups = lists:foldl(fun(#{identity := Id = {family, F, _}, device := D}, Acc) ->
                maps:update_with({D, F}, fun(Ids) -> [Id | Ids] end, [Id], Acc)
            end, #{}, maps:get(actors, Direct)),
            hls_partition_schedule:shared(Direct, Groups)
    end,
    Reduced = case ReductionMode of
        ordinary -> Scheduled;
        source_fragments -> hls_partition_reduction:attach(Plan, Scheduled,
            #{phi_x => source_fragments, phi_z => source_fragments})
    end,
    Partition = case Tile of
        true -> tile_layout(Reduced, Limits);
        false -> Reduced
    end,
    Requirements = hls_partition_reduction:requirements(Partition),
    Deployment = hls_partition_binding:deployment(Partition),
    Dependency = code:lib_dir(erl_hls),
    Artifacts = maps:from_list([begin
        Source = filename:join([Dependency, "src", "examples", "phi_decoder", atom_to_list(Module) ++ ".erl"]),
        Artifact = xls_scheduler_actor:to_artifact(Source,
            (maps:get(Module, Requirements, #{shared_service => ordinary}))#{mailbox_debug => Mode =/= direct}),
        save(Stage, atom_to_list(Module) ++ ".x", xls_emitted:bytes(Artifact)),
        {Module, Artifact}
    end || Module <- [phi_halo_cell, phenom_syndrome_cell, phenom_data_cell]]),
    Devices = [begin
        Local = #{tx_lanes := Tx, rx_lanes := Rx, links := Links, externals := Externals, ingresses := Ingresses} =
            hls_partition:device(Partition, Device),
        Name = list_to_atom("device_" ++ integer_to_list(Device) ++ "_graph"),
        Module = case Tile of true -> tile_graph; false -> Name end,
        Graph = iolist_to_binary(hls_partition_dslx:emit(Partition, Device,
            #{name => Module, channel_depth => 1, actor_egress_depth => burst})),
        save(Stage, atom_to_list(Name) ++ ".x", Graph),
        case Tile of
            true -> same_source(Stage, "tile_graph.x", Graph);
            false -> ok
        end,
        save(Stage, "phi_device_" ++ integer_to_list(Device) ++ ".x",
            xls_partition_application:emit(Deployment, Device, Module)),
        Bound = case Tile of
            true ->
                Binding = maps:get(Device, maps:get(devices, Deployment)),
                Constants = hls_partition_tile:constants(Local, Binding),
                save(Stage, "phi_device_" ++ integer_to_list(Device) ++ "_config.json",
                    json:encode([#{name => N, width => W, value => integer_to_binary(V, 16)} || {N, W, V} <- Constants])),
                same_source(Stage, "phi_tile.x", iolist_to_binary(xls_partition_application:emit(Deployment, Device, Module))),
                Local#{tile_constants => Constants};
            false -> Local
        end,
        Banks = case Mode of direct -> 0; _ -> hls_partition_ram:write(Stage, Device, Bound, Artifacts) end,
        #{id => Device, graph => Name, tile => Tile, application => true, scheduler_count => Banks, rx_lanes => length(Rx), tx_lanes => length(Tx),
            transport => Transport, link_width => hls_partition_links:width(Local),
            links => [#{index => I, peer => Peer, tx_lanes => length(LTx), rx_lanes => length(LRx)}
                || #{index := I, peer := Peer, tx_lanes := LTx, rx_lanes := LRx} <- Links],
            ingresses => [#{port => iolist_to_binary(Input)} || #{input_name := Input} <- Ingresses],
            externals => [#{index => Index, port => iolist_to_binary(Port), name => Id}
                || #{id := Id, index := Index, port := Port} <- Externals]}
    end || Device <- maps:get(devices, Partition)],
    save(Stage, "deployment.term", io_lib:format("~w.~n", [Partition])),
    save(Stage, "config.term", io_lib:format("~w.~n", [Options])),
    save(Stage, "bridge.json", json:encode(#{devices => Devices, reductions => ReductionMode,
        partition_fingerprint => binary:encode_hex(crypto:hash(sha256,
            term_to_binary(Partition, [deterministic])), lowercase)})).

%% Physical roles are independent of global torus coordinates, including the wrap seam.
-spec tile_layout(map(), map()) -> map().
tile_layout(P, Limits) ->
    {Roles, Peers} = hls_phi_board_geometry:tile_roles(6),
    hls_partition_tile:schedule(hls_partition_tile:prepare(P, Roles, Peers), 12, Limits).

%% Reuse requires exact generated source equality, not a guessed geometric equivalence.
-spec same_source(file:filename(), string(), binary()) -> ok.
same_source(Stage, Name, Source) ->
    case file:read_file(filename:join(Stage, Name)) of
        {error, enoent} -> save(Stage, Name, Source);
        {ok, Source} -> ok;
        {ok, _} -> error({noncongruent_tile, Name})
    end.

-doc "Records the selected independent BEAM witness; the D3 case also checks its established golden.".
-spec oracle(file:filename()) -> ok.
oracle(Stage) ->
    {ok, [Options]} = file:consult(filename:join(Stage, "config.term")),
    Witness = case Options of
        #{distance := 3} ->
            Result = {ok, W} = phi_memory_demo:run_cpu(),
            ok = phi_memory_demo:verify(Result), W;
        #{} -> cpu(Options, 10000)
    end,
    save(Stage, "oracle.term", io_lib:format("~w.~n", [Witness])).

%% Keep generated inputs and evidence beside their owning build.
-spec save(file:filename(), file:filename(), iodata()) -> ok.
save(Stage, Name, Contents) -> ok = file:write_file(filename:join(Stage, Name), Contents).

%% Both board-sized cases finish with the ordinary quiet fence and final measurements.
-spec config(d3 | board_memory | board_quiet | mesh_memory) -> map().
config(d3) -> phi_memory_demo:fixture();
config(mesh_memory) ->
    Options = #{distance => 6, noise_rate => 16#80000000, first_quiet_step => 16,
        line_y => 6, measurement => z, request_id => 16#504849},
    #{distance => 6, noise_rate => 16#80000000, options => Options};
config(Case) when Case =:= board_memory; Case =:= board_quiet ->
    {Rate, Quiet} = case Case of
        board_memory -> {16#80000000, 16};
        board_quiet -> {0, 18}
    end,
    Options = #{distance => 2, noise_rate => Rate, first_quiet_step => Quiet,
        line_y => 2, measurement => z, request_id => 16#504849},
    #{distance => 2, noise_rate => Rate, options => Options}.

-doc "Runs fresh BEAM actors to quiet closeout and all final measurements; propagates runner errors.".
-spec cpu(map(), pos_integer()) -> phi_memory_experiment:witness().
cpu(Options = #{distance := D, noise_rate := Rate}, Timeout) ->
    {ok, Fabric} = phi_memory_cpu_fabric:start_link(D, Rate),
    try
        {ok, Runner} = phi_memory_runner:start_link(Fabric, Options, Timeout),
        try
            {ok, Witness} = phi_memory_runner:await(Runner),
            Witness
        after phi_memory_runner:stop(Runner) end
    after phi_memory_cpu_fabric:stop(Fabric) end.
