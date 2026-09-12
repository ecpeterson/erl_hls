# Debug management protocol

The debug endpoint is a second, transport-neutral AXI4-Stream path. It uses the same four-byte frame header layout as the application path:

```text
byte 0: payload word count
byte 1: transaction identifier
byte 2: flags
byte 3: operation tag
```

The header is the first 32-bit beat. `TLAST` is asserted on the header for an empty payload and on the final payload beat otherwise. Every beat has `TKEEP = 4'hf`, and request flags must be zero.

## Version 5 operations

Request tags sent from the host occupy `0x01` through `0x7f`. Reply tags sent from the FPGA occupy `0x81` through `0xff`, allowing adapters and future routers to reject a tag used in the wrong direction.

`DEBUG_GET_COUNTERS` (`0x01`) has no payload. Its reply is `DEBUG_COUNTERS` (`0x81`) with ten words captured from one coherent monitor snapshot:

1. Protocol version (`5`).
2. Cycles since reset.
3. Accepted application input beats.
4. Accepted application input frames.
5. Application input stall cycles.
6. Accepted application output beats.
7. Accepted application output frames.
8. Application output stall cycles.
9. Observation cycles dropped at the passive tap.
10. RX/TX framing status.

Request tag `0x02` and reply tag `0x82` are reserved and unassigned. A raw `0x02` request receives `DEBUG_ERROR`, like any other unsupported request.

`DEBUG_GET_TRACE` (`0x03`) has no payload. It atomically snapshots and drains the bounded trace buffer, replying with `DEBUG_TRACE` (`0x83`). Its payload is:

1. Trace schema version (`2`).
2. Words per event record (`3`).
3. Number of retained event records.
4. Event records dropped because the buffer was full.
5. Observation cycles dropped at the passive tap.
6. RX/TX framing status.
7. The retained event records, oldest first.

Each version 2 event contains three little-endian 32-bit words:

| Word | Contents |
| --- | --- |
| 0 | Observation-cycle timestamp, modulo `2^32`. |
| 1 | Source endpoint in bits 31–16 and destination endpoint in bits 15–0; zero for an endpoint-local stream. |
| 2 | Event kind, observation flags, transaction identifier, and application operation tag, from most- to least-significant byte. |

Kinds 1 and 2 denote an accepted application input or output **inner frame header**. Observation flag bit 0 records header `TLAST`, bit 1 records the presence of a route, and bit 2 records an observation gap before this direction's retained header. These are monitor flags, not the application's header flags. A retained header does not prove that the remaining frame was valid, delivered, or handled by an actor.

`hls_debug_monitor` defaults to `ROUTED=0` for endpoint-local streams whose first beat is the application header, such as regsvc after its router. `ROUTED=1` consumes an outer route word before recognizing the inner header, as on the phi-memory host gateway. This mode applies to both observed directions and must match the physical attachment. Routes identify physical endpoints, not necessarily individual actors inside a shared topology.

The framing status word packs RX phase in bits 1–0, TX phase in bits 3–2, RX pending-gap in bit 4, and TX pending-gap in bit 5. All higher bits are zero. Each phase is `0=boundary`, `1=header` (route already consumed), `2=payload`, or `3=unsynchronized`. Pending-gap means that no retained header from that direction has yet reported the most recent observation loss; it is independent of whether framing has recovered.

The prototype retains 64 events and drops newer events once full. Reading the trace atomically freezes that bank, switches collection to a second bank, and resets the new bank's event-drop count. The passive tap's observation-drop count is cumulative modulo `2^32`. A full reply has 198 payload words, or 800 bytes including the outer route and inner reply header. This record is deliberately a small instrumentation envelope, not an encoding of ERTS trace messages.

Complete event pairs are stored in an external 1R1W memory as 192-bit rows. A possible odd final event travels in the snapshot descriptor. This lets one observer cycle retain both an input and output frame header without requiring two writes to the same memory, while FPGA synthesis can implement the bulk storage as block RAM. The RAM itself is not reset; the retained count prevents unwritten rows from being read.

An input stall is a cycle with `TVALID && !TREADY` on the request path. An output stall is a cycle with `TVALID && !TREADY` on the reply path. Counters are 32-bit wrapping counters in this prototype. Frame counters count observed accepted `TLAST` beats, even while header framing is uncertain; they are not packet-validity checks.

