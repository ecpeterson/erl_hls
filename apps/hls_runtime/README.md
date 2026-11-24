# HLS execution runtime

`hls_runtime` owns live actor execution and transport state. It contains the actor/domain API, CPU callback execution, device brokers, virtual Erlang nodes, observation sessions, retained wire codecs and protocol queues. Shared values, logical identities and serialization contracts live in [`hls_core`](../hls_core/README.md).

The application callback `hls_fabric_app` starts `hls_fabric_sup`, under which callers explicitly attach virtual device nodes. The retained module names describe the public Fabric runtime API; application ownership is `hls_runtime`. Starting the application does not compile actors, choose placement, open a physical descriptor or reset hardware. Deployment code supplies brokers and node descriptions to the explicit runtime APIs.

| Directory | Owns |
| --- | --- |
| [`src/api`](src/api/README.md) | Actor behaviours, domain control and stable caller APIs |
| [`src/runtime`](src/runtime/README.md) | CPU execution, broker/session state, debugging and observation |
| [`src/fabric`](src/fabric/README.md) | OTP lifecycle, virtual nodes, live protocol routing and wire codecs |
| [`include`](include/README.md) | Runtime-facing records shared with callers and generated bindings |

The runtime depends only on `hls_core` and OTP. It has no dependency on the `erl_hls` facade, `hls_compile`, `hls_fabric`, `hls_target`, `hls_spacetime` or the optional observer adapter. A deployed application consumes retained schemas and bindings from its build, then loads only its own code and the runtime closure it actually uses.

Host paths do not inspect source freshness, render DSLX or invoke optimizer callbacks. `hls_service_schema` reads embedded contracts, `hls_debug_catalog` binds retained observation metadata, and `hls_actor_identity` supplies shared logical identity encoding. Source validation stays with computation synthesis; communication planning stays with `hls_fabric`; target source and physical tools stay with `hls_target`.
