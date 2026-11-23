# Partitioned actor graphs

The channel-scheduler partition backend places an actor graph on independently compiled RTL devices. Local messages stay on their device. Each cut source/recipient pair becomes a separately credited lane over a full-duplex word stream; no host process forwards these messages. Ordinary BEAM processes supply an independent semantic reference, and the public debug protocol inspects the generated hardware while the application link is blocked.

Placement has two storage choices. The direct reference gives each actor a `Service` with register-backed state and mailbox. `hls_partition_schedule:shared(Deployment, Groups)` assigns every actor to a device-local RAM executor; `Groups` maps group names to lists of deployment identities. Each group must contain one module and stay on one device. Both choices preserve logical identities, routes, startup order and application framing.

Use `hls_partition_schedule:shared_by_module(Deployment, MaxActors)` to group automatically. It balances each device/module bucket across the fewest executors allowed by the actor-count limit. Compatible families and singleton actors can share; family identity is not a physical isolation requirement. Grouping is deterministic under actor-list reordering. Module identity currently denotes one compiled implementation, so distinct compiled variants must not share that identity. A lower limit permits more parallel execution at the cost of duplicated logic and RAM banks; the limit alone does not predict throughput or area.

Shared placement reuses the public executor and physical 1R1W RAMs. Before a callback issues, its actor reserves storage for a complete effect batch. Each actor drains that batch through the same ordered router used by direct placement and returns its own local credit. A stalled actor cannot occupy the executor while awaiting its destination; other actors retain their output reservations. There is no global permission owner or inter-device grant exchange.

Credit returns have independent scheduler receptacles and do not pass through actor mailboxes. This prevents output pressure from coupling otherwise runnable actors through shared retirement. It does not prove the Erlang application deadlock-free: finite mailbox/output capacity, fair execution and the lane transport's progress assumptions still apply. State and mailbox storage remain shared; output-batch storage grows with actor count.

## Placement and ordering

`hls_partition:normalize(Plan, Placement, hls_frame_layout:new(N))` selects an ordinary payload capacity of N words while accepting the normalized public topology plan and a complete map from logical actor identities to at least two device IDs. The `/2` convenience uses the default three-word capacity. Identities use `{actor, Id}` or `{family, Family, Coordinates}`. Family expansion preserves global coordinates and startup values. Missing or additional placements are rejected, as are incompatible record selectors/layouts and ambiguous external encodings.

`hls_partition_dslx:emit(Deployment, Device, Options)` emits that device's actor graph. Its boundaries contain a pair of `axis::Frame` lane arrays per peer, local external outputs, and any local rectangle-control input. `hls_partition:device/2` derives a sorted `links` list with each peer, local port index and directed lanes. Each pair of arrays connects to its own credit bridge. Wire IDs are dense within each directed device pair: lane 0 on one link is independent of lane 0 on another. The fixture retains the complete deployment beside its compiler inputs so wire IDs can be resolved to logical sources and destinations.

