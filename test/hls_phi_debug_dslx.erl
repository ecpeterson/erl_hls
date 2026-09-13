-module(hls_phi_debug_dslx).
-moduledoc "Complete D3 phi-memory fixture for cumulative debug cost and live diagnostics.".
-export([fixture/1, write/3]).

fixture(Shards) ->
    #{distance := Distance, noise_rate := Rate} = phi_memory_demo:fixture(),
    Plan = hls_topology:normalize(phi_noise_topology:topology(Distance, Rate)),
    Profile = phi_noise_topology_dslx:profile({phi_shards, Shards}),
    {Plan, Profile}.

write(Stage, Enabled, Shards) ->
    {Plan, Profile} = fixture(Shards),
    Options = #{mailbox_debug => Enabled},
    Artifacts = maps:map(fun(Module, Requirement) ->
        xls_parse:to_xls(filename:join("src/examples/phi_decoder", atom_to_list(Module) ++ ".erl"),
            maps:merge(Requirement, Options))
    end, xls_topology_dslx:artifact_requirements(Plan, Profile)),
    maps:foreach(fun(Module, Artifact) -> write_file(Stage, atom_to_list(Module) ++ ".x", Artifact) end, Artifacts),
    write_file(Stage, "phi_noise_topology.x", xls_topology_dslx:emit(Plan, maps:merge(Profile, Options))),
    write_file(Stage, "phi_memory_gateway.x", phi_memory_gateway_dslx:to_dslx(3, {phi_shards, Shards}, Options)),
    write_file(Stage, "phi_memory_top.v", phi_memory_debug_top_v:application({phi_shards, Shards}, Options)),
    write_file(Stage, "actors.json", json:encode(xls_scheduler_debug:projection(Plan,
        maps:get(scheduler_groups, Profile), Artifacts, Options))).

write_file(Stage, Name, Data) -> file:write_file(filename:join(Stage, Name), Data).
