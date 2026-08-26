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

## Version 2 operations

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

`DEBUG_GET_STATE` (`0x02`) also has no payload. Its `DEBUG_STATE` (`0x82`)
reply begins with a one-word state-schema version, followed by the packed
private state record. Version 1 state records use the same least-significant-
word-first representation as application payloads, so the generated Erlang
record unpacker decodes the reply without a second wire format. The payload
length in the reply header makes the state width explicit.

The generated XLS service emits its packed state on an always-ready internal
observation channel when a transaction commits. The debug monitor retains the
latest value and answers queries from that mirror. A transaction blocked before
commit is therefore absent from the snapshot; application backpressure cannot
block a query for the preceding committed value. The current compiler's init
state is zero, matching the debug mirror's reset value. A future nontrivial
initializer must also publish its initial packed state.

This is deliberately a last-committed-state view. If translated handlers later
gain blocking operations such as `receive` or `gen_server:call/3`, a suspended
handler's continuation and wait reason will need a separate execution-status
observation; they must not be presented as committed callback state.

An input stall is a cycle with `TVALID && !TREADY` on the request path. An
output stall is a cycle with `TVALID && !TREADY` on the reply path. Counters are
32-bit wrapping counters in this prototype.

Malformed or unsupported requests receive `DEBUG_ERROR` (`0xff`) with a
one-word error code. Error code 1 means an unsupported or malformed request.

## Availability rule

The monitor only observes application signals and the always-ready state
commit channel. None of its outputs feed the application ready/valid path. A
blocked debug consumer may block later debug queries, but cannot block
application traffic; a blocked application output cannot prevent counter or
state queries from completing.

Future trace buffers must preserve this rule. In particular, trace overflow
drops trace events and increments a drop counter rather than applying
backpressure to the application.

## Erlang simulation client

The Icarus VPI bridge exposes the application and debug streams as independent
named FIFO pairs: `app_tx`/`app_rx` and `debug_tx`/`debug_rx`. The
`xls_debug` gen_server owns the debug pair, correlates replies by transaction
identifier, and decodes `DEBUG_COUNTERS` into a map with named counter fields.
When started with the translated service module, it uses that module's
generated state unpacker to decode `DEBUG_STATE` into the original private
record tuple. State results retain the schema version and raw packed bytes in
addition to the decoded record. Without a service module, callers still receive
the version and raw bytes, with the decoded `state` field set to `undefined`.

The generated-RTL regression starts this client alongside `xls_gs`, runs the
same application scenario as the CPU reference test, and queries the resulting
counter and state snapshots from Erlang. The deterministic SystemVerilog test
separately checks the stronger availability case in which application output
is held under backpressure while both debug queries complete.
