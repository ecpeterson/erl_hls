# HLS execution runtime

`hls_runtime` owns live actor execution and transport state. It contains the actor/domain API, CPU callback execution, device brokers, virtual Erlang nodes, observation sessions, retained wire codecs and protocol queues. Shared values, logical identities and serialization contracts live in [`hls_core`](../hls_core/README.md).

The application callback `hls_fabric_app` starts `hls_fabric_sup`, under which callers explicitly attach virtual device nodes. The retained module names describe the public Fabric runtime API; application ownership is `hls_runtime`. Starting the application does not compile actors, choose placement, open a physical descriptor or reset hardware. Deployment code supplies brokers and node descriptions to the explicit runtime APIs.

| Directory | Owns |
| --- | --- |
| [`src/api`](src/api/README.md) | Actor behaviours, domain control and stable caller APIs |
| [`src/runtime`](src/runtime/README.md) | CPU execution, broker/session state, debugging and observation |
| [`src/fabric`](src/fabric/README.md) | OTP lifecycle, virtual nodes, live protocol routing and wire codecs |
| [`include`](include/README.md) | Runtime-facing records shared with callers and generated bindings |

The runtime depends only on `hls_core` and OTP. It has no dependency on the `erl_hls` facade, `hls_compile`, `hls_fabric`, `hls_target`, `hls_spacetime` or the optional observer adapter. Source-protocol partition, relay and mixed stream deployments load a canonical `hls_deployment_artifact` containing only their retained execution schemas and bindings; the other runtime APIs continue to consume their own retained values. Build plans, generated-source metadata and tool identities remain in their existing manifests. Brokers, PIDs, sessions, reset ownership and admission are fresh runtime inputs, never serialized deployment fields. Both artifact decoders accept trusted build output only because full codec validation may load and invoke installed provider modules. `decode/1` uses existing-atom ETF and never interns atoms; `load/1` additionally uses a bounded reader and may intern retained atoms. Never pass either API uploaded or network-provided bytes, or pass `load/1` a user-selected untrusted path. An artifact identity detects byte changes; it is not authentication.

Host paths do not inspect source freshness, render DSLX or invoke optimizer callbacks. `hls_service_schema` reads embedded contracts, `hls_debug_catalog` binds retained observation metadata, and `hls_actor_identity` supplies shared logical identity encoding. Source validation stays with computation synthesis; communication planning stays with `hls_fabric`; target source and physical tools stay with `hls_target`.
