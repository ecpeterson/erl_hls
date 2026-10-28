# Two-counter build walkthrough

`hls_counter_example.erl` contains `hls_statem` callbacks plus one logical topology: two addressed counters, a rectangular increment ingress and one output per counter. Initial entry publishes zero; each consumed increment republishes the updated total.

From the repository root, `source.config` selects a source-protocol application boundary. `scheduler.config` selects dedicated channel-scheduler actors. `scheduler-ram.config` shares one executor and exposes scheduler-owned RAM ports for an enclosing shell. The `source.config` and `scheduler.config` comments show the matching `hls-fabric emit` arguments; the RAM configuration uses the same channel-scheduler command. Paths are relative to the invoking directory.

All three configurations use the same application callbacks and topology. Placement and schedules are configuration choices; external XLS compilation, RTL execution and physical deployment are separate steps. Use this example for small build/API changes before changing the larger phi workloads.