The graph supports single-recipient routes, queued fanout and one rectangle-control ingress. `hls_partition_ingress:commands/5` selects devices by their owned actor points and returns `{Device, Packet}` pairs: each packet is a flattened `SpatialFrame` of `66 + frame_bits` bits for the generated input port (194 bits at the default three-word payload capacity). Global coordinates are retained; each local router delivers only to its own actors. Per-device command order must be preserved. Partial failure aborts the activation; multicast is not atomic and commands must not be replayed. The current generator requires application lanes in both directions on every peer link. All devices use the same selected ordinary frame layout, with matching numeric selectors at sender and receiver. The default layout has a 96-bit payload; the checked layout also determines mailbox and link-frame widths. Framed host gateways impose their own [envelope limits](application-streams.md#attach-and-use). This does not remap record tags, dynamically discover peers, or attach arbitrary scheduled-actor PID deployments to the link.

Several output ports from one actor to the same recipient share one lane. That includes aliased cardinal directions on a small torus. The source-ordered actor egress and lane FIFO preserve their order. Distinct source actors have independent lanes and no total ordering promise. A queued fanout accepts the actor event into its common egress, then waits for every branch; a stalled branch can hold later events from that source.

At a destination, fair bounded merges feed actor admission. Direct actors use a startup prefix and `axis::ReservedFrame`; shared actors use a dedicated scheduler producer slot, with startup preloaded into RAM before ordinary requests become eligible. Their final one- or two-way merge constructs the scheduled request directly; producer order is preserved, while cross-producer order is unspecified. Startup must fit each shared actor's mailbox. Returned effect credit has its own producer slot, so a full request slot cannot prevent an executor from resuming. Actor admission remains separate from link credits: a returned link credit means the message moved into bounded downstream storage, not that the actor consumed it or finished its callback.

## Credit bridge

Each peer has one independent physical word stream in each direction. There is no shared transmitter or credit pool across peers. A remote route requires a direct physical connection to its destination device; this backend does not forward through intermediate boards. In the default serial bridge, each logical receive lane owns an explicit one-frame FIFO and starts with one advertised credit under common reset. A transmitter selects a lane with credit before dequeuing its next frame, then spends that credit and sends the complete packet. The receiving lane returns credit after dequeuing into its bounded downstream path. An unavailable lane therefore cannot consume another lane's reserved receive capacity.

Data frames and returned credits receive fair service, including when some lanes are empty or blocked. Each continuously eligible lane receives a grant within a bounded service round; cross-lane order is unspecified. A data packet retains the physical transmitter until its lane prefix and all `1 + N` ordinary-frame words have been accepted, where `N` is the configured payload capacity (five beats including the lane prefix at the default capacity). Credit update and return paths have independent per-lane FIFOs and do not pass through an actor's mailbox. A shared elastic beat queue holds the selected word stable under wire backpressure. The current arbiter scans unserved eligible lanes and starts a new round when that class has no remaining candidate; an empty scan can still consume a turn.

The independent FIFOs matter even with registered XLS outputs. A blocked output register can stall the whole producing proc, including its other outputs. A register on the common receiver alone does not provide independent lane capacity. The explicit FIFO owns the advertised slot; additional pipeline/output registers are unadvertised storage. Code generation uses `--flop_outputs=true` and explicit channel depths.

An isolated endpoint with four lanes per direction maps to 1,470–1,497 XC7 LUTs and 1,966 flip-flops, with no BRAM. See [the synthesis report](artifacts.md#historical-reports) (`experiments/results/credit-link-measurements.md`) for the six-lane configuration, distributions and scope limits.

The link unit regression holds one destination blocked while the other three directional lanes finish all their messages. It checks complete frame order/content, stable stalled beats, and per-lane credit balances at the public wire. It then releases the blocked destination and checks recovery. Its progress obligation is to avoid adding waits between independently deliverable lanes; application deadlocks and insufficient declared mailbox capacity remain separate concerns.

## Packed transfers and receive windows

The default transport uses one 32-bit word per transfer and one advertised slot per lane. Before generating the deployment, call `hls_partition_links:configure(Deployment, #{words => W, credits => C})` to use packed transfers with `W = 1, 2, 4` and `C = 1..16` independently reserved slots per receive lane. Both endpoints must share these settings; they participate in the deployment identity. Actor frames, logical routes and per-lane ordering remain unchanged.

A packed transfer carries `W` consecutive protocol words. Subword `i` occupies bits `[34*i+:34]` as `{valid, TLAST, data[31:0]}`, least subword first. Valid subwords form a nonempty prefix. Packet boundaries may occur within a transfer, and unused trailing subwords consume no protocol words. These are internal ready/valid sidebands, not an Ethernet encoding. A physical adapter must retain their meaning across its own framing and clock domains.

The packed packetizer stages bounded input frames independently per lane and can select a new packet within the same clock. It restarts exhausted service rounds without an idle scan and serves either traffic class when the other is empty. A wider port consequently increases serialization capacity; it does not merely pad one protocol word to a larger bus. More credits cover longer return latency at the cost of receive storage. Neither setting removes finite downstream mailbox capacity or promises progress for an application-level deadlock.

Add `compact => true` to combine the lane and actor headers when the lane is below 32, the payload has at most seven words and fits the selected ordinary frame capacity, and flags, transaction ID and unused payload bits are zero. A compact header contains `{TAG xor 1:16, opcode:8, payload_words:3, lane:5}`, followed by exactly that many payload words. A zero-word frame ends at its header. Every other frame uses the full format below; metadata and every bit of the selected ordinary frame survive unchanged. Credit packets retain their full-format header. Both peers must enable compact framing, which also participates in deployment identity.

Transfer grouping is independent of packet boundaries and destinations. Several frames for the same lane may share a transfer; the receiver retains its unconsumed tail while delivering at most one frame per lane per activation. This staging uses already reserved credits and needs no additional credit from the sender to drain. Compact framing reduces bytes but does not guarantee a proportional reduction in application latency.

## Wire contract and reset

The serial boundary is `axis::Beat`: a 32-bit word plus TLAST, transferred with ready/valid. Packed transfers group full-format words or the compact packets described above. Words and TLAST must arrive in order, exactly once, without corruption. A physical adapter must provide that contract; the independent-clock harness supplies a bounded beat crossing, but there is no Ethernet, GT, CRC, acknowledgment/retransmission, or link-training implementation here. See [clock domains and the physical implementation requirements](clock-domains.md).

| Packet | Header word | Remaining beats |
| --- | --- | --- |
| Data | `TAG[31:16]`, zero bit 15, lane number `[14:0]` | `1 + N` words of `axis::bits_from_frame`, where `N` is the configured payload capacity; least significant first, with TLAST only on the final word (four words at the default capacity) |
| Returned credit | `TAG[31:16]`, one bit 15, lane number `[14:0]` | None; TLAST on the header |

The fixture uses tag `0x4850`. It is a format discriminator, not a unique deployment fingerprint or activation generation. Every device must use artifacts from the same checked deployment. The bridge supports up to 32,768 lanes in either direction; practical area limits are much smaller.

Each link’s endpoints **and all intervening transport storage** must be reset together. Common reset empties queues and restores the configured credit count per lane. Resetting only one FPGA, reconnecting to a peer with old queued traffic, or changing placement without draining/resetting the pair is unsupported. The unit test resets an occupied link mid-packet, changes its payload activation marker, and verifies that old frames do not reappear. An independently restartable physical link needs an activation handshake and a defined outcome for interrupted actor work before it can replace this reset contract.

For the running phi graph, recovery is a full application restart: all actor graphs and links reset, and outstanding work is discarded. Reinitializing bridge credits while keeping actors alive could strand an actor waiting for a discarded contribution and is unsupported.

Fault output codes are 1 for a wrong tag, 2 for an invalid lane, 3 for invalid packet length or termination, 4 for an excess returned credit, and 5 for an invalid packed-valid prefix. A receiver fault stops that receive half; an excess-credit fault stops the transmit half. The other half can still make progress. A report is emitted once per faulted half. The fixture fails on any report; a supervisor using this backend must retire/reset the connected application. This is a current recovery limitation, not a required policy for future independently recoverable links. These checks cannot detect every violation of the required transport contract, such as a dropped complete data packet or a duplicate that happens to consume an available credit.

## Phi simulation and debug

The [complete memory experiment](distributed-memory.md) also applies corrections and compares final measurements. The smaller replay fixture below isolates decoder/link behavior.

The fixture uses the real `phi_halo_cell` and deterministic `phi_syndrome_replay_cell` actors from `apps/hls_phi`. Global PRNG seeds, coordinates, toroidal routes and initial records are unchanged by placement. The graph splits its Y dimension evenly between devices. It is a decoder-only experiment: replay sources replace data/syndrome acquisition, and correction/status frames leave through external ports.

`shape` counts phi cells per selected plane, not physical qubits. A `[2,2]` grid with both X and Z planes gives four phi actors and four replay actors on each device, matching the intended two-board phi population. The larger single-plane cases exercise more neighbor relationships; none of these register-backed builds establish a Z-7030 capacity or timing result.

The harness uses independent device clocks, restarts the pair during a partially transmitted packet, and then holds the 0→1 physical link. A single BEAM opens the two independent public debug streams, verifies each manifest, queries channel/FIFO state and follows the wait graph to the blocked link output. It saves the observations before releasing the link, stops the peer clock and queries the running device to diagnose the resulting backpressure, then resumes the peer. The RTL transport introduces unequal periodic stalls in both directions while every actor's correction/status sequence through step 32 is compared with independent BEAM execution. Cross-actor output merge order is deliberately unconstrained.

VPI carries only the two public debug streams. The testbench connects the public link ports and records public event outputs; it does not inspect private actor state. Direct Services expose channel/FIFO diagnostics. Shared placement also exposes actor state and mailbox observations through the public actor catalog; these are passive snapshots, not execution histories.

Native validation covers the following populations, each through decoder step 32 with the held-link diagnosis and asymmetric stalls (clock-crossing validation is described [separately](clock-domains.md)):

| Phi shape | Planes | Phi + replay actors per device | Cut lanes per direction | Statuses | Corrections |
| --- | --- | ---: | ---: | ---: | ---: |
| `[2,2]` | X/Z | 4 + 4 | 4 | 264 | 0 |
| `[4,2]` | X | 4 + 4 | 4 | 264 | 30 |
| `[3,4]` | X | 6 + 6 | 6 | 396 | 82 |

The smallest torus deliberately exercises aliased neighbor ports and two external plane streams. The middle case adds nonzero corrections. The largest case gives every cell four distinct neighbors and exercises a non-power-of-two lane count. These are retained experiment cases; the current [CI suite](ci.md) uses one D2 memory integration rather than this decoder-only matrix. These are finite workload checks, including a final sequence comparison after recovery queries, rather than a proof over all seeds and executions.

## Reproduction

```sh
rebar3 eunit
python3 tools/test_credit_link.py "$XLS_ROOT" --stage _build/credit-link
python3 apps/hls_phi/tools/test_phi_bridge.py "$XLS_ROOT" --stage _build/phi-bridge --shape 2 2 --planes x z
```

`XLS_ROOT` supplies the converter, optimizer, code generator and matching standard library. The runner records source/tool hashes, both independent compilation command sequences, generated artifacts, debug manifests and observations, and BEAM/RTL event logs. Instrumentation is checked for structural noninterference, and each generated device passes a combinational-loop check. `--reuse-build` verifies the original inputs and outputs before reusing a completed build for another host-side run; use a fresh stage for changed hardware inputs. This optional command is separate from the current CI integration selection; use the pinned RAM-safe XLS build for shared placement.
