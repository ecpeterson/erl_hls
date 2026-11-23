# Snowflake semantic witnesses

These EUnit modules check local vertex transitions, completion barriers, coordinator behavior, communicating actors, source configuration and placement. `snowflake_window_tests` compares finite repetition and surface-code streams with the independently generated [fixture corpus](../priv/fixtures/README.md), including committed state and correction retirements.

`snowflake_phase_witness` exports complete phase snapshots, proposals and retirements for experimental implementation comparisons. Its explicit fixture word layout is separate from the actor transport ABI. `snowflake_barrier_tests.inc.x` is a DSLX test fragment appended by `snowflake_barrier_tests:write_dslx/1` to the normally lowered barrier; it is not a standalone support module.

The repository integration harness exercises the small source-protocol application with external XLS/RTL tools. Larger custom kernels and scheduling probes remain in [experiments](../../../experiments/snowflake/README.md). Finite agreement does not establish a threshold or unrestricted decoder correctness.
