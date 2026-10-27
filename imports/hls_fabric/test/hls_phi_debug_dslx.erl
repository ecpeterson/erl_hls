-module(hls_phi_debug_dslx).
-moduledoc "Complete D3 phi-memory fixture for cumulative debug cost and live diagnostics.".
-export([fixture/1, write/3]).

-doc "Builds the selected test topology and its matching execution profile.".
-spec fixture(term()) -> {term(),term()}.
fixture(Shards) ->
    #{distance := Distance, noise_rate := Rate} = phi_memory_demo:fixture(),
    Plan = hls_topology:normalize(phi_noise_topology:topology(Distance, Rate)),
    Profile = phi_shared_noise_topology_dslx:profile({phi_shards, Shards}),
    {Plan, Profile}.

-doc "Writes generated DSLX and the matching oracle or wrapper files into the test stage.".
-spec write(atom() | binary() | [atom() | [any()] | char()],term(),term()) -> 'ok' | {'error',atom()}.
write(Stage, Enabled, Shards) ->
    {Plan, Profile} = fixture(Shards),
    Options = #{mailbox_debug => Enabled},
    Artifacts = maps:map(fun(Module, Requirement) ->
        xls_shared_parse:to_artifact(filename:join("src/examples/phi_decoder", atom_to_list(Module) ++ ".erl"),
            maps:merge(Requirement, Options))
    end, xls_shared_topology_dslx:artifact_requirements(Plan, Profile)),
    maps:foreach(fun(Module, Artifact) -> write_file(Stage, atom_to_list(Module) ++ ".x", xls_emitted:bytes(Artifact)) end, Artifacts),
    write_file(Stage, "phi_noise_topology.x", xls_shared_topology_dslx:emit(Plan, maps:merge(Profile, Options))),
    write_file(Stage, "phi_memory_gateway.x", phi_memory_gateway_dslx:to_dslx(3, {phi_shards, Shards}, Options)),
    write_file(Stage, "phi_memory_top.v", phi_memory_debug_top_v:application({phi_shards, Shards}, Options)),
    write_file(Stage, "actors.json", json:encode(xls_scheduler_debug:projection(Plan,
        maps:get(scheduler_groups, Profile), Artifacts, Options))).

%% Writes one generated test artifact below the selected stage.
-spec write_file(atom() | binary() | [atom() | [any()] | char()],nonempty_string(),binary() | maybe_improper_list(binary() | maybe_improper_list(any(),binary() | []) | byte(),binary() | [])) -> 'ok' | {'error',atom()}.
write_file(Stage, Name, Data) -> file:write_file(filename:join(Stage, Name), Data).
