# hls_compile: computation synthesis

`hls_compile` owns Erlang source acquisition, process analysis, XLS computation lowering and compiler summaries. It is a process-free library: it does not choose placement, construct communication fabrics, run target tools or consume system-optimization results.

Actor descriptors can name the runtime-owned `hls_gs:from()` provider. Compilation loads its pure descriptor, width, empty-value and codec callbacks, so the `hls_runtime` BEAM library remains in the compiler code closure; it does not need the runtime application or its supervisor to be started. Use the compiler API or `hlsc` as a library entry point. `application:ensure_all_started(hls_compile)` instead follows the declared OTP dependency and starts `hls_runtime`, so it is not the standalone compiler launch contract.

[`src/frontend`](src/frontend/README.md) owns source context, parse transforms and actor interfaces. [`src/topology`](src/topology/README.md) projects those interfaces into the core logical system, while [`src/backend`](src/backend/README.md) lowers reachable computation to DSLX and compiler artifacts. `priv/xls/lib/` contains the installed computation library; `hls_compile_support` locates it without importing target policy.

The [`erl_hls` facade](../erl_hls/src/README.md) owns CLI and bundle orchestration. [`hls_core`](../hls_core/README.md) owns shared logical contracts, [`hls_fabric`](../hls_fabric/README.md) owns communication synthesis, and target publication and external-tool execution belong to [`hls_target`](../hls_target/README.md). These later applications may consume compiler products; `hls_compile` has no reverse dependency on them or on `hls_spacetime`.
