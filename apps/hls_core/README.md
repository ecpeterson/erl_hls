# hls_core: shared values and models

`hls_core` owns the process-free values shared by actor source, computation synthesis, communication planning, target materialization, deployed execution and characterization. It contains type descriptors and providers, record and frame layouts, deterministic collection and PRNG helpers, retained host codec primitives, structured diagnostics and stable logical actor keys.

The application depends only on OTP `kernel`, `stdlib` and `crypto`. It has no application callback, supervisor, registered process or dependency on compiler, Fabric, target, runtime or optimization applications. Consumers start no service when they load it.

The [value API](src/api/README.md) preserves the existing Erlang terms and encoding contracts. The [support modules](src/support/README.md) provide pure bitstream operations, diagnostics and actor-key hashing. The [model modules](src/model/README.md) own logical identities, source-independent process interfaces, logical topology, proposed implementation plans, retained descriptors and exactly correlated characterization. The [shared system model](../../docs/system-model.md) separates those contracts from realized implementations and evidence claims.

The model modules own process-free implementation contracts. `hls_host_codec` retains source-checked record catalogs, and `hls_protocol_application_schema` describes logical ownership, geometry and endpoint bindings. Communication planning derives requirements, target materialization binds emitted interfaces, and runtime owns concrete wire encoding and live use.

Actor execution, domains, brokers and live observation sessions remain in [`hls_runtime`](../hls_runtime/README.md). Compiler `hls_topology` acquires source-bound summaries and projects them into the core model; communication plans and physical target products remain in their owning applications.