Malformed or unsupported requests receive exactly one `DEBUG_ERROR` (`0xff`) reply with the original header's transaction identifier and a one-word error code of `1`. A valid request is a single header beat with zero payload count, zero flags, full `TKEEP`, `TLAST`, and a supported operation tag. If the first beat does not assert `TLAST`, the server drains the packet through an accepted `TLAST` before replying. It ignores the declared length and all payload contents while draining; command-like payload words cannot become requests. Rejected packets neither query the observer nor read trace RAM or drain a trace bank.

Without a terminating `TLAST`, the receiver remains in the drain state. Reset is the explicit abort boundary; no header-looking word can unambiguously identify a new packet inside an unterminated one. Reset also clears the observer's counters and retained trace count. The receiver can drain a rejected packet while its reply output is blocked, but it serializes that error before accepting the next request.

## Availability rule

The hardware observer only receives application stream signals through a passive tap. Packed application state and state-commit signals do not cross this boundary, and none of the observer's outputs feed the application ready/valid path. A blocked debug consumer may block later debug queries, but cannot block application traffic; a blocked application output cannot prevent counter or trace queries from completing. Missed observation cycles increment the cumulative count reported by both counter and trace replies; the cycle counter and later trace timestamps advance across those gaps modulo `2^32`. Stream counts omit missed cycles. Event loss can also result from trace overflow or deliberate suppression while framing is uncertain, so retained-event counts need not match frame counters. Trace overflow drops events and increments its own counter rather than applying backpressure to the application.

Any missed sample makes **both** directions unsynchronized: the tap cannot know which direction transferred during the gap. The observer suppresses header recognition until it observes an accepted `TVALID && TREADY && TLAST` in that direction. That beat restores the boundary but does not itself produce a header event. Idle cycles, a stalled `TLAST`, and header-looking payload cannot restore framing. The next retained header carries the pending-gap flag, even if intervening headers overflowed a full trace bank. Draining a bank does not clear framing or an unreported gap.

The tap carries a gap bit separately from its cumulative drop count. Even exactly `2^32` lost cycles, which leave the count numerically unchanged, invalidate framing. A zero count alone therefore does not prove a loss-free history. Timestamps are observations in one monitor clock domain, not global time: at 200 MHz they wrap in about 21.5 seconds. Modular differences do not reveal multiple wraps. The application and monitor must share reset or start at a known frame boundary; independently resetting a monitor mid-packet does not establish that boundary. Reset clears framing, counters, and retained events; it is an explicit session boundary, not an epoch inferred from a smaller timestamp. Restart clients and establish a clean transport after an interrupted transaction. An idle byte transport may remain open across a quiescent reset when no physical transfer is outstanding.

`hls_debug_capture` accepts the tap's 104-bit observation record and owns the observer, server, and trace RAM. The record packs `routed`, `gap`, the 32-bit cumulative drop count, TX observation, and RX observation from most to least significant field; each 35-bit stream observation packs data, `TLAST`, ready, and valid. An alternative provider must report every rejected sampling cycle and set `gap` on the next accepted sample. The production tap samples independently of application progress. A one-entry snapshot-request register decouples the separately scheduled XLS procs so request acceptance cannot wait on a snapshot which the server is not yet ready to receive.

Request reception and reply serialization occupy separate server iterations. Only one debug reply is serialized at a time. Consequently, the next trace request cannot reclaim a frozen bank until the prior trace reply has completed; application observations continue into the other bank meanwhile.

## Erlang simulation client

The Icarus VPI bridge exposes the application and debug streams as independent named FIFO pairs: `app_tx`/`app_rx` and `debug_tx`/`debug_rx`. An `hls_fabric` broker owns the debug pair. The `hls_debug` gen_server registers its return route, correlates replies by transaction identifier, and decodes `DEBUG_COUNTERS` into a map with named counter fields. Its boundary-monitor API consists of `get_counters/1,2` and `get_trace/1,2`; the two-argument forms let a caller select the `gen_server:call` timeout for slow simulation transports. `get_trace/1,2` decodes `DEBUG_TRACE` into a map that preserves the raw payload and numeric event-kind code alongside named event fields. Each event includes `route => none | {Source, Destination}` and `observation_gap => boolean()`. Both replies include `framing => #{rx => Phase, tx => Phase, rx_gap_pending => boolean(), tx_gap_pending => boolean()}` with phases `boundary`, `header`, `payload`, and `unsynchronized`. Generated private state packers and unpackers remain available as type-serialization support; they are not exercised by the live service recurrence or exposed through the version 5 debug protocol.

