# Dedicated actor topology

`xls_topology_dslx` is the communication renderer for normalized logical [topology plans](../../../../../hls_compile/src/topology/README.md). It selects `xls_topology_family_dslx` for compact regular families or `xls_topology_instance_dslx` for materialized instances.

`xls_topology_profile` adds compiler-specific reserved names and observation selection to the common `hls_implementation_constraints` profile before preparation. `xls_topology_graph` retains checked actor interfaces, startup frames and route lanes; `xls_topology_ingress` validates bounded rectangle ingress and supplies its selector fragments. Retained-interface entry points reuse an existing catalog rather than reacquiring actor source.

The renderers consume [actor compilation](../../../../../hls_compile/src/backend/xls/actors/README.md) and [compiler emission documents](../../../../../hls_compile/src/backend/xls/emission/README.md). Each dedicated actor owns register-backed state and its bounded mailbox. Physical placement, source-protocol materialization and scheduler RAM layout belong to [`hls_target`](../../../../../hls_target/src/planning/scheduler/README.md); this directory does not own host transport or deployed sessions.
