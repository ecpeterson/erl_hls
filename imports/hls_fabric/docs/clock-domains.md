# Independent device clocks

Each XLS device runs on its own clock. `apps/hls_lowering/priv/rtl/hls_async_fifo.v` supplies the ready/valid boundary between domains; the DSLX credit protocol and actor graph do not change. The phi simulation has three clocks: one for the host debug transport and one for each device. Two FIFOs carry the full-duplex application link, and four more carry independent debug requests and responses. All storage is bounded.

In a board implementation each FIFO lives wholly inside one FPGA, between the application clock and a local transport or recovered clock. The simulated direct connection collapses the intervening transport into an ordered beat stream; a physical adapter must supply that stream and its clocks.

## Beat ownership

`hls_async_fifo` transfers complete `WIDTH`-bit words. A write owns a slot when `in_valid && in_ready` holds at a rising `wr_clk` edge. A read releases it when `out_valid && out_ready` holds at a rising `rd_clk` edge. The data stays stable while a valid output is stalled. Link words are 33 bits, including TLAST; debug words are 37 bits, including TKEEP and TLAST. Packet boundaries travel with their data, including when the FIFO stalls partway through a packet.

Capacity is exactly `2**ADDR_BITS` words, with `2 <= ADDR_BITS <= 16`. The simulation uses eight words in every crossing. Storage has a synchronous write port and asynchronous read port, with `ram_style="distributed"`; this implementation targets small LUT memories, not BRAM. It accepts or delivers one beat per local clock when space or data is available. Empty/full changes arrive conservatively: two pointer synchronizer stages plus a registered local flag add delay before newly written words or freed slots become visible. This costs latency and can limit throughput with shallow queues or large clock ratios.

Binary pointers address storage; registered Gray pointers cross through two synchronization stages. Only the synchronized remote pointer affects local full/empty decisions. Neither ready nor valid is passed combinationally between domains. Memory is not reset, but reset empties both pointers, so stale contents are unreachable until replaced by new writes.

These FIFOs do not create additional lane credits. The credit bridge still reserves one complete frame per receive lane. The clock crossing is additional unadvertised beat storage, and preserves the bridge's required ordered, exactly-once word stream.

## Reset and stopped clocks

One common active-high `reset` must reach both FIFO sides, both credit endpoints, both actor graphs and all other intervening transport storage. Assertion is asynchronous. `hls_clock_reset` holds each local reset until two rising edges of that clock have occurred after common reset is released. A stopped domain therefore remains in reset until its clock returns. The same reset helper drives the generated devices' synchronous reset inputs.

A stopped clock without reset retains outstanding work. The FIFO fills or empties, then backpressures the still-running side; it resumes from the same pointers when the clock returns. The running device's debug port remains usable, because its own host crossing and clock are independent. The stopped device cannot answer a debug request until it is clocked again.

Common reset discards all outstanding work and restarts the application. The host must retire outstanding debug transactions and re-establish its debug transport around this reset: clearing hardware storage alone does not retire a partial frame already buffered by the host. The phi regression performs its traffic reset before attaching the host, then exercises clock stopping with both debug sessions live. It is not a way to reconnect a single board while its peer continues running. A physical link with independent restart needs activation agreement and an outcome for interrupted actor work, as described in the [bridge contract](device-bridge.md).

## Physical implementation requirements

RTL simulation and formal verification cover digital behavior, not metastability, routing skew, reset pulse widths or clock quality. `ASYNC_REG` and `SHREG_EXTRACT="NO"` mark both pointer synchronizers and reset-release chains. An implementation must preserve those chains, constrain the actual crossing paths and inspect the implemented CDC/timing reports before using this on a board.

For each FIFO instance, the Gray-pointer crossings are `wr_gray` → `wr_gray_r1` and `rd_gray` → `rd_gray_w1`. Constrain each bus from the source register Q pins to the first synchronization stage D pins. Use a source-clock-period maximum datapath delay and a bus-skew bound no larger than the smaller clock period; retain normal destination-clock timing between synchronization stages. The memory data path must also settle before the destination can consume a newly visible word. Review that path, the local asynchronous read path and reset recovery/removal in the target implementation. Observe the device's minimum asynchronous reset pulse width even when a clock is stopped.

AMD's [Gray-bus constraint example](https://docs.amd.com/r/en-US/ug903-vivado-using-constraints/set_bus_skew-Example-Two) explains the pointer delay/skew constraints. A blanket asynchronous clock group or false path can override maximum-delay constraints; [UG949 describes that precedence](https://docs.amd.com/r/2023.2-English/ug949-vivado-design-methodology/Defining-Clock-Groups-and-CDC-Constraints). Board-specific constraints and placement review remain pending; this repository does not provide a validated physical CDC implementation or a PHY.

## Validation and cost

Digital simulation/formal checks cover ordering, bounds, stalls and reset; they do not establish physical CDC safety. See [qualification procedures](../yap/clock-validation.md) and the [isolated crossing report](artifacts.md#historical-reports) (`experiments/results/clock-crossing-measurements.json`). The measured six-FIFO bundle uses 256 XC7 LUTs and 198 flip-flops, excluding actors, credit endpoints and physical transport.
