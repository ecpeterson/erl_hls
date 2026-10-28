# HLS runtime library

`hls_runtime` contains the [actor and type API](src/api/README.md) and its [host runtime](src/runtime/README.md). It owns retained codecs, CPU callback execution, device brokers and observation sessions. It depends only on OTP `kernel`, `stdlib` and `crypto`; it has no dependency on the `erl_hls` compiler application.

The root [`erl_hls` application](../../src/README.md) owns source preparation, parse transforms, hardware lowering and external-tool assets. It depends on this library. Both applications build together in this repository; Git consumers select root `erl_hls` and `apps/hls_runtime` explicitly at the same revision when they need compilation. A deployed application using compiled actors and retained bindings needs only the runtime library and its own code.

Both packages are library applications: neither supplies an application callback or supervisor. CPU actors and device brokers have explicit start/stop APIs and remain caller-owned. The companion fabric application's supervision policy is separate from these shared mechanisms.

The `hls_fabric` module here is the low-level routed-frame broker, not the downstream `hls_fabric` application's build frontend or lifecycle supervisor. Keeping the broker, its request bookkeeping and `hls_gs` proxy together lets compiler clients and deployed fabric applications share the same runtime without a reverse package dependency.

Host paths do not invoke type lowering callbacks, inspect source freshness or render DSLX. `hls_service_schema` reads embedded contracts, `hls_debug_catalog` binds retained observation metadata, and `hls_actor_identity` supplies the shared logical identity encoding. Source-bound validation stays with the compiler or downstream lowering application. Custom provider extension and encoding contracts are described in [type providers](../../docs/type-providers.md).
