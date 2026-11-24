# Documentation

Start with the [telemetry project](../apps/erl_hls/src/examples/telemetry/README.md) for a complete communicating example, or the [standalone compiler](toolchain.md) for one actor. `hls_core` owns shared values and codecs, `hls_compile` owns source analysis, `erl_hls` owns the supported facade and orchestration, and `hls_runtime` owns CPU actors and device sessions. The [application map](../apps/README.md) describes that architectural spine and its supporting packages; the [workload map](../workloads/README.md) covers the maintained decoder applications; the [source map](../apps/erl_hls/src/README.md) locates implementation entry points.

The small examples under `apps/erl_hls/src/examples/` teach individual APIs and project structure. For larger end-to-end applications, use the maintained [Phi walkthrough](hls_fabric/execution/phi-walkthrough.md) or [Snowflake guide](../workloads/hls_snowflake/README.md). Phi and Snowflake remain separate OTP applications because they own application-specific actors, resources and witnesses; neither is a generic compiler stage.

Read the contract before its deployment details:

- **Architecture and actor programming:** [shared system model](system-model.md), [initialization](initialization.md), [control flow](control-flow.md), [entry actions](entry-outcomes.md), [local helpers](local-helpers.md), [reductions](actor-reductions.md), [indexed gathers](indexed-gathers.md) and [retained replies](retained-replies.md).
- **Values and compilation:** [standalone toolchain](toolchain.md), [actor compilation](actor-compilation.md), [numeric contracts](numeric-contract.md), [provider extensions](type-providers.md), [wrapping counters](serial-counters.md), [binary syntax](bit-syntax.md), [names](actor-names.md), [source context](source-context.md).
- **Composition and host transport:** [actor topologies](mixed-topologies.md), [service contracts](service-contracts.md), [actor domains and replacement](actor-domains.md), [host transactions](host-transactions.md), [application framing](application-framing.md) and [physical routing](fabric-routing.md).
- **Inspection:** [debug targets](debug-targets.md), [topology queries](topology-debug.md), then [query packets](topology-query-format.md) or [counter/trace packets](debug-protocol.md). [Timing profiles](profiling.md) render explicit captures; they do not collect actor events automatically. The [`hls_spacetime` application](../apps/hls_spacetime/README.md) handles cycle/version histories and physical associations. The compiler supplies a small [RAM observation witness](memory-observation.md).
- **Contributing:** [optimization review](optimization.md), [source quality checks](source-quality.md), [compiler regressions and CI](ci.md), [formal contracts](formal-contracts.md), [style](../STYLE.md), and [local build storage](build-storage.md).

Implementation and validation working material belongs in `yap/`; it is not an additional application contract.
