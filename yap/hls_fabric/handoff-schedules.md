# Queue adapter schedules

`Notes/erl_xls/Roadmap.md` is the sole active task list. This note supports G2’s upstream-gated scheduling work and P6’s selected physical qualification; it does not schedule either.

Packed receive delivery forwards the existing credited FIFO head in the same clock. Credit is scheduled one cycle after that acceptance, so no frame register is needed in `Deliver`. Transmit forwarding uses a single combinational stage; the existing two-slot transfer FIFO retains a stalled word.

Incoming credit counts are registered before they affect the packetizer. Without this, bypassing `Wire` closes a combinational path through two directly connected endpoints. The zero-delay boundary test fails with unknown valid; the retained design passes that test and a composed Yosys SCC check. Registering credits moves latency onto credit replenishment rather than data forwarding. Small windows on long links can still limit throughput.

XLS currently validates IO constraints only against the top proc. `tools/transport_codegen.py` therefore extracts each unchanged, stateless adapter from optimized IR, compiles it as the top with an explicit schedule, verifies its complete module interface, and replaces only that module. Every other generated RTL byte stays unchanged. The manifest records the source IR, compiler command and products. Unsupported state, operations, interfaces or module populations fail closed. These are XLS implementations with separately chosen schedules, not handwritten replacements for generated logic.

Retiring separate adapter compilation requires XLS to support scheduling constraints on nested proc interfaces and a witness that those constraints actually apply. Physical timing belongs to the selected complete endpoint implementation; cycle simulation and combinational acyclicity do not establish a clock frequency.
