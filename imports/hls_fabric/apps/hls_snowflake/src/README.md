# Snowflake source

This application owns the decoder's ordinary actor implementation and its sequential BEAM reference. The compiler and fabric libraries supply actor execution, topology planning and hardware generation; they do not select Snowflake rules.

- `snowflake_node`, `snowflake_geometry` and `snowflake_window` define local transitions, bounded geometry and sequential phase execution for repetition and planar surface-code windows. Reference ticks are algorithm steps, not hardware cycles.
- `snowflake_vertex`, `snowflake_coordinator` and `snowflake_barrier` implement the communicating actors. `snowflake_actor_topology` owns their routes, startup and optional placement. `snowflake_actor_run` compares finite communicating runs with the sequential reference.
- `snowflake_source` selects the small source-protocol example and resolves installed source/include paths. The [application guide](../README.md) describes its bounds and build entry point.

Shared records and transition bodies live in [include](../include/README.md). Custom kernel RTL and scheduler ablations remain in [experiments](../../../experiments/snowflake/README.md), which consume this application source.
