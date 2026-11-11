# Documentation

Begin with [building the backend](building.md). The [Phi source-to-runtime walkthrough](execution/phi-walkthrough.md) follows one concrete application through the compiler, placement, generated artifacts and live attachment. Keep retained measurements in the [external artifact archive](artifacts.md).

- [Actor execution](execution/README.md): shared placement, compiler boundary and observations.
- [Indexed collections](indexed-collections.md): typed member snapshots, storage ownership and placement assertions.
- [Virtual nodes](device-sessions.md): messages, lifetimes, admission and recovery.
- [Closed recovery domains](domain-recovery.md): source-network reset, lifecycle observations and independent management.
- [Actor PIDs](actor-pids.md): logical addressing and hardware inspection.
- [Return contexts](return-contexts.md): request/reply ownership at the device boundary.
- [Device bridge](device-bridge.md), then [clock domains](clock-domains.md): partitioning, link contract and physical CDC obligations.
- [Application streams](application-streams.md): checked attachment, ordered commands and credited events.
- [Distributed memory experiment](distributed-memory.md): correction application, global closeout and final measurements.
- [Shared RTL tiles](tiles.md): one compilation with board-specific constant wrappers.
- [Actor timing profiles](profiling.md): reusable event graphs, exact clocks and causal scope.
- [Retained locality baseline](locality-baseline.md): reproduce the accepted Snowflake comparison design.
- [Source quality](source-quality.md) and [style](../STYLE.md): contributor requirements.
- [Passive source-protocol capture](spacetime-capture.md): optional build-bound event observations, exact simulator replay and evidence limits.

`yap/` holds implementation/qualification working material. Retained measurements, scope and reproduction evidence live in the external artifact archive.
