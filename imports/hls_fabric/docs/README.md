# Documentation

Begin with [building the backend](building.md); keep retained measurements in the [external artifact archive](artifacts.md).

- [Actor execution](execution/README.md): shared placement, compiler boundary and observations.
- [Virtual nodes](device-sessions.md): messages, lifetimes, admission and recovery.
- [Actor PIDs](actor-pids.md): logical addressing and hardware inspection.
- [Return contexts](return-contexts.md): request/reply ownership at the device boundary.
- [Device bridge](device-bridge.md), then [clock domains](clock-domains.md): partitioning, link contract and physical CDC obligations.
- [Application streams](application-streams.md): checked attachment, ordered commands and credited events.
- [Distributed memory experiment](distributed-memory.md): correction application, global closeout and final measurements.
- [Shared RTL tiles](tiles.md): one compilation with board-specific constant wrappers.
- [Actor timing profiles](profiling.md): reusable event graphs, exact clocks and causal scope.
- [Source quality](source-quality.md) and [style](../STYLE.md): contributor requirements.

`yap/` holds implementation/qualification working material. `experiments/results/` holds measurements with their scope and reproduction commands.
