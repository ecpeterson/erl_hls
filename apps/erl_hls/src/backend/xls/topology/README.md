# Dedicated actor topology

`xls_topology_dslx` is the facade for wiring normalized logical [topology plans](../../../topology/README.md). It selects `xls_topology_family_dslx` for compact regular families or `xls_topology_instance_dslx` for materialized instances.

`xls_topology_profile` validates physical options before preparation. `xls_topology_graph` retains checked actor interfaces, startup frames and route lanes; `xls_topology_ingress` validates bounded rectangle ingress and supplies its selector fragments. Retained-interface entry points reuse an existing catalog rather than reacquiring actor source.

The renderers consume [actor compilation](../actors/README.md) and [target documents](../emission/README.md). Each dedicated actor owns register-backed state and its bounded mailbox. Shared RAM placement, source-protocol transport and scheduling policies belong to the fabric lowering application; this directory does not own host transport or deployed sessions.