The generated-RTL regression starts this client alongside `hls_gs`, runs the same application scenario as the CPU reference test, and queries the resulting counter and trace snapshots from Erlang. The deterministic SystemVerilog test separately checks the stronger availability case in which application output is held under backpressure while both supported debug queries complete. It also verifies that the reserved `0x02` request returns error code 1, along with exact two-event ordering and trace-bank overlap. The bridged EUnit scenario checks odd trace counts, a full 64-event bank, overflow accounting, and drain-on-read behavior.

[Scoped debug targets](debug-targets.md) combine process-style current-state inspection with explicitly selected boundary counter/trace operations. Shared-topology actors expose placement and related boundaries; an actor-level counter or trace request is rejected instead of returning shared traffic under that actor's name. The phi-memory bridged regression exercises the scoped monitor interface around a generated shared-scheduler topology.

The raw `hls_debug:query/4` API sends a word-aligned management payload and returns the reply payload, correlating both the transaction identifier and reply tag. [Topology queries](topology-debug.md) use this API on their own routed endpoint.

## Checked simulation transport

The VPI bridge checks both directions of both physical streams before forwarding accepted words. At this boundary, packets have an outer route word, the inner frame header, and exactly the payload count declared in that header (0–255 words). `TLAST` must mark that declared end and cannot mark the route word. Every valid beat must have full `TKEEP` and known data, keep, last, and ready bits; `TVALID` must always be known outside reset. Data, keep, last, and asserted valid must remain stable across a stall, including the accepting edge. Data and sidebands may be unknown while valid is low.

A violation, missing or incorrectly sized signal, FIFO setup failure, or hard FIFO I/O error ends Icarus with a nonzero status and a diagnostic identifying the endpoint, direction, and cycle where applicable. A normal simulation finish also checks for incomplete physical transfers and pending buffered bytes. Initial reset permits queued startup input. A later reset that interrupts a transfer fails the byte-FIFO simulation and requires a fresh run and FIFOs; it cannot safely reframe bytes already delivered to the host. Reset recovery of the hardware receiver is tested directly at its beat interface. Open read/write FIFO descriptors do not detect peer disconnection, and a sender that simply stops mid-packet is subject to the caller's simulation timeout.

Run `python3 tools/test_sim_bridge.py` for fault injection against the real VPI module; it requires Icarus and its C toolchain, but not XLS. The generated-RTL regression also runs `hls_debug_server_tb.sv` against the separately lowered server, injecting bad counts, early/late/missing termination, partial keep, flags and unsupported tags, command-like payloads, more than 255 drain beats, output backpressure, and reset. It verifies one error per rejected packet, preservation of the original transaction ID and retained trace event, and recovery of subsequent counter and trace requests. The physical bridge deliberately fails on malformed framing, so these receiver recovery tests drive the hardware directly. Passing `+timing` to that testbench reports valid-request and reply acceptance cycles without output backpressure.

`ERL_HLS_SIM_DEBUG_ONLY=1` enables just the debug FIFO pair for applications such as the decoder profiler that have no host application stream. `ERL_HLS_SIM_APP_ONLY=1` enables just the application pair, and `ERL_HLS_SIM_PROFILE_ONLY=1` enables neither transport. These modes are mutually exclusive; without them both transports are checked. Disabled interfaces need not exist in the testbench.

## Diagnosing generated applications

Start with `hls_debug:info` to resolve actor placement and related physical boundaries. Use topology `inspect_waits` and queue/credit queries for current backpressure; use boundary counters and `get_trace` when accepted traffic or event ordering matters. Check observation drops, framing status, event overflow, and session/reset boundaries before interpreting absence of an event. Save decoded reports with the topology manifest and stimulus so the diagnosis can be reproduced. A boundary trace drain affects all clients of that monitor.

Prefer these interfaces when investigating generated RTL. The simulation bridge can transport the same debug packets as a device without reading generated private state. If the debug endpoint itself fails, inspect its public request/response and observation handshakes in a focused RTL test; keep any need for deeper state inspection explicit.

After `rebar3 eunit` and debug RTL generation, run `python3 tools/test_debug_trace_integration.py _build/xls_sim/regsvc`. It drives routed application traffic independently of observation readiness and injects lost routes, headers, and final payload beats at a sampling gate. The real `hls_debug` client checks simultaneous RX/TX records, uncertain framing, stalled versus accepted `TLAST`, per-direction recovery, overflow with a pending gap, and reset with a fresh client. Decoded `trace_*.term` reports and transport logs are saved under `_build/debug-trace-integration`. VPI sees only the public debug stream. DSLX tests separately check cycle/drop-counter wrap, including a gap with unchanged cumulative count. The phi-memory regression checks recorded routes and operation selectors against its generated boundary contract.
