# Shared scheduler ownership

A scheduler multiplexes actors over one executor and one state/mailbox RAM pair. An actor has at most one activation in flight. Other actors may advance while its activation waits for memory, execution or publication. Dedicated actors use a separate execution backend.

The XLS code generator must reserve fixed-latency RAM response capacity and gate physical operations on accepted requests. Use the repository's [pinned RAM-safe toolchain](../../../tools/hls_fabric/xls_ram_codegen/README.md); stock releases without that fix can lose reads under pipeline stalls.

| Owner | Holds | Releases when |
|---|---|---|
| Metadata service | Producer receptacles, mailbox order, readiness and actor reservations | An admission or dispatch is accepted |
| Loader | Actor identity, work kind and selected mailbox indices | Both RAM responses form one complete request |
| Request register | Loaded machine and selected input | The executor accepts them |
| Executor | Callback computation | Its result reaches reserved completion storage |
| Metadata service | Registered completion and effect batch | Retirement transfers the state write and any effects |

These are ownership boundaries; they do not each promise one clock of latency. The executor remains XLS-pipelined. Request and completion values cross registers even when their buffers are empty.

## Selection and concurrent changes

Dispatch and mailbox admission select from committed metadata. Current captures, credit returns and retirements become eligible at a later decision edge. Round-robin cursors advance on accepted selections. An added visibility edge can change global interleaving; per-actor mailbox order and callback semantics remain intact.

Admission may append while the same actor executes: its already-free physical slot cannot overlap the retained live message. Concurrent retirement and admission merge their changes to the current row. Admission cannot reuse a slot freed by that same retirement. Failure cancels a conflicting admission without consuming its producer.

A dispatch fixes its work kind and transfers any selected aggregate into its ticket. A simultaneous replacement remains pending, including a protocol-failure value from an invalid duplicate. Actor ownership remains reserved through execution and retirement; the existing write-acknowledgement fence prevents a later load from observing stale state or mailbox data.

## Bounded storage and stalls

Each actor reservation owns completion capacity. A scheduler with `N` actors has one retained completion and `max(1, N−1)` result-FIFO entries, enough to park all outstanding results when publication stops. The loaded-request register adds one request-sized state value; mailbox and outbox capacities are unchanged.

Shared-outbox mode preserves ordered batch publication. Per-actor mode also excludes actors whose previous batch still occupies their outbox. In both modes, blocked channels retain ownership; whole-design reset discards outstanding tickets, requests and results together. This is not a partial-recovery protocol.

Pipeline latency and storage can outweigh a shorter clock period, especially with few actors available to overlap. Compare measured cycles per step × routed period for the intended placement; an initiation interval of one alone does not establish application throughput.
