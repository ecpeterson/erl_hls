# Phi external drivers

These checkout tools compile emitted sources, run bounded simulation witnesses and analyze recordings for the Phi example. Shared compiler invocation and generic transport helpers remain in the repository's `tools/`. `phi_tool_paths` exposes that common tooling without selecting another compiler checkout or changing child process settings.

Invoke scripts from the repository root; generated outputs belong in fresh build stages or the external artifact archive. Shell staging retains explicit sources and support files for remote execution. Running a profile or build driver is distinct from starting a board or an EC2 instance.

The generic scheduler RAM configuration helper lives at `tools/scheduler_ram_configurations.sh`; it also serves small backend regressions unrelated to Phi.

For the optional dedicated distance-three noise graph check, first compile the checkout with `rebar3 as test compile`, then run:

```sh
bash apps/hls_phi/tools/check_dedicated_noise.sh /path/to/xls /absolute/new-stage
```

The stage must not already exist. The helper uses the selected test profile's current Erlang lowerers to emit the three ordinary actors and `phi_noise_topology_dslx` graph, checks all four sources against their retained goldens, and converts `Top` to XLS IR. It retains generated sources, `generation.log`, `elaboration.log` and `phi_noise_topology.ir`, including partial output on failure. This restores the dedicated graph elaboration check independently of shared-scheduler staging; it performs no optimization, RTL generation or simulation and is not an additional CI integration test.
