# Snowflake shared declarations

`snowflake_actor_protocol.hrl` owns actor message records and bounded protocol constants. `snowflake_node.hrl` and `snowflake_barrier.hrl` define the state shared by their implementation and tests. `snowflake_node_impl.hrl` contains the common local transition functions used by the node and actor implementations, avoiding a second copy of the decoder rules.

Explicit compile-time options select the documented experimental variants; including these files does not select a hardware scheduler or deployment. The localuf-derived transitions retain their [MIT attribution](../reference/LICENSE.localuf). Source-build configurations must retain this include directory with the [application source](../src/README.md).
