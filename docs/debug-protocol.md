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

## Version 1 operations

`DEBUG_GET_COUNTERS` (`0xd0`) has no payload. Its reply is `DEBUG_COUNTERS`
(`0xd1`) with eight words captured from one coherent monitor snapshot:

1. Protocol version.
2. Cycles since reset.
3. Accepted application input beats.
4. Accepted application input frames.
5. Application input stall cycles.
6. Accepted application output beats.
7. Accepted application output frames.
8. Application output stall cycles.

An input stall is a cycle with `TVALID && !TREADY` on the request path. An
output stall is a cycle with `TVALID && !TREADY` on the reply path. Counters are
32-bit wrapping counters in this prototype.

Malformed or unsupported requests receive `DEBUG_ERROR` (`0xdf`) with a
one-word error code. Error code 1 means an unsupported or malformed request.

## Availability rule

The monitor only observes application signals. None of its outputs feed the
application ready/valid path. A blocked debug consumer may block later debug
queries, but cannot block application traffic; a blocked application output
cannot prevent counter queries from completing.

Future state snapshots and trace buffers must preserve this rule. In
particular, trace overflow drops trace events and increments a drop counter
rather than applying backpressure to the application.
