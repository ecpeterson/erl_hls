# Debug management protocol

The debug endpoint is a second, transport-neutral AXI4-Stream path. It uses the
same four-byte frame header layout as the application path:

```text
byte 0: payload word count
byte 1: transaction identifier
byte 2: flags
byte 3: operation tag
```

The header is the first 32-bit beat. `TLAST` is asserted on the header for an
empty payload and on the final payload beat otherwise. Every beat currently has
`TKEEP = 4'hf`.

## Version 4 operations

Request tags sent from the host occupy `0x01` through `0x7f`. Reply tags sent
from the FPGA occupy `0x81` through `0xff`, allowing adapters and future
routers to reject a tag used in the wrong direction.

`DEBUG_GET_COUNTERS` (`0x01`) has no payload. Its reply is `DEBUG_COUNTERS`
(`0x81`) with eight words captured from one coherent monitor snapshot:

1. Protocol version.
2. Cycles since reset.
3. Accepted application input beats.
4. Accepted application input frames.
5. Application input stall cycles.
6. Accepted application output beats.
7. Accepted application output frames.
8. Application output stall cycles.

Request tag `0x02` and reply tag `0x82` are reserved and unassigned. An earlier
prototype used them for passive full-state snapshots, but version 4 does not
mirror packed application state into the debug monitor. A raw `0x02` request is
therefore unsupported and receives `DEBUG_ERROR`, like any other unsupported
request. A future state-inspection design must use a versioned, narrow,
on-demand mechanism with explicitly defined coherent-snapshot semantics.

`DEBUG_GET_TRACE` (`0x03`) has no payload. It atomically snapshots and drains
the bounded trace buffer, replying with `DEBUG_TRACE` (`0x83`). Its payload is:

1. Trace schema version (`1`).
2. Words per event record (`2`).
3. Number of retained event records.
4. Event records dropped because the buffer was full.
5. Observation cycles dropped at the passive tap.
6. The retained event records, oldest first.

Each version 1 event contains a 32-bit observation-cycle timestamp followed by
one metadata word: event kind, flags, transaction identifier, and application
operation tag from most- to least-significant byte. Kinds 1 and 2 denote an
accepted application input or output frame header. Flag bit 0 records whether
that header also ended the frame.

The prototype retains 64 events and drops newer events once full. Reading the
trace atomically freezes that bank, switches collection to a second bank, and
resets the new bank's event-drop count. The passive tap's observation-drop
count is cumulative. This record is deliberately a small instrumentation
envelope, not an encoding of ERTS trace messages. A later schema can add trace
tokens and distribution context while preserving the independent endpoint and
drain operation.

Complete event pairs are stored in an external 1R1W memory as 128-bit rows. A
possible odd final event travels in the snapshot descriptor. This lets one
observer cycle retain both an input and output frame header without requiring
two writes to the same memory, while FPGA synthesis can implement the bulk
storage as block RAM. The RAM itself is not reset; the retained count prevents
unwritten rows from being read.

An input stall is a cycle with `TVALID && !TREADY` on the request path. An
output stall is a cycle with `TVALID && !TREADY` on the reply path. Counters are
32-bit wrapping counters in this prototype.

Malformed or unsupported requests receive `DEBUG_ERROR` (`0xff`) with a
one-word error code. Error code 1 means an unsupported or malformed request.

## Availability rule

The hardware observer only receives application stream signals through a
passive tap. Packed application state and state-commit signals do not cross this
boundary, and none of the observer's outputs feed the application ready/valid
path. A blocked debug consumer may block later debug queries, but cannot block
application traffic; a blocked application output cannot prevent counter or
trace queries from completing. Missed observation cycles increment the
cumulative count reported by `DEBUG_TRACE`; the cycle counter and later trace
timestamps advance across those gaps. Stream counters and trace events are
complete only when that observation-drop count is zero. Trace overflow drops
events and increments its own counter rather than applying backpressure to the
application.

Only one debug reply is serialized at a time. Consequently, the next trace
request cannot reclaim a frozen bank until the prior trace reply has completed;
application observations continue into the other bank meanwhile.

## Erlang simulation client

The Icarus VPI bridge exposes the application and debug streams as independent
named FIFO pairs: `app_tx`/`app_rx` and `debug_tx`/`debug_rx`. The
`hls_debug` gen_server owns the debug pair, correlates replies by transaction
identifier, and decodes `DEBUG_COUNTERS` into a map with named counter fields.
Its public query API consists of `get_counters/1,2` and `get_trace/1,2`; the
two-argument forms let a caller select the `gen_server:call` timeout for slow
simulation transports. `get_trace/1,2` decodes `DEBUG_TRACE` into a map that
preserves the raw payload and numeric event-kind code alongside named event
fields. Generated private-
state packers and unpackers remain available as type-serialization support;
they are not exercised by the live service recurrence or exposed through the
version 4 debug protocol.

The generated-RTL regression starts this client alongside `hls_gs`, runs the
same application scenario as the CPU reference test, and queries the resulting
counter and trace snapshots from Erlang. The deterministic SystemVerilog test
separately checks the stronger availability case in which application output
is held under backpressure while both supported debug queries complete. It
also verifies that the reserved `0x02` request returns error code 1, along with
exact two-event ordering and trace-bank overlap. The bridged EUnit scenario
checks odd trace counts, a full 64-event bank, overflow accounting, and
drain-on-read behavior.
