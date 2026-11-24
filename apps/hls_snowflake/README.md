# Snowflake application

`hls_snowflake` owns ordinary Snowflake actors, geometry, the sequential BEAM reference and its finite independent fixtures. `hls_lowering` supplies topology planning and hardware generation, `hls_core` supplies shared values, and `hls_runtime` supplies actor execution. This is a build/example library, not part of the deployed Fabric runtime closure.

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

Use `rebar3 release -n hls` to prepare that driver for an already-emitted bundle. To relocate the Snowflake sources and configuration as well, use `rebar3 release -n hls_examples` and copy that complete release; its application closure includes `hls_snowflake`. The same retained configuration can be written as one Erlang term for the generic CLI's `--config` option; no Snowflake-specific Python transformation is needed for this path. Hardware generation alone is not a clock, resource or live-device qualification.

## Source owners and checks

- `src/snowflake_vertex`, `snowflake_coordinator` and `snowflake_barrier` implement ordinary actors; `snowflake_actor_topology` defines their connectivity and startup.
- `src/snowflake_node`, `snowflake_geometry` and `snowflake_window` define local transitions and the sequential reference. `snowflake_actor_run` checks the communicating BEAM actors against that reference.
- `include/` owns the shared actor/vertex records and macros. Compile-time experiment options remain explicit; the default coordinated protocol is unchanged.
- `test/` owns localized actor and reference checks, including the shared phase-witness exporter used by experimental hardware probes. `priv/fixtures/` holds the unchanged named/enumerated corpora and their provenance; fixture loading uses the installed application's private directory.
- [`reference/`](reference/README.md) regenerates finite witnesses from pinned, unchanged localuf. These generators and their Python dependencies are optional reference tooling, not HLS compiler dependencies.

The repository's one Snowflake integration uses `snowflake_source:config/0`, compares eight sheets with the existing BEAM oracle, and checks public RTL under stalls/reset. The application fixtures provide finite agreement evidence; they do not establish a decoder threshold or unrestricted correctness.
