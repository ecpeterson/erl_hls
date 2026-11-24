# hls_snowflake: Snowflake streaming-decoder workload

[Snowflake](https://arxiv.org/abs/2406.01701) is a distributed streaming decoder for quantum surface codes. It grows and merges local clusters around detection events inside a fixed-height decoding window, then commits corrections for older syndrome layers as they leave that window. In the algorithm's metaphor, those locally grown clusters are the “snowflakes” falling through the window. This application is unrelated to the Snowflake data platform.

`hls_snowflake` is the umbrella's maintained implementation of that public algorithm. It contains ordinary Erlang actors, geometry, a sequential BEAM reference and independently generated finite fixtures. The workload exercises computation synthesis, actor topology planning, runtime execution and target materialization without making any of those generic applications depend on a decoder.

Maintained end-to-end applications live below `workloads/`, separate from the reusable applications under `apps/`. The default development profile compiles Snowflake, the `hls_workloads` release packages it, and the generic `hls` and deployed `hls_runtime` releases omit it. See the [workload map](../README.md) for the package categories and dependency direction.

## Choose an entry point

| Goal | Start here |
| --- | --- |
| Check the sequential and communicating Erlang implementations without external synthesis tools | `rebar3 eunit --app hls_snowflake` from the repository root |
| Understand the actor split, geometry and algorithm phases | [`src/README.md`](src/README.md) |
| Inspect the independently generated finite reference corpus | [`priv/fixtures/README.md`](priv/fixtures/README.md) |
| Reproduce the corpus from pinned upstream `localuf` | [`reference/README.md`](reference/README.md) |
| Emit the maintained source-to-hardware workload | Continue with the source-protocol build below |

## Source-protocol build

Compile the repository with `rebar3 compile`, then use the common build frontend from a rebar shell:

```erlang
Config = snowflake_source:config().
hls_source_build:write(boundary, Config, "/tmp/snowflake-source").
```

The configuration selects the existing small distance-two, height-two window: twelve vertices plus a coordinator, a flat completion barrier, explicit startup and independently buffered command copies. It retains the coordinator's twelve-source and sixteen-message bounds. `snowflake_source:config/0` resolves sources and includes from the installed application, so the caller's working directory does not select another source tree. `snowflake_actor_topology:topology/0` retains its original distance-three, height-three default for other callers.

This writes a generic source-build bundle without running XLS. The shared external driver consumes that bundle:

```sh
_build/default/rel/hls/bin/compile-source-build /path/to/xls /tmp/snowflake-source
```

Use `rebar3 release -n hls` to prepare that driver for an already-emitted bundle. To relocate the Snowflake sources and configuration as well, use `rebar3 release -n hls_workloads` and copy that complete release; its application closure includes `hls_snowflake`. The same retained configuration can be written as one Erlang term for the generic CLI's `--config` option; no Snowflake-specific Python transformation is needed for this path. Hardware generation alone is not a clock, resource or live-device qualification.

## Package contents

| Directory | Responsibility |
| --- | --- |
| [`src`](src/README.md) | Local decoder transitions, sequential window, communicating actors, topology and source-build configuration |
| [`include`](include/README.md) | Shared actor records, protocol bounds and the common vertex transition body |
| [`priv/fixtures`](priv/fixtures/README.md) | Installed finite reference inputs and their provenance |
| [`reference`](reference/README.md) | Optional pinned-upstream fixture regeneration; its Python packages are not compiler dependencies |
| [`test`](test/README.md) | Sequential/actor agreement, phase, placement and source-configuration witnesses |

The repository's Snowflake integration uses `snowflake_source:config/0`, compares eight sheets with the existing BEAM oracle, and checks public RTL under stalls/reset. The application fixtures provide finite agreement evidence; they do not establish a decoder threshold or unrestricted correctness.
