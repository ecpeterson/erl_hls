# HLS runtime library

`hls_runtime` contains the [actor and domain API](src/api/README.md) and its [host runtime](src/runtime/README.md). It owns CPU callback execution, domain lifecycle, device brokers and observation sessions. Shared values, codecs, diagnostics and logical actor keys live in [`hls_core`](../hls_core/README.md).

The runtime depends on `hls_core` and OTP `kernel`, `stdlib` and `crypto`; it has no dependency on the `erl_hls` compiler application. The [`erl_hls` application](../erl_hls/src/README.md) owns source preparation, parse transforms, hardware lowering and external-tool assets. A deployed application using compiled actors and retained bindings needs its own code, `hls_core`, `hls_runtime` and any selected transport application, but no compiler.

Both core and runtime are library applications: neither supplies an application callback or supervisor. CPU actors and device brokers have explicit start/stop APIs and remain caller-owned. The companion Fabric application's supervision policy is separate from these mechanisms.

The `hls_fabric` module here is the low-level routed-frame broker, not the downstream `hls_fabric` application's build frontend or lifecycle supervisor. Keeping the broker, its request bookkeeping and `hls_gs` proxy together lets compiler clients and deployed fabric applications share the same runtime without a reverse package dependency.

Host paths do not invoke type lowering callbacks, inspect source freshness or render DSLX. Core `hls_service_schema` reads embedded contracts, `hls_debug_catalog` binds retained observation metadata, and core `hls_actor_identity` supplies the shared logical identity encoding. Source-bound validation stays with the compiler or downstream lowering application. Custom provider extension and encoding contracts are described in [type providers](../../docs/type-providers.md).
