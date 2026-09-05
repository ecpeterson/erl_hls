# Generated phi/noise topology

This deliberately small fixture connects one phi cell, one phenomenological
syndrome cell, and one phenomenological data cell. Its sources are split by
responsibility:

- `phi_phenom_topology.erl` declares actors, exact routes, startup messages,
  and observable outputs as ordinary Erlang data.
- `phi_phenom_topology_dslx.erl` declares temporary physical choices for this
  executable fixture.
- `phi_phenom_topology.x` is generated and checked in as a golden artifact.

Actors exchange complete `axis::Frame` values through depth-one network
queues. Startup prefixes configure the two noise actors before their first
routed input. Each actor drains its entry actions through one source-ordered
egress stream. A generated router then places each message in the queue for
its logical source/recipient lane. The syndrome announcement uses queued
fanout: the actor send completes at the common egress queue, after which its
router waits for both the phi and observation branch queues. Each actor
ingress ends at one mailbox-admission gate.

Startup quiescence is checked from each configured actor's statically known
initial phase and source-ordered entry-effect summary. Topology generation does
not execute actor callbacks.

The one-instance periodic topology makes four output ports of each actor
converge on one destination. All four ports now enter the same lane queue, so
their source order is preserved before that lane competes with other senders
at the destination ingress. The physical profile no longer needs an
alias-order exception. The current implementation conservatively serializes
all entry actions from an actor, including actions for different recipients.
The common egress is explicitly sized for that artifact's largest phase-entry
effect list. Its registered producer slot and FIFO therefore retain the phi
actors' five-action flipping sequences without depending on incidental
mux-tree buffering before they can complete.

Logical actor IDs may be tuple-indexed values such as `{phi, X, Y}`; generated
channel names use canonical numeric instance indexes. In this exact backend,
external IDs also become DSLX port names and must therefore be DSLX
identifiers.

The generated-RTL regression runs consecutive decoder steps, stalls the
observation port, checks that a complete frame remains stable, then verifies
that the graph continues. Compiler-emitted actor summaries now check routed
schema membership and actor-to-actor layouts. Direct actor edges still require
equal local selectors because this backend does not yet generate tag remappers;
producers sharing an external output must agree on its selector and layout.
An additional generated-RTL fixture routes three distinguishable actions
written in the order 3, 1, 2 through one aliased external lane and verifies
that order while the lane is backpressured.

The closed-graph generator consumes an exact heterogeneous graph, so its proc
and channel instances are explicit. The compact torus plan below uses a
separate family backend that retains regular structure instead of flattening a
large grid globally.

### Topology input-flop area check

A one-flag out-of-context XC7 synthesis comparison of the exact one-cell
phi/noise fixture keeps producer output flops in both variants:

| consumer input flops | estimated logic cells | flip-flops | LUT1–LUT6 | `DSP48E1` |
| --- | ---: | ---: | ---: | ---: |
| enabled | 8,860 | 9,417 | 9,834 | 4 |
| disabled | 8,273 | 7,887 | 9,390 | 4 |

Both variants come from the same optimized IR and use the pinned XLS build and
the experiment-local openXC7 Yosys. This is an area-only synthesis result; it
does not establish placement, routing, or timing closure.

## Compact torus witness

`phi_torus_topology.erl` is the first rule-preserving family plan. It declares
one bounded rectangular `phi_halo_cell` family and seven route relations: four
wrapped cardinal translations, one external syndrome-request stream, and the
correction and status outputs which share one external decoder-event stream. A
5-by-5 plan and a 50-by-50 plan therefore contain the same one family and seven
rules; only the shape, derived instance count, and explicit per-coordinate
startup constants differ. The v0
startup representation enumerates one deterministic, nonzero phi coin seed per
member; it is not yet a compact instance-constant formula.

The generated proc hierarchy is:

```mermaid
flowchart LR
    Top["Top"] --> Torus["FamilyTorus&lt;W, H&gt;"]

    subgraph FamilyTorus
        Spawn["nested unroll_for!&lt;x,y&gt;"] --> Node["FamilyNode × W·H"]
        Arrays["depth-zero lane arrays / router-output slots"]
        ExternalLanes["syndrome-request and decoder-event lane arrays"] --> GridMux["FrameGridMux × 2"]
        GridMux --> Outputs["syndrome_requests_out / decoder_events_out"]
    end

    Torus --> Spawn

    subgraph OneFamilyNode["each FamilyNode"]
        NeighborInputs["neighbor lane inputs"] --> Ingress["FamilyIngress"]
        Startup["optional coordinate startup"] --> Ingress
        Credits["mailbox admission credits"] --> Ingress
        Ingress --> ActorQueue["actor request queue"]
        ActorQueue --> Service["phi_halo_cell::Service"]
        Service -- "ordered Egress" --> Router["FamilyRouter"]
    end

    Node -. "instantiates" .-> OneFamilyNode
    Arrays --> NeighborInputs
    Router -- "north / east / west / south" --> Arrays
    Router -- "syndrome / correction / status" --> ExternalLanes
```

`FamilyTorus`, `FamilyNode`, and `FamilyIngress` each appear once in generated
source. XLS elaboration instantiates one node, service, router, integrated
ingress, and actor request queue per coordinate. The ingress retains one
mailbox credit while fairly polling its statically known input lanes, then
transfers one complete frame and consumes the credit. For configured families,
the same ingress sends the coordinate startup frame under the first credit
before polling routed traffic. This replaces the earlier buffered `FrameMux2`
tree, `StartupPrefix`, and separate `ReservedFrame` process without changing
the actor mailbox boundary or adding another input queue. `FrameGridMux`
appears only at the scalar observation boundaries; it is not on the cardinal
mesh paths.

The topology normalizer validates every family output and route interface once
per rule. `hls_topology:routes_for_instance/3` resolves selected coordinates for
boundary tests without constructing a global actor or route list. On a 2-by-2
torus it also exposes the genuine north/south and east/west lane aliases; the
family backend maps each aliased pair to one channel array, reusing the ordered
actor egress rather than merging the ports again at the receiver.

The generated DSLX contains one reusable family node and nested `unroll_for!`
spawns over two-dimensional channel arrays. With instance startup omitted, a
5-by-5 and a 50-by-50 torus have the same generated routing structure; the
operational fixture additionally emits one startup match arm per coordinate.
XLS still elaborates the required actor and queue resources for every
coordinate. Runtime channel-array indexing is not supported by the pinned XLS
build, so each scalar external boundary uses statically indexed unrolled
receives gated by a round-robin cursor. These polling merges are bounded and
fair but not work-conserving: each family member gets one turn per
`Width * Height` completed activations. The default rectangular 2-by-3 fixture
is compiled to RTL and verifies all six post-configuration initial requests,
stable backpressure, and no duplication. Its decoder-event stream stays idle
because this structural witness has no syndrome source to advance the actors.

The lane arrays explicitly declare depth zero. This supplies the pinned block
stitcher's per-channel FIFO metadata without installing a global default which
could mask another unannotated channel. The adapter is zero-capacity and
bypassing; synthesis removes its 128-bit storage and most of its controller
state. Codegen disables implicit consumer input flops and retains one registered
producer output for every router lane. That output stage is the lane's one
bounded holding slot and timing boundary. Placing the pinned materialized
depth-one FIFO used here after it would double-buffer the route and allocate two
additional 128-bit storage words. Actor request, admission, egress, and
external-merge queues remain explicit.

This single-family witness still does not model the syndrome/data-cell geometry
or a production-throughput external merge.

## Nondegenerate phi/noise geometry

`phi_noise_topology.erl` adds the first nondegenerate periodic decoder geometry.
It uses six `Distance`-by-`Distance` families:
`phi_x`, `phi_z`, `syndrome_x`, `syndrome_z`, `data_even`, and `data_odd`.
`data_even[X,Y]` and `data_odd[X,Y]` represent physical data coordinates
`[X,2Y]` and `[X,2Y+1]`. That parity split turns every cardinal neighborhood
into an ordinary wrapped translation between equal-shaped families, so the
current compact relation form needs no parity-dependent or affine index
language.

```mermaid
flowchart LR
    Caller["ERTS caller"] --> Runner["phi_memory_runner<br/>+ phi_memory_experiment"]
    Runner -->|"register_route + send"| Broker["hls_fabric<br/>route broker"]
    Broker -->|"32-bit routed AXIS<br/>endpoint 0 → 1"| Wrapper["phi_memory_debug_top"]
    Wrapper --> Gateway["phi_memory_gateway"]
    Gateway -->|"endpoints 2–6 → 0<br/>five routed event streams"| Broker
    Broker -->|"route + header + payload"| Runner

    Caller --> Debug["hls_debug"]
    Debug --> DebugBroker["hls_fabric<br/>debug route broker"]
    DebugBroker -->|"routed debug AXIS<br/>endpoint 0 → 1"| Wrapper
    Wrapper -->|"routed counter / trace reply"| DebugBroker
    Wrapper -. "passive application<br/>RX / TX observation" .-> Monitor["hls_debug_monitor<br/>counters + 64-event trace"]

    Runner -->|"same calls and routed ABI"| CPU["phi_memory_cpu_fabric<br/>functional ERTS deployment"]
    CPU -->|"decoded spatial command"| CR
    CPU -->|"encoded routes 2, 4, 6"| Runner

    subgraph Fabric["normalized one-fabric topology"]
        CR["control_router<br/>spatial fanout"]
        PX["phi_x"] -->|"cardinal torus"| PX
        PZ["phi_z"] -->|"cardinal torus"| PZ

        PX -->|"request"| SX["syndrome_x"]
        SX -->|"result"| PX
        PZ -->|"request"| SZ["syndrome_z"]
        SZ -->|"result"| PZ

        SX <-->|"queries / replies"| DE["data_even"]
        SX <-->|"queries / replies"| DO["data_odd"]
        SZ <-->|"queries / replies"| DE
        SZ <-->|"queries / replies"| DO

        PX -->|"correction + post-move status"| XE["x_decoder_events<br/>source endpoint 4"]
        PZ -->|"correction + post-move status"| ZE["z_decoder_events<br/>source endpoint 6"]
        DE -->|"Pauli reply"| DM["data_measurements<br/>source endpoint 2"]
        DO -->|"Pauli reply"| DM

        CR -->|"whole grid: noise_cutoff"| DE
        CR -->|"whole grid: noise_cutoff"| DO
        CR -->|"whole grid: noise_cutoff"| SX
        CR -->|"whole grid: noise_cutoff"| SZ
        CR -->|"point: pauli_update<br/>whole grid: pauli_query"| DE
        CR -->|"point: pauli_update<br/>whole grid: pauli_query"| DO
    end

    Gateway -->|"one SpatialFrame stream"| CR
    XE & ZE & DM -->|"generated channels"| Gateway
    XE & ZE & DM -. "ordinary records via<br/>CPU forwarding processes" .-> CPU

    XE -. "map each correction<br/>to a point update" .-> Runner
    ZE -. "map each correction<br/>to a point update" .-> Runner
    XE -. "complete quiet + empty<br/>same-step X status" .-> Runner
    ZE -. "complete quiet + empty<br/>same-step Z status" .-> Runner
    DM -. "one selected-basis snapshot<br/>canonical bit witness" .-> Runner
```

At the default distance three, the plan has 54 actor instances, 34 compact
route relations, and 54 explicit startup messages: one for every actor. The
route-rule count is independent of distance; only the family bounds and startup
entries grow. PRNG seeds are deterministic, distinct, and nonzero across all
six families. The noise seeds are deliberately mixed so the first
distance-three syndrome plane is not spatially uniform.

Each syndrome result carries its `{X, Y}` coordinate and is delivered only to
the corresponding phi plane. The former external copies existed solely for
visualization and have been removed from the lossless application boundary;
endpoints 3 and 5 remain reserved so the boundary version does not silently
remap its surviving streams. Each phi cell retains that coordinate and may
emit one `phi_correction` after its four anyon-move actions for the step,
followed by a `phi_status` reporting occupancy and propagated noise-quiet
state. Correction and status share one plane boundary, which preserves each
source cell's order while leaving cross-cell merge order unspecified. The
plane, syndrome coordinate, and selected direction together identify the
neighboring data-qubit edge; the single event stream does not mean that a phi cell is associated
with only one data qubit.

The correction action is a statically placed `cast_if`: it retains its position
in the ordered entry-effect list, but its move predicate suppresses the frame
when no correction was applied. This matches the reference implementation's
sparse correction behavior, so traffic scales with corrections rather than
physical qubits and steps.

Each data actor retains one cumulative projective Pauli containing both
physical errors and applied decoder corrections. The current binary noise event
is Y because it is visible to both syndrome planes; two such events cancel.
After cutoff, `pauli_query` asks whether that frame anticommutes with a requested
Pauli measurement. This operation nondestructively inspects the simulator's
classical accumulator; the physical memory protocol uses it for only one basis
before reset. The reply carries a request ID, physical data coordinate, and
parity bit. Both data families share one fairly merged output; request IDs and
coordinates make its unspecified cross-family order irrelevant.

These `external` endpoints remain five typed channels on the generated
topology, but `phi_memory_gateway` now merges them into distinct routed source
endpoints. `hls_fabric` registers all five routes to one `phi_memory_runner`,
which decodes their records and feeds the pure reducer. Route identity supplies
the plane or measurement-stream identity that is deliberately absent from the
actor payload. `phi_memory_boundary` derives this canonical output order, the
endpoint allocation shown in the diagram, and each selector and packed width
from the compact topology and generated actor codecs; the host wire codec and
DSLX gateway generator consume the same contract.

`phi_memory_cpu_fabric` is the example-local realization of that same compact
plan. It starts every family member as a disconnected `hls_statem`, resolves
each member's routes from the normalized relations, and groups output ports
with the same recipients behind one forwarding process. It queues all startup
messages and the first cutoff before connecting data and syndrome actors, then
phi actors; the decoder therefore cannot outrun the command which closes its
noise epoch. Rectangle delivery uses the normalized ingress embeddings rather
than a second copy of the checkerboard geometry.

The CPU realization accepts the same `register_route` and `send` calls as
`hls_fabric`, and decodes commands and encodes events through
`phi_memory_wire`. The runner and reducer are consequently unchanged between
CPU and transported deployments. Its actor and forwarding mailboxes are
ordinary Erlang mailboxes, however: this is a functional reference for the
current topology subset, not a model of bounded network backpressure, physical
fanout completion, reset, or admission.

Host commands use destination endpoint 1. Their boundary frame has four
payload words: a full-width prefix of four little-endian `u16` rectangle bounds
followed by one or two actor payload words. The generator therefore selects
`axis::FrameN<4>` for the current contract; the capacity follows the widest
declared command rather than being a global `axis::Frame` limit. This wider
boundary does not change the three-word actor ABI. The gateway validates the
route, boundary version, message length, rectangle, and target-specific payload
before constructing the ordinary actor frame. Its first valid command also
supplies a one-shot egress activation token, so topology output cannot escape
before the host has installed its routes.

The generated gateway contains only that phi-specific validation, output
selection, and topology composition. It imports route-envelope ingress, the
activation gate, and frame serialization from `hls_fabric_router.x`; those
transport procs are shared with other fabric boundaries rather than repeated
as a static block in the Erlang generator.

`phi_memory_debug_top` wraps that generated gateway with the same passive
monitor used by the smaller `regsvc` example. A second `hls_fabric` owns the
independent debug stream and routes requests to monitor endpoint one. The
distance-one and distance-three ERTS/Icarus bridge tests issue live counter and
trace requests, decode populated maps, require observed application traffic in
both directions, and reject any passive-observation drop. The trace is attached
outside the application route-envelope decoder, so it describes physical
routed packets rather than actor selectors, mailbox admission, coordinates, or
state transitions. This is a useful boundary-health apparatus, not yet a
semantic actor debugger.

An out-of-context XC7 mapping of the generated distance-one gateway measured
the constant boundary cost with `synth_xilinx -flatten -abc9 -noiopad`:

| boundary | estimated logic cells | flip-flops | LUT1–LUT6 | `RAMB36E1` | `DSP48E1` |
| --- | ---: | ---: | ---: | ---: | ---: |
| application gateway | 19,033 | 16,393 | 21,732 | 0 | 16 |
| gateway + routed debug monitor | 20,207 | 18,665 | 22,975 | 2 | 16 |

The monitor adds 1,174 estimated logic cells (6.2%), 2,272 flip-flops (13.9%),
1,243 LUTs (5.7%), and two block RAMs, with no additional DSPs. The two trace
banks account for the block RAMs. This is an exact distance-one boundary A/B;
the monitor is instantiated once per gateway, so these numbers should not be
multiplied by the actor count or presented as a mapped distance-three result.

The one application ingress is the externally addressed `control_router`
service. Its envelope contains an ordinary actor frame plus an internal target
and inclusive rectangle. `noise` selects all noise actors, while `data`
selects data actors for Pauli queries or correction updates. Coordinates name
stable logical services, like registered process names, rather than actor
incarnations; one broadcast may therefore straddle lifecycle churn. The
present whole-topology reset flushes router and actor traffic together.
Independent restart will need lifecycle-owned flushing or generation checks at
the leaves.

A malformed routed packet is drained without actor delivery so the receiver
can accept the next packet in sync. The present boundary has no trustworthy
operation identity or reserved error path for every malformed packet, so this
case ends at the runner timeout. A later typed protocol-fault sideband should
close the owning connection; actual transport-process failure already reaches
the runner through its `hls_fabric` monitor as `{fabric_down, Reason}`.

The current physical lowering uses one lossless, statically unrolled
distributor per family. It finishes the selected family sends before accepting
another envelope, but top-level router acceptance is bounded network admission,
not simultaneous actor-mailbox admission. The gateway validates rectangle
bounds and target/schema combinations before this point. Pauli updates are
at-most-once: a malformed frame, transport failure, reset, or timeout aborts
the experiment, and retry will require an explicit operation identity and
bounded duplicate suppression.

`hls_spatial_router.x` also defines tested pair, quadrant, and leaf building
blocks for a later generated tree inside one fabric. Neither implementation
defines how a global rectangle is partitioned, addressed, or retried across
multiple FPGAs. A multi-FPGA adapter must intersect the rectangle with each
local partition and re-originate explicitly addressed per-fabric commands;
partial delivery and failure semantics remain unresolved.

`phi_memory_experiment` is the example-local, pure ERTS reducer for closing one
memory experiment. It first sends a whole-grid cutoff. Every data reply then
propagates its persistent quiet bit through the syndrome result and phi
status. The reducer translates each sparse correction into a point-addressed
`pauli_update` immediately. A complete same-step status set from both decoder
planes closes the decoder only when every coordinate is quiet and empty.
Because each cell's status follows its optional correction on the same ordered
plane output, the two complete sets also fence all earlier correction events.
The reducer then issues one whole-data-grid `pauli_query` in the caller-selected
basis after the queued point updates. The canonical result records the common
closeout step, every coordinate's anticommutation bit, the sorted correction
set, and the parity of the selected horizontal row. A complementary-basis
measurement requires reset and a separate run; sequential X and Z queries
would not describe one physical shot. This is a sound completion witness, not
a liveness guarantee: the current fixed-round decoder can leave symmetric
nonempty anyon configurations stationary. Until its tie-breaking or stopping
rule is
strengthened, the ERTS runner must bound the closeout wait and report
nonconvergence rather than inferring completion from elapsed time. This first
protocol assumes one lossless, non-restarting fabric activation; a reset or
gateway failure aborts the experiment rather than invoking unspecified retry
behavior.

The present distance-three noise configuration is still a plumbing fixture.
Its common high noise rate deliberately produces frequent binary events rather
than modeling a full Pauli channel. That rate is encoded as the `u32` threshold
used by each cell's Bernoulli comparison. The explicit startup list also caps
this example at distance 50; the compact route representation itself has no
such bound. The direct VPI bridge now transports the reducer's ordered commands
and the five routed output streams in simulation. The real DMA `axismsg` driver
still expects its older unrouted frame boundary and must be adapted before this
gateway can be used on a PS/PL link. A physically calibrated noise model remains
later decoder work.

### Ordered-egress capacity experiment

Actor actions share one serialized egress. On an initially empty path, the
`burst` policy sizes its FIFO so that the FIFO and XLS's registered producer
output can hold the actor's largest phase-entry action list. This relies on the
repository code generators retaining `--flop_outputs=true`. Literal profile
values select a uniform FIFO depth for experiments.

An out-of-context d=2 XC7 comparison measured the actor-egress alternatives
with consumer input flops disabled and producer output flops enabled:

| actor-egress FIFO | estimated logic cells | flip-flops | LUT1–LUT6 | `DSP48E1` |
| --- | ---: | ---: | ---: | ---: |
| previous FIFO-only sizing: 4 for data/syndrome, 5 for phi | 69,801 | 57,634 | 92,258 | 512 |
| burst accounting for the producer slot: 3 and 4 | 68,688 | 55,489 | 90,872 | 512 |
| uniform depth one | 65,276 | 50,499 | 88,090 | 512 |

Accounting for the existing producer slot reduces the conservative row by
1.6% of estimated logic cells, 3.7% of flip-flops, and 1.5% of LUTs without
reducing its initially empty burst capacity. Uniform depth one reduced the
counts further, but neither it nor uniform depth zero reached quiet decoder
status in the d=1 smoke bench within 200,000 cycles. The selected burst policy
passed that bench and the full d=3 ERTS/Icarus memory closeout. The depth-zero
d=2 graph reached XLS code generation but was not mapped.

These d=2 results are area witnesses, not decoder-geometry or timing results:
distance two aliases cardinal routes, and the synthesis jobs shared one
physical host. The table records deterministic mapped resource counts only;
it does not compare wall time, part fit, placement, routing, or timing closure.

### Fixed-point division experiment

The first Q15.16 lowering widened each signed recurrence numerator to 64 bits
and selected between separate positive and negative divisions. XLS implemented
each `/24` and `/20` path as a 64-bit reciprocal multiplier, using 64 DSPs per
phi actor. The actor invariant that exactly four `s32` neighbor fields enter
each sum gives tighter bounds: both weighted numerators fit in `s37`, their
biased magnitudes fit in `u36`, and their rounded quotients fit in `s33`.
Factoring `/24` into a shift by three followed by unsigned `/3`, and `/20` into
a shift by two followed by unsigned `/5`, preserves nearest rounding with ties
away from zero while leaving one narrow multiplier per recurrence.

An isolated generated phi actor mapped as follows:

| division lowering | estimated logic cells | flip-flops | LUT1–LUT6 | `DSP48E1` |
| --- | ---: | ---: | ---: | ---: |
| signed `s64` `/24` and `/20` | 5,706 | 6,452 | 7,675 | 64 |
| bounded unsigned `/3` and `/5` | 5,136 | 6,404 | 6,133 | 8 |

The selected d=2 topology profile retained the actor-level DSP reduction:

| division lowering | estimated logic cells | flip-flops | LUT1–LUT6 | `DSP48E1` |
| --- | ---: | ---: | ---: | ---: |
| signed `s64` `/24` and `/20` | 68,688 | 55,489 | 90,872 | 512 |
| bounded unsigned `/3` and `/5` | 68,852 | 55,105 | 79,070 | 64 |

The narrower lowering removes 87.5% of DSPs in both scopes and 13.0% of total
d=2 LUTs. Yosys's coarse logic-cell estimate rises by 0.2% in the composed
graph because more of the remaining logic maps to LUT3 rather than LUT2; the
underlying LUT total still falls. Generated interpreter tests cover every
rounding residue near zero, extrema of the valid four-neighbor domain, and
2,000 deterministic randomized comparisons with the wide recurrence. The
actor and full memory benches retain end-to-end coverage. These are again
mapping results, not placement, routing, or timing closure.

### Distance-three synthesis progression

The last out-of-context XC7 mapping progression, before the data-measurement
state and output were added, was:

| ingress | lane holding storage | consumer input flops | estimated logic cells | flip-flops | LUT1–LUT6 | `DSP48E1` |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| buffered mux trees | router output + depth-one FIFO | enabled | 193,795 | 264,146 | 214,606 | 72 |
| integrated credit-aware | router output + depth-one FIFO | disabled | 153,843 | 156,920 | 173,480 | 72 |
| integrated credit-aware | router output | disabled | 135,199 | 111,416 | 153,265 | 72 |

Using the already-registered router output as the lane's only holding slot
removes 12.1% of the remaining estimated logic cells, 29.0% of the flip-flops,
and 11.7% of the LUTs. Relative to the original wrapper, the cumulative
reductions are 30.2%, 57.8%, and 28.6%. The full stalled-output distance-three
bench passes with the reduced lane capacity. The global producer-output-flop
policy cannot also be disabled: XLS detects the resulting combinational
request/admission cycle.

All rows use the same logical routing graph and actor artifacts; their physical
lane and ingress configurations differ as shown. These are area-only synthesis
results; they establish no part fit, placement, routing, or timing closure. The
final ABC map has logic depth 32 versus 33 for the preceding row, but that is
only a coarse technology-mapping metric.

### Scheduler and state-storage experiment

The raw distance-three baseline and the register-array, relaxation-lane, and
one-block-RAM scheduler ablations now live in
[`experiments/08-phi-scheduler`](../../../experiments/08-phi-scheduler/README.md).
They are implementation experiments rather than backend components. The most
complete shared-state witness services this topology's routed ERTS protocol,
matches every correction and final data-qubit value from the CPU deployment,
and maps to 1,723 estimated XC7 logic cells, 1,293 flip-flops, 2,319 LUTs, one
`RAMB18E1`, and one `DSP48E1`. The experiment README records the scope,
comparison tables, latency tradeoffs, and reproduction commands.

The generated phi/noise deployment now consumes that physical plan. The two
data families share one homogeneous executor, as do the two syndrome families
and the two phi families. Each d=3 group therefore has 18 logical slots.
Callback state and mailbox frames use separate one-read/write RAM interfaces
per group. The executor keeps only bounded mailbox metadata—occupancy, order,
and postponement bits—in its own state. The target wrapper therefore supplies
six instances of the small `hls_1rw_ram` inference wrapper: one actor-state RAM
and one mailbox-frame RAM for each homogeneous group. XLS sees those RAM
operations but not 54 separate actor or mailbox-frame register banks.

```mermaid
flowchart LR
    Host["spatial control ingress"] --> Control["ControlDispatcher"]

    subgraph Groups["one instance per homogeneous group"]
        Inputs["bounded producer slots<br/>scheduler / control / route credit"]
        Shared["SharedService<br/>mailbox owner + actor scheduler"]
        Router["group router<br/>slot + translated destination"]
        StateRAM["actor-state RAM"]
        MailboxRAM["mailbox-frame RAM"]

        Inputs --> Shared
        Shared -->|"scheduled egress"| Router
        Router -->|"credit after bounded acceptance"| Inputs
        Shared <-->|"read / write"| StateRAM
        Shared <-->|"read / write"| MailboxRAM
    end

    Control --> Inputs
    Router -->|"addressed request"| Other["destination group's<br/>producer slot"]
    Router --> ExternalQ["one bounded queue<br/>per external output"]
    ExternalQ --> External["gateway / test output"]
```

Each producer has one holding slot before mailbox admission, so a full target
does not stop the manager from capturing unrelated traffic. The manager
alternates admission work with round-robin actor visits, preserving bounded
mailbox order and allowing postponed messages and phase-entry effects to be
retried. A blocked ordered effect keeps its effect index and yields the
executor; an accepted effect advances that index and is never rolled back or
resent. Only one egress is outstanding per group. Its router returns credit
after the selected destination request slot or external queue accepts the
complete frame. The external queues are important: one stalled observation
port does not prevent another group from completing an otherwise independent
route until that port's own bounded queue fills.

The scheduler does not tentatively acquire several downstream resources, so
the symmetric "reserve, collide, release, retry" livelock does not arise inside
this implementation. This is not a general network progress proof. A protocol
can still deadlock after committing a resource acquisition, and future
generated components which truly require several grants must use one
deterministic grant point, a global acquisition order (potentially derived
from logical address), or a separately proven escape class rather than
symmetric rollback.

#### Shared mailbox layout

Each homogeneous d=3 group owns one logical array of 18 actor mailboxes. The
slot order is X-major within each family: `slot = family_base + 3*x + y`.
The first family in a group has base zero and the second has base nine:

| group | slots 0–8 | slots 9–17 |
| --- | --- | --- |
| data | `data_even` | `data_odd` |
| phi | `phi_x` | `phi_z` |
| syndrome | `syndrome_x` | `syndrome_z` |

Every actor has five physical frame positions. Position `i` for actor slot `s`
is mailbox-RAM address `5*s + i`, so the 18 logical mailboxes occupy addresses
0 through 89 of one 128-by-128-bit inferred RAM. A frame word stores
`payload_words`, transaction ID, flags, and operation in bits 0–31, followed
by the 96-bit actor payload in bits 32–127. The mailbox RAM itself is not reset:
the reset scheduler metadata says that all positions are free, so stale frame
bits cannot be selected.

Queue order is deliberately not represented by moving those 128-bit words.
For each actor the scheduler keeps an 8-bit occupancy count, five 8-bit
physical-position indices in logical arrival order, and five postponement
bits. Admission chooses an unused physical position and appends its index.
Consumption compacts only the small index row; postponement marks the physical
position until the actor reaches a phase boundary. These metadata cost 954
register bits per group and remain local to the scheduler in this first
implementation.

The frame RAM is distinct from the actor-state RAM. State address `s` contains
one packed machine word for actor slot `s`: phase, previous phase, callback
record, pending-entry flag, and failure flag. The words are 434 bits for data
and syndrome actors and 546 bits for phi actors. Eighteen words are live in
each 32-entry inferred state RAM. Unlike the mailbox RAM, the scheduler
initializes those live words during its boot sweep. Shared actors no longer
store an entry-effect cursor: the scheduler commits an entire entry batch,
and the one cursor for draining it belongs to the group router.

There are also small register-resident queues around this storage. Each
incoming producer has one `ScheduledRequest` holding slot (three producers for
the data and phi groups, four for syndrome), and each group permits one
outstanding scheduled egress. These prevent a full logical mailbox or a
stalled route from occupying the shared RAM transaction machinery; they are
not additional per-actor mailboxes.

### Distance-three RTL simulation

`tools/run_phi_noise_topology_sim.sh` is the opt-in full-graph regression. It
regenerates the distance-three DSLX, runs XLS conversion, optimization, and
Verilog generation on the configured build host, then compiles and runs
`phi_noise_topology_tb.sv` with Icarus. The cost is deliberately excluded from
the routine CI job.

The distance-three bench holds one decoder-event stream under backpressure,
checks that its frame remains stable, and otherwise continuously drains every
output. It requires every status coordinate from both planes in steps zero
through two, proving that steps zero and one completed everywhere. The current
deterministic fixture also produces sparse corrections; the bench compares
those as coordinate/direction sets rather than as one globally ordered trace.
Those sets are regression goldens for this fixture, not a logical-correctness
or winding test.

The same bench drives `control_router` over the nondegenerate physical
coordinate space. It broadcasts a future cutoff over the full 3-by-6 data
grid, requires all 18 phi cells to report quiet in that exact step, queries the
three data qubits on physical row four, applies one point-addressed X update,
and queries the row again. The XOR of the three Z-anticommutation replies must
toggle. This verifies rectangular target embedding and the correction/query
path in the synthesized D3 network; it deliberately does not wait for empty
decoder planes or claim a logical-correctness result.

The routine distance-one topology smoke bench does drive `control_router`. It
sends one whole-fabric cutoff, waits for propagated quiet status, inspects one
data line, applies one point-addressed X update, and observes the corresponding
anticommutation change with a second same-basis inspection. That is a
nondestructive simulator plumbing check, not two physical measurements.
Distance one aliases decoder routes, so the bench does not test the
nondegenerate drain criterion.

`phi_memory_gateway.x` is the checked generated wrapper for the distance-three
topology. The routine remote regression instead generates the same wrapper
around a zero-noise distance-one topology, compiles it through XLS and Icarus,
and connects its AXIS ports to `hls_fabric` through the VPI FIFO bridge. A real
`phi_memory_runner` then sends cutoff, observes the quiet/empty fence, issues
one whole-grid Z query, and returns the two zero anticommutation bits to its
ERTS caller. This is an end-to-end transport and protocol witness; the aliased
distance-one geometry is not a decoder-correctness test.

The local regression now performs the full noisy distance-three closeout with
cutoff step 16, physical row four, and a Z measurement through
`phi_memory_cpu_fabric`. Its deterministic full-device witness closes at step
21, contains 84 corrections, records 18 Z-anticommutation bits (six set), and
returns row parity one. Run the same fixture through both the CPU realization
and the checked distance-three gateway with:

```sh
tools/run_phi_memory_demo.sh
```

Set `ERL_HLS_PHI_NATIVE_ICARUS=1` to keep XLS conversion and code generation
on the configured build host but retrieve the generated Verilog and run the
VPI bridge plus Icarus on the local machine.

The script derives the distance, noise rate, experiment options, and compact
golden summary from `phi_memory_demo:fixture/0`. The CPU regression writes its
complete canonical witness into the staging directory; the remote bridge must
match that exact term as well as the checked summary. The script uses the
`ERL_HLS_REMOTE_*` settings described in the README, retrieves only logs and
compact metrics, and leaves the generated Verilog on the remote build host.
This comparison remains outside routine CI because of the costs below.

On the 4-core, 8-GiB UTM using the pinned XLS build, the earlier line-parity
comparison passed with parity one. It measured about 33 seconds and 449 MiB
for DSLX conversion, 6 minutes 28 seconds and 3.21 GiB for optimization, 1
minute 10 seconds and 294 MiB for code generation, 27 seconds and 472 MiB for
Icarus compilation, and 4 minutes 45 seconds and 151 MiB for simulation. The
generated Verilog is about 8.6 MiB and 150,146 lines. These are host build
costs, not an FPGA utilization estimate; the runner saves compact timing and
digest reports but does not copy that Verilog into the repository.
Reusing that compiled Icarus image, the later full-device witness comparison
completed in 5 minutes 42 seconds. Wrapping the gateway and then retrieving
live counters and a full 64-event trace increased the same comparison to 8
minutes 26 seconds. This is Icarus wall time, not a hardware latency estimate.

The homogeneous scheduler and shared mailbox implementation passes the same
nondegenerate topology bench in 40,159 post-reset clocks. The last replicated
implementation of this bench finished in approximately 1,229 clocks, so this
version trades about 33 times as many hardware clocks for its much smaller
generated graph. On the same UTM and the upgraded XLS build, conversion took
22 seconds and 232 MiB, optimization 32 seconds and
151 MiB, code generation 11 seconds and 71 MiB, and Icarus compilation 4
seconds and 74 MiB. The generated Verilog is 764 KiB and 13,735 lines, versus
8.6 MiB and 150,146 lines for the replicated deployment above. Icarus took 11
minutes 46 seconds to run the serialized design. These measurements expose
the intended spatial/temporal trade: compilation and generated structure
shrink sharply while a software event simulator must execute more hardware
clocks.

Most of that clock increase is structural rather than arithmetic latency. A
logical delivery now crosses a producer holding slot, a mailbox-RAM write, a
round-robin actor visit, parallel state/mailbox reads, one resumable actor
microstep, a state-RAM write, and an egress-credit round trip. One executor
per group serializes those visits across 18 actors, while the control ingress
also scans addressed family coordinates. The replicated graph lets all 54
mailboxes and actor machines make progress concurrently.

The handwritten global-schedule baseline is not a like-for-like clock
comparison. Its complete 84-correction closeout takes 69,722 clocks, while the
one-BRAM DSLX worker takes 175,408 clocks; the topology bench above stops after
its step-two/cutoff/query/update witness. Both experimental workers exploit a
global round schedule, avoid actor mailboxes and per-message dispatch, and can
therefore do substantially more useful work per serialized control transition.

An out-of-context XC7 map of the generated scheduler core reports 36,770
estimated logic cells, 14,430 flip-flops, 43,620 LUTs, and 96 `DSP48E1`s. This
map leaves the six RAM response ports at the core boundary, so it excludes the
separately instantiated RAM macros and is not a complete part-fit result. The
last replicated D3 core above reported 135,199 logic cells and 111,416
flip-flops, although that older measurement predates some measurement-path
additions. Of the scheduler core's 96 DSPs, only eight appear in an isolated
phi actor; the other 88 come from the current routers' full-width division,
remainder, and linear-coordinate arithmetic. Narrow bounded coordinate
arithmetic is therefore a high-value follow-up without changing actor or
mailbox semantics.

The quadtree broadcast used by `qec_runtime` remains a good model for a future
spatially partitioned control ingress: fixed, even region splits need only
bounded comparisons and fanout, not division. It does not by itself remove the
current egress cost, which comes from recovering `(x, y)` with `/ HEIGHT` and
`% HEIGHT` and then applying wrapped translations. Carrying a narrow named
family/coordinate address through the scheduled request, and flattening it
only at a destination RAM, should remove that arithmetic. A quadtree can then
distribute rectangles among several spatial scheduler partitions without
reintroducing one host message per actor.

The bounded-routing follow-up replaces that quotient/remainder reconstruction
with generated static maps between each scheduler's dense RAM slot and a
`{family, x, y}` address. Wrapped neighbor translations use only a comparison
and add/subtract at the topology's coordinate width. The address is immutable
topology metadata rather than another field in the wide, shallow actor-state
RAM. The same D3 topology bench passes in 39,875 post-reset clocks, compared
with 40,159 before the change.

An attempted generic alternative passed a packed address table as a proc
parametric whose width depended on the actor-count parametric. The current DSLX
type checker rejects that dependency as non-constant even when the width is a
separate parametric or the bits are wrapped in a parametric struct. Ordinary
parametric functions and structs do permit this kind of width expression. The
generated topology maps therefore keep the immutable table out of actor state
without relying on that proc-parametric limitation; a small compiler reproducer
is worth revisiting separately.

On the same out-of-context XC7 core map, the new router uses 32,327 estimated
logic cells, 13,144 flip-flops, 36,423 LUTs, and eight `DSP48E1`s. The 88 DSPs
attributed to routing disappear; the remaining eight belong to phi
relaxation. Relative to the first shared-scheduler map, this is a 12.1%
reduction in estimated logic cells, an 8.9% reduction in flip-flops, and a
16.5% reduction in LUTs. As above, these core-only figures leave the six
external RAMs at the boundary.

The full ERTS-plus-RTL fixture also matches the complete 84-correction CPU
witness and returns all 18 final Pauli replies. Cycle-stamped status frames
put completion of steps zero through 21 about 4,750 clocks apart; two native
replays averaged 4,749.8 and 4,758.1 clocks per step. This corresponds to
about 21.1 thousand decoder steps per second at 100 MHz or 42.1 thousand at
200 MHz; a one-megahertz decoder-step rate would require an impractical
4.75 GHz clock.
At 200 MHz, the present architecture therefore needs about 24 times as much
effective parallelism to meet the rate target.

Native arm64 Icarus materially improves regression wall time without changing
RTL semantics. The identical 39,875-clock topology bench takes 19.75 seconds
on the M2 host rather than 11 minutes 55 seconds in its local x86 UTM, a 36x
speedup. A native full-witness replay completes in about 58 seconds. Verilator
is also cycle-accurate for this synchronous synthesizable RTL, but using it
for the transported demo will require a compiled host harness in place of the
current Icarus VPI bridge; its two-state emphasis also makes it a complement
to, rather than a complete replacement for, four-state Icarus checks.

The native bridge can profile the shared schedulers through VPI without adding
ports, counters, or state to the synthesized design. It discovers
`SharedService` instances and samples their request, state-RAM, mailbox-RAM,
and egress handshakes. The checked full-witness runner enables this profile and
records the interval from the first accepted application beat through the last
application output beat in `phi_memory_demo.metrics`.

One 84-correction replay measured 104,665 clocks over that interval:

| Scheduler | Actor visits | Visits with mail | Clocks per visit | Request stall clocks | Egresses |
| --- | ---: | ---: | ---: | ---: | ---: |
| data | 20,592 | 2,080 (10.1%) | 5.083 | 8,735 | 1,602 |
| syndrome | 20,534 | 1,998 (9.7%) | 5.097 | 9,745 | 1,993 |
| phi | 19,585 | 12,543 (64.0%) | 5.344 | 15,007 | 7,209 |

Every completed visit, busy or idle, took exactly two clocks from its state
read request to its state write request. The gap from that write to the next
read averaged 3.083 clocks for data, 3.097 for syndrome, and 3.344 for phi.
No state-RAM request, mailbox-RAM request, or scheduler-egress stall was
observed. The producer request stalls are time spent waiting for the
scheduler's single-entry producer holding slots, not stalls at the external
RAMs or output routers.

This rules out handler arithmetic and downstream backpressure as the immediate
source of the cycle-count multiplier. The current executor pays an
approximately five-clock non-overlapped visit for every one of its 18 actor
slots, including empty mailboxes, so an actor is reconsidered only about once
per 91--96 clocks.

The first sharding experiment assigns each of the six D3 families to its own
nine-slot executor, retaining separate state and mailbox RAMs for every shard.
The same complete 84-correction witness passes in 54,224 debug-counted clocks;
the interval from first accepted application beat through last application
output is 53,319 clocks, 1.96 times faster than the three-executor profile.
Cycle-stamped status frames put completion of steps zero through 21 an average
of 2,413 clocks apart. This is about 41.4 thousand decoder steps per second at
100 MHz or 82.9 thousand at 200 MHz. A one-megahertz step rate would still
require 2.41 GHz, equivalently about 12.1 times the present effective
parallelism at 200 MHz.

The six executors again completed every busy and idle visit in exactly two
clocks and observed no state-RAM, mailbox-RAM, or egress stall. The speedup is
therefore the expected effect of two concurrent nine-slot scans rather than a
new memory or routing bottleneck. An out-of-context XC7 map reports 39,834
estimated logic cells, 19,607 flip-flops, 47,112 LUTs, and 16 `DSP48E1`s. The
one-shard bounded-router core used 32,327 cells, 13,144 flip-flops, 36,423
LUTs, and eight DSPs. Two-way sharding therefore buys nearly twice the rate for
23.2% more estimated logic cells, 49.2% more flip-flops, 29.3% more LUTs, and a
second phi datapath's eight DSPs. Both maps exclude the external RAM macros;
the sharded core exposes twelve RAM interfaces rather than six, while storing
the same total number of actor and mailbox entries.

The ready-slot implementation makes those scheduler states explicit with
three bits per actor. `mail_candidates` records a mailbox with an eligible,
non-postponed message. `entry_probes` records pending entry work whose next
resource need has not yet been classified. `egress_waiters` records entry work
known to need the scheduler's one outstanding egress credit. Mailbox work is
latent while either entry bit is set, and egress waiters become selectable
together when the shared credit returns. Servicing one waiter consumes the
credit and makes the others temporarily unselectable again.

Selection is fair and work-conserving. Two statically unrolled priority passes
find the first selectable slot at or after the round-robin cursor, falling back
to the first selectable slot before it. This avoids both an empty cyclic scan
and the large dynamic-index mux synthesized by an earlier rotated-mask
implementation. Entry execution either completes, remains a probe for its next
effect, or becomes an egress waiter; it never speculatively loops through entry
states while a resource is unavailable.

The complete CPU-versus-Icarus comparison still agrees exactly on all 84
accepted corrections and all 18 final data-qubit replies. Aggregate actor-state
visits fell from 61,888 to 22,501, a 63.6% reduction. Of the remaining visits,
10,839 read a mailbox and 11,662 execute pending entry work. The profiler now
calls these `mailbox_visits` and `entry_visits`; the earlier `busy` and `idle`
names obscured that a visit without a mailbox read can be useful entry work.

The observed full-witness interval fell from 53,319 to 50,191 clocks, and the
mean interval between completed decoder steps fell from about 2,413 to 2,272
clocks, both improvements of about 5.9%. The result is about 44.0 thousand
decoder steps per second at 100 MHz or 88.0 thousand at 200 MHz. One million
steps per second would require 2.27 GHz if expressed as clock frequency alone,
or about 11.4 times the present effective parallelism at 200 MHz. The much
larger reduction in visits than in elapsed clocks shows that empty-slot scans
were substantially overlapped with inter-family dependency and credit flow;
request admission and useful actor visits now dominate this experiment.

An out-of-context XC7 map reports 40,415 estimated logic cells, 19,945
flip-flops, 48,930 LUTs, and 16 `DSP48E1`s. Relative to the first sharded core,
ready selection adds 1.5% cells, 1.7% flip-flops, and 3.9% LUTs, with no DSP
increase. Both maps exclude the same twelve external RAM macros. This is a
reasonable area cost for eliminating almost two-thirds of state-memory traffic,
even though it confirms that ready selection alone is not the remaining
throughput breakthrough.

### Batched entry effects

Shared actors now compute all of one `handle_enter/3` callback's effects in a
single state visit. The scheduler admits the resulting ordered batch as its
commit point, writes the entered actor state, and may immediately choose
another actor. A scheduler-local router retains the batch and emits at most one
valid action per activation in source order. It returns the scheduler's one
egress credit only after the last batch position has drained. This retains the
single-resource acquisition rule used by the deadlock argument: no actor state
or mailbox transaction remains held while a downstream action is blocked.

Conditional casts occupy their original batch positions but are skipped when
false. A batch is transmitted only when at least one effect is valid, and its
static capacity is the largest entry-action list for that actor type: four
effects for data and syndrome cells and five for phi cells. Entry work that
finds the sequencer busy remains an egress waiter. Because callbacks are pure,
the scheduler can reread and recompute that batch after credit returns without
storing speculative actor state.

The complete CPU-versus-native-Icarus comparison continues to agree on all 84
accepted corrections and all 18 final data-qubit replies. Compared with ready
selection alone, the interval from the first accepted application beat through
the last application output falls from 50,191 to 35,892 clocks, a 28.5%
reduction and a 39.8% throughput increase. Aggregate actor-state visits fall
from 22,501 to 15,932. Entry visits fall from 11,662 to 4,878 (58.2%), while
mailbox visits move from 10,839 to 11,053; the latter small increase reflects a
different legal inter-family arrival order. The profiler's 3,205 `egresses`
now count admitted effect batches, whereas the earlier 10,832 count individual
effects and therefore is not a like-for-like traffic reduction.

Cycle-stamped status frames put completion of steps zero through 21 an average
of 1,618.6 clocks apart, down from about 2,272 clocks. This is about 61.8
thousand decoder steps per second at 100 MHz or 123.6 thousand at 200 MHz. A
one-megahertz step rate would require about 1.62 GHz if expressed as clock
frequency alone, or 8.1 times the present effective parallelism at 200 MHz.
The native Icarus witness completed in 36 seconds, versus 45 seconds for the
ready-slot design.

An out-of-context XC7 core map reports 43,872 estimated logic cells, 23,035
flip-flops, 52,745 LUTs, and 16 `DSP48E1`s. Relative to ready selection this is
an 8.6% logic-cell, 15.5% flip-flop, and 7.8% LUT increase, with no additional
DSPs, for 39.8% more effective throughput. Throughput per estimated logic cell
therefore improves by about 28.8%. The wider batch channels and the six
in-flight router records explain most of the register increase. As with the
previous maps, these core-only figures exclude the twelve external RAM macros.

### Fused dispatch and phase entry

When a shared actor's message handler changes or repeats its phase, the
scheduler now evaluates that phase's `handle_enter/3` callback during the same
state visit. If the resulting entry batch is empty, or the batch sequencer can
accept it, the handler result and entered actor state commit together. This
removes the usual second state-memory visit between dispatch and entry. If a
nonempty batch cannot be accepted, the scheduler retains the former two-visit
fallback: it commits the phase transition with entry pending, classifies the
actor as an egress waiter, and recomputes the pure entry callback after credit
returns. Direct, one-service-per-actor lowering is unchanged.

The complete CPU-versus-native-Icarus comparison again agrees exactly on all
84 accepted corrections and all 18 final data-qubit replies. Relative to
batched entry alone, the measured interval from the first accepted application
beat through the last application output falls from 35,892 to 29,731 clocks, a
17.2% cycle reduction and a 20.7% throughput increase. Aggregate actor-state
visits fall from 15,932 to 13,023, and separate entry visits fall from 4,878 to
1,474. The remaining entry visits are the fallback taken while an earlier
batch is still draining.

Cycle-stamped status frames put completion of steps zero through 21 an average
of 1,339.8 clocks apart, down from 1,618.6 clocks. This is about 74.6 thousand
decoder steps per second at 100 MHz or 149.3 thousand at 200 MHz. One million
steps per second would require about 1.34 GHz if expressed as clock frequency
alone, or about 6.7 times the present effective parallelism at 200 MHz. The
native Icarus witness completed in 33 seconds.

The out-of-context XC7 core map reports 44,261 estimated logic cells, 23,031
flip-flops, 52,613 LUTs, and 16 `DSP48E1`s. Compared with batched entry alone,
that is 0.9% more estimated logic cells, four fewer flip-flops, and 0.3% fewer
LUTs, with no DSP increase. Effective throughput per estimated logic cell
therefore improves by 19.7%. Both maps exclude the same twelve external RAM
macros.

### First overlapped shared-scheduler attempt

The first pipelined scheduler captured producer requests while reading the
selected actor's state and mailbox entry. After the pure actor microstep had
produced an accepted effect batch, the scheduler issued the actor-state write
and any pending mailbox admission without waiting synchronously for their
completion.
The following actor read, or the idle collection phase when no actor is ready,
drains those completions. Requests to each single-port RAM remain on one
ordered channel, and at most one completion per RAM is outstanding, so a new
read cannot overtake the preceding write. The effect-batch send still precedes
both writes on the token path; downstream backpressure therefore cannot expose
speculative actor or mailbox state.

This changed a continuously active actor visit from three clocks--read,
execute/write, and collect/write-completion--to two clocks--read and execute.
Idle schedulers retained the collection phase. Producer admission and returned
batch credits use one shared combinational transition in both the idle and
commit paths; spelling that pure transition once is important, because an
initial two-call form made XLS duplicate much of the mailbox-management logic.
No actor-state width, mailbox depth, effect-batch width, or RAM-port count
changes.

The complete CPU-versus-native-Icarus comparison again agrees on all 84
accepted corrections and all 18 final data-qubit replies. Relative to fused
dispatch and entry, the interval from the first accepted application beat
through the last application output falls from 29,731 to 20,170 clocks, a
32.2% cycle reduction and a 47.4% throughput increase. The profiler observes
12,981 actor-state reads, essentially unchanged from 13,023, but every
completed mailbox and entry visit now takes exactly two clocks rather than
three. The improvement therefore comes from overlapping RAM completion and
request capture, rather than eliminating useful actor work. Native Icarus
completes the witness in 26 seconds, down from 33 seconds.

Cycle-stamped status frames put completion of steps zero through 21 an average
of 902.6 clocks apart, down from 1,339.8 clocks. This is about 110.8 thousand
decoder steps per second at 100 MHz or 221.6 thousand at 200 MHz. A one-megahertz
step rate would require about 903 MHz if expressed as clock frequency alone,
or about 4.5 times the present effective parallelism at 200 MHz.

An out-of-context XC7 core map reports 54,634 estimated logic cells, 23,239
flip-flops, 64,689 LUTs, and 16 `DSP48E1`s. Relative to fused dispatch and entry,
that is 23.4% more estimated logic cells, 0.9% more flip-flops, and 23.0% more
LUTs, with no DSP increase, for 48.4% more completed-step throughput. Effective
throughput per estimated logic cell improves by 20.3%. The combinational area
increase is the cost of updating mailbox-admission and actor-completion
metadata in one activation; the nearly unchanged register count confirms that
the overlap did not duplicate actor or mailbox storage. As above, the map
excludes the same twelve external RAM macros. The fixed pipeline below
supersedes this revision.

### Fixed two-stage shared-scheduler pipeline

An ablation first separated dispatch from phase entry while retaining the
first pipeline's single-port RAM protocol. It passed the complete witness but
only reduced the core from 54,634 to 53,398 estimated logic cells, while the
application interval grew from 20,170 to 24,233 clocks. Its 23,241 flip-flops,
63,810 LUTs, and 16 `DSP48E1`s likewise remained close to the expensive first
attempt. The area increase therefore did not principally come from fusing
dispatch with entry, and simple unfusion was rejected as both large and slower.

The replacement is a fixed, in-order pipeline with two registered actor
contexts. In one steady `RUN` activation, the older context performs phase
entry and retires while a distinct younger context receives its state and
mailbox values and performs message dispatch. Each actor-state and mailbox
store is now a simple-dual-port RAM with one read and one write port. There is
no periodic collection trigger: write responses are collected at the start of
the next `RUN` activation, and the independent write port accepts the older
commit while the read port opens the younger visit.

Pipeline position supplies the age order used for hazards. The younger slot
is excluded from admission and from the next ready selection until its dispatch
result has advanced to the older context. Retirement projects the older
context's queue and readiness metadata before selection, so that slot may be
chosen again only after its state write. Thus simultaneous RAM accesses always
belong to distinct actors; a scheduler with only one ready actor deliberately
bubbles rather than forwarding speculative state. This is a small instance of
the visibility discipline described in [*High-Level Synthesis of Efficient
Pipelines with Visibility Control*](https://arxiv.org/abs/2607.18765): fixed
stage order identifies older effects, while unresolved younger same-address
accesses are withheld. The scheduler does not need transaction sequence tags
or a dynamic rollback rule.

The distance-one RTL bench passes, and the complete CPU-versus-native-Icarus
comparison agrees on all 84 accepted corrections and all 18 final data-qubit
replies. The interval from the first accepted application beat through the
last application output was 13,322--13,350 clocks across repeated runs, down
from 20,170 clocks: about a 34% cycle reduction and a 51% throughput increase.
Although separating dispatch and entry raises aggregate actor-state reads from
12,981 to 15,326--15,354, every completed mailbox and entry visit takes exactly
two clocks. Each scheduler observes a minimum interval of two clocks between
accepted state reads, with no state- or mailbox-RAM request stalls. The
profiler also observes thousands of simultaneous read/write acceptances and no
same-row overlap in either RAM; both RTL topology benches assert that hazard
invariant directly. The native Icarus witness completes in 22 seconds.

Cycle-stamped status frames put completion of steps zero through 21 an average
of 576.3 clocks apart, down from 902.6 clocks. This is about 173.5 thousand
decoder steps per second at 100 MHz or 347.0 thousand at 200 MHz. One million
steps per second would require about 576 MHz if expressed as clock frequency
alone, or about 2.9 times the present effective parallelism at 200 MHz.

An out-of-context XC7 core map reports 41,345 estimated logic cells, 24,533
flip-flops, 53,718 LUTs, and 16 `DSP48E1`s. Relative to the first pipeline this
is 24.3% fewer estimated logic cells and 17.0% fewer LUTs, with 5.6% more
flip-flops for the registered contexts. It is also 6.6% fewer estimated logic
cells than fused dispatch and entry before pipelining; LUTs are 2.1% higher and
flip-flops are 6.5% higher than that revision. The map excludes the twelve
external RAM macros.

The new RAM interface does not duplicate stored contents. Separate XC7 maps of
the three instantiated RAM shapes infer the same primitives as their earlier
single-port counterparts: each 434-by-16 state RAM uses 13 `RAMB18E1`s, each
546-by-16 state RAM uses eight `RAMB36E1`s, and each 128-by-64 mailbox RAM uses
two `RAMB36E1`s. Across two data, two syndrome, and two phi schedulers, that is
52 `RAMB18E1`s and 28 `RAMB36E1`s, or 54 `RAMB36E1`-equivalents. Those figures
also expose the fragmentation cost of the current very wide, shallow actor
state layout; the fixed pipeline neither improves nor worsens it.

The reusable DSLX storage protocol now lives in `priv/xls/lib/bram.x`, while
`priv/xls/lib/mailbox.x` owns mailbox row types, flattened addressing, and
frame-row reads and writes. Generated actor modules retain public type aliases
for their state- and mailbox-RAM channels, so topology and gateway interfaces
remain actor-qualified without reproducing the protocol records and
constructors in every actor source. XLS still receives the same explicit
`1R1W` channel configuration, and this refactoring does not change the memory
layout, pipeline schedule, or measurements above.

### Phi-family sharding sweep

The scheduler plan can now partition one regular family among several physical
executors without changing the semantic topology. A member reference of the
form `{family, Id, {interleaved, Index, Count}}` selects row-major instances
whose linear index has the indicated residue. Plan normalization requires all
residues exactly once, rejects overlaps and incomplete partitions, and gives
each partition dense local state and mailbox slots. The default complete-family
form is unchanged.

Generated topology routing retains the semantic family address until the final
hop, then uses a static coordinate table to select both the owning scheduler
and its dense slot. Control broadcasts use the same table. Startup traffic is
filtered to the coordinates owned by each partition. This preserves the
bounded coordinate arithmetic described above: the sharded design contains no
runtime division or remainder by `WIDTH` or `HEIGHT`.

The D3 sweep leaves the two data and two syndrome families on one scheduler
each and assigns each of the X and Z phi families to one, two, or three
interleaved schedulers. Every row passes the complete CPU-versus-native-Icarus
comparison, agreeing on all 84 accepted corrections and all 18 final data-qubit
replies. The event order and number of intermediate status frames may differ,
as expected for another legal actor schedule.

| Phi schedulers per plane | Total schedulers | Application clocks | Mean clocks/step | Steps/s at 200 MHz | Clock for 1 MHz steps | Estimated logic cells | Flip-flops | LUTs | DSPs |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 6 | 13,320 | 576.9 | 346,700 | 576.9 MHz | 41,345 | 24,533 | 53,718 | 16 |
| 2 | 8 | 10,402 | 438.2 | 456,400 | 438.2 MHz | 49,328 | 33,890 | 67,020 | 32 |
| 3 | 10 | 9,695 | 400.5 | 499,400 | 400.5 MHz | 59,246 | 44,546 | 81,667 | 48 |

The area figures are out-of-context XC7 maps of the topology core embedded in
each generated gateway, excluding the gateway and external RAM macros. The
one-shard row exactly reproduces the 41,345-cell fixed-pipeline baseline above.
Two phi schedulers per plane improve completed-step throughput by 31.7% for
19.3% more cells, or about 10% better throughput per cell. A third improves
throughput by only another 9.4% while adding 20.1% more cells. By then each phi
scheduler is active for roughly 5,000 clocks and each unsharded syndrome
scheduler for roughly 4,600, so phi execution is no longer a singular
bottleneck.

The DSP count rises by 16 at each point because every added X/Z pair contains
two more phi relaxation datapaths. Wide shallow RAM packing is a second, less
visible cost: applying the isolated RAM maps above gives approximately 54, 74,
and 94 `RAMB36E1`-equivalents. Stored logical content is constant, but an
independently active phi shard still needs an eight-`RAMB36E1` state bank and a
two-`RAMB36E1` mailbox bank. Avoiding that fragmentation would require packed
or multipumped memories with enough effective ports to retain the parallelism.

The two-shard profile is therefore the useful candidate from this sweep, but
it is not yet the default. The next deployment choice should weigh its extra
DSP and BRAM use against timing closure. Further throughput work should first
profile a two-shard placed design, then consider balanced static partitions or
syndrome-family sharding once phi and syndrome utilization converge. The
current coordinate-to-shard match tables also made the three-shard DSLX-to-IR
conversion take 13 minutes 45 seconds; a compact generated ownership primitive
is a worthwhile compiler/code-generation cleanup before substantially larger
partition counts.

### Decoder-only throughput attribution

`phi_decoder_profile_topology` removes the two data-qubit and two full syndrome
families from the three-shard graph. Each phi cell still sends its ordinary
`phenom_request`; a compact request-paced source advances a deterministic PRNG
and returns the transition of a Boolean measurement bit as `phenom_anyon`.
This preserves the phi mailbox, actor, routing, and credit machinery while
removing the phenomenological neighborhood query and response protocol. The
source families have separate schedulers, so their RAM activity is not counted
as decoder activity.

The RTL bench requires one status from every coordinate on both planes for
every step zero through 32, rejects duplicates and malformed events, and
requires corrections on both planes. It observed 64 X and 62 Z corrections.
Between complete steps eight and 32, the graph took 4,048 clocks, or 168.67
clocks per decoder step. That projects to 1.186 million steps per second at
200 MHz, and equivalently needs about 168.7 MHz for a one-megahertz step rate.
The complete three-shard memory experiment took 400.5 clocks per step. The
one-result lookahead below shows that this gap cannot all be assigned to the
phenomenological source/data round trip: once that work overlaps phi, the
host-facing diagnostic streams expose a second bottleneck.

The exclusive VPI issue classification supports that interpretation. During
a repeated full closeout, the six phi schedulers launched a state read on
17.1% of their aggregate clocks. Another 14.6% had producer backpressure but
no issue, 68.4% had neither a state/RAM stall, egress stall, nor visible
producer backpressure, and no clock had a blocked state port or egress. The
decoder-only bench launched phi state reads on 38.5% of aggregate phi-shard
clocks. Its remaining bubbles include real protocol dependencies and the
two-stage same-actor exclusion, but they no longer prevent the target rate at
the assumed clock.

This diagnostic is intentionally not a replacement for the end-to-end golden
comparison: it supplies a different, deterministic syndrome stream and omits
correction feedback and the final data-frame query. Run it with the native XLS
toolchain as described below:

```sh
tools/run_phi_decoder_profile.sh
```

Because the real apparatus supplies syndromes externally, further work should
not optimize the phenomenological generator merely to improve this demo's
headline throughput. The paper-semantics audit below must be resolved before
the measured cadence is treated as a decoder-performance target.

### One-result phenomenological lookahead

The request-paced source previously began all four data queries only after its
paired phi actor requested the next step. The revised source computes step zero
at configuration and retains each completed result until the matching
`phenom_request` arrives. Consuming that request releases the retained
`phenom_anyon` and starts the four queries for the following step in one entry
batch. It can therefore overlap one physical-noise result with phi work, but it
cannot run two results ahead. Four data responses plus one early request still
fit the existing five-frame syndrome mailbox, and the completed result lives
in the unchanged actor-state word.

The complete three-shard CPU-versus-native-Icarus comparison still agrees on
all 84 corrections and all 18 final data replies. The cycle trace confirms the
intended overlap. Before the change, the complete step-`n+1` announcement set
reached the application boundary an average of 105.9 clocks after the last
step-`n` status; afterward it arrived an average of 37.3 clocks before that
status. Step zero also completed about 1,100 clocks earlier in this run. The
steady interval, however, changed only from 400.45 clocks over steps 0--22 to
399.57 clocks over steps 0--23.

That flat result is an output-bandwidth bound, not a failed lookahead. Every
step sends 18 diagnostic syndrome announcements, 18 required closeout status
frames, and on this witness an average of 84 / 22 correction frames. Each is a
five-beat routed frame, and the current gateway path accepts one output beat
every two clocks. The resulting lower bound is about 398.2 clocks per step,
which accounts for the observation. The new run keeps that link occupied while
the source and decoder work overlap behind it.

The gateway now terminates at a typed `RoutedFrame` channel. Its host-bound
serializer is compiled as a separate one-stage, II=1 unit, while the scheduler
core remains two-stage and II=2 for its synchronous 1R1W RAM contract. The
complete three-shard CPU-versus-native-Icarus witness again agrees on all 84
corrections and all 18 final data replies. With the diagnostic announcements
still present, steady cadence improved from 399.57 to 220.46 clocks per step,
or about 907 thousand steps per second at 200 MHz. The application output
reported no transmit stalls.

The visualization-only announcement copies have subsequently been removed
from the lossless application topology. This reduces the same witness from 942
frames and 4,713 observed beats to 507 frames and 2,535 beats, while retaining
the 84 corrections, 18 replies, and per-cell status reports. It does not
improve steady cadence: steps 8--21 average 221.69 clocks per step, or about
902 thousand steps per second at 200 MHz. The serializer therefore removed
the transport bound; the remaining rate is set by internal decoder/scheduler
work. The removed events are a natural future best-effort debug source, where
an absent observer cannot backpressure the application. The remaining status
traffic may eventually merit on-fabric aggregation, but that higher-complexity
work is deferred until bandwidth measurements require it. These rates are
cycle-count projections, not timing-closure results.

### Ready-selection attribution

The VPI bridge can now inspect the source-level readiness signals retained in
each generated `SharedService` next-state module. It samples them only when the
first pipeline stage completes, so the counters describe scheduler selection
opportunities rather than every physical clock. This is passive simulation
instrumentation: it adds no RTL ports, registers, or synthesized logic.

Each selection activation falls into exactly one bucket. `selectable` means at
least one ready slot does not conflict with the actor already in flight;
`same actor` means work is ready but the only eligible slot has that conflict;
`egress credit` means all pending work is waiting for the one admitted egress;
and `no actor work` means there is no mailbox candidate, phase-entry probe, or
egress waiter. `internal other` retains completeness for scheduler-specific
admission states not covered by those common cases. The profile also records
the number of ready, mailbox-candidate, entry-probe, and egress-waiter slots
seen across activations. Both maintained runners assert that the exclusive
buckets sum to the activation count for every scheduler.

A fresh full distance-three closeout, from the first application request to
the final output, covered 5,151 clocks and 2,575 selection activations per
scheduler. Aggregating the exclusive buckets by actor family gives:

| family | selectable | same actor | egress credit | no actor work |
|---|---:|---:|---:|---:|
| data | 41.9% | 14.9% | 12.2% | 31.0% |
| syndrome | 49.9% | 15.4% | 14.2% | 20.5% |
| phi | 61.2% | 20.2% | 5.1% | 13.6% |

The decoder-only run again measured 4,048 clocks for steps eight through 32,
or 168.67 clocks per step. Across its six phi schedulers, 77.1% of selection
activations were selectable, 18.0% were blocked only by the same-actor hazard,
3.4% waited for egress credit, and 1.5% had no actor work. State and mailbox
RAMs accepted every request, and their simultaneous read/write activity never
targeted the same row.

A temporal follow-up now revisits the excluded actor after its in-flight visit
retires. The original 18.0% is not evidence that one actor monopolizes a shard:
within each three-actor phi scheduler, per-slot state-read counts differ by only
3.5--6.2% of their mean. Selection is ready-aware round robin, and the observed
load is correspondingly balanced. The lone-ready periods instead arise because
neighbor messages arrive in causal bursts and a three-slot shard can drain the
other two queues before the current actor's next dependency arrives.

The follow-up also shows that the original ready bit was sometimes only a
conservative prediction. Of 3,058 same-actor samples, 1,966 (64.3%) still had a
mailbox candidate after retirement, 380 (12.4%) were waiting for the shared
egress credit, and 710 (23.2%) had no work left. Of the mailbox cases, 438
crossed a phase boundary. The narrow state-forwarding proposal--reuse the
outgoing machine only for a direct next mailbox dispatch--therefore applies to
1,528 samples: 50.0% of the apparent same-actor bubbles, or 9.0% of all
selection activations. Recovering every one would raise the selectable share
from 77.1% to at most 86.1%, roughly an 11.7% issue-rate gain before accounting
for new critical paths or downstream limits. This remains a useful local
optimization, but it is not itself the missing factor of two. Empty or causally
blocked work is material in the complete phenomenological fixture, but it is
not the first place to spend effort for a real apparatus which supplies
syndromes externally.

Run this profile natively with an arm64 XLS distribution:

```sh
ERL_HLS_XLS_ROOT=/path/to/xls-darwin-arm64 \
    tools/run_phi_decoder_profile.sh
```

The stage worker remains portable to Linux for CI or as a fallback, but the
development runner no longer copies work into the local UTM.

### Paper-semantics audit

The decoder now follows the parameters used by Herold et al. The paper
specifies an auxiliary `L x L x L` torus, with `c = 10 log^2(L)` parallel field
updates followed by one anyon update in each sequence, and reports
`eta = 1/2` for its numerical results.
See [Cellular-automaton decoders for topological quantum memories](https://arxiv.org/abs/1406.2338).

For `L = 3`, a two-element field vector represents the complete third
dimension without loss: reflection symmetry about the anyon plane makes the
`z = 1` and `z = -1` values equal. The center recurrence is therefore
`q + (6 phi0 + 2 phi1 + planar_sum) / 12`. A bulk representative has the
center value on one side and its reflected bulk counterpart on the other, so
its recurrence is `(phi0 + 7 phi1 + planar_sum) / 12`. Both paths retain the
existing single-round, nearest-Q15.16 rounding policy. A general odd `L`
implementation would need `(L + 1) / 2` stored depth classes under this
symmetry reduction.

The paper does not state an integer-rounding convention for `c` at very small
`L`; natural logarithms give approximately 12.1 at `L = 3`. The demonstration
explicitly rounds that prescription to twelve field updates. The deterministic
ERTS fixture now closes at step 18 with 80 accepted corrections and a
nonuniform final data measurement: eight commuting and ten anticommuting
qubits. Repeated ERTS runs produce the same summary.

This changes the throughput target substantially. A phi actor requires
`5c + 12 = 72` state visits per sequence. At `c = 12`, each existing
three-actor shard therefore needs at least 216 visits, and the II=2 selector
has a hard lower bound of 432 clocks per sequence before egress or causal
waits. A native RTL profile measured 12,172 clocks for steps eight through 32:
507.17 clocks per step, or about 394.3 thousand steps per second at 200 MHz.
The implementation is 17.4% above the visit-count floor.

The same run separates ingress pressure from actor execution. Across the six
phi schedulers, 40,458 state reads occupied 40,458 of 50,562 selection
activations. The exclusive selection buckets were 80.1% selectable, 16.2%
blocked only by the same-actor hazard, 3.3% waiting for egress credit, and 0.4%
without actor work. State and mailbox RAMs accepted every request.

Mailbox occupancy was sampled after retirement and the activation's one
admission. The schedulers averaged 3.48 queued messages spread over 2.12 of
their three actors, with a peak of eight or nine messages in an individual
scheduler. Producer holding slots retained an average of 0.43 non-credit
commands after admission and were nonempty on 38.7% of activations. The large
physical-cycle request-stall count--54,766 stalls beside 42,844 accepted
requests--mostly reflects valid inputs being held across the scheduler's
two-clock initiation interval; it does not indicate dropped work. There is
ample queued input, and only a modest post-admission backlog, while the actor
executor is busy whenever the same-actor rule permits it. This profile points
to increasing executor issue rate rather than changing the mailbox payload
layout.
### Decoupled actor executor

The actor-specific microstep is now a stateless `SharedExecutor` proc. The
mailbox manager reads a selected actor's state and message, marks that actor
in flight, and submits the complete activation to the executor. It may then
select another actor while XLS pipelines the first activation. Returned
results retire in order through the existing 1R1W state port; an in-flight
bit per actor prevents a stale reread of the same state. One result skid slot
allows the manager to continue collecting input and returned credit while an
effect-producing result waits to retire. This changes no mailbox capacity,
RAM port count, actor callback, or message-order rule.

The isolated phi executor compiles as a two-stage II=1 pipeline. Its
out-of-context XC7 map reports 1,477 estimated logic cells, 1,021 flip-flops,
2,349 LUTs, and eight `DSP48E1`s. A single pipelined executor per scheduler is
therefore sufficient to accept one distinct actor activation per clock; a
second physical actor datapath would not improve the present issue rate.

The paper-parameter decoder-only fixture now measures 6,792 clocks for steps
eight through 32, or 283.0 clocks per step. This is about 707 thousand steps
per second at 200 MHz and would require a 283 MHz clock for one million steps
per second. Relative to the II=2 result above, the decoupled executor removes
5,380 clocks, a 44.2% reduction. The complete CPU-versus-native-Icarus
closeout also agrees on all 80 accepted corrections and all 18 final data
replies; the latter remain nonuniform, with eight commuting and ten
anticommuting qubits.

The profile exposes a new dominant limiter. Across the six phi schedulers in
the decoder-only run, 33,904 actor reads occupied 60.2% of 56,298 selection
activations. Completed effect-producing results waited behind the scheduler's
single outstanding effect batch for 33.6% of activations; 5.0% had ready work
only for actors already in flight, and 1.2% had no actor work. The full noisy
closeout gives the same diagnosis: 29.0% effect-result blockage, 10.8%
in-flight-only work, and 2.1% no work. Neither state nor mailbox RAM reported
a request stall in either run.

An apples-to-apples XC7 topology-core map reports 81,195 estimated logic
cells, 81,239 flip-flops, 104,105 LUTs, and 48 `DSP48E1`s. The preceding
three-shard II=2 row was 59,246 cells, 44,546 flip-flops, and 81,667 LUTs. The
complete gateway map, which additionally includes the boundary and host-facing
machinery, reports 88,135 cells, 88,530 flip-flops, and 105,106 LUTs. The
substantial register increase comes from carrying loaded activations and full
result/effect values through the II=1 pipeline and its channel buffers. This
is a throughput-first prototype, not yet a favorable area point.

Changing the executor request and result channels from depth one to depth zero
preserved the simulated cycle count, but it created combinational ready loops
between `SharedService` and `SharedExecutor`; Yosys reports those loops during
flattening. The explicit channel registers are therefore part of the current
correct elastic boundary, rather than removable duplicate storage.

The first follow-up ablation therefore targeted post-handler admission rather
than mailbox payload fragments or another executor lane. A router keeps one
`EntryEffects` batch and returns its sole credit only after serializing the
whole batch. A bounded two-batch window appeared able to let the executor
retire another actor while the previous effects drained. Because the queue had
to remain ordered and its credit had to denote real storage, this was tested
at depth two before attempting to generalize the capacity.

### Rejected two-batch effect window

That depth-two ablation does not preserve the current progress argument. The
first implementation counted the batch retained by `SchedulerRouter` and the
existing depth-one `ScheduledEffects` channel as two outstanding slots. It
failed to complete decoder step eight within the 500,000-clock profile limit.
The router originally received a new batch and attempted its first downstream
send in one atomic activation, so a blocked first effect meant that the router
had not actually acquired the batch and the apparent second slot was not yet
real.

A second implementation separated router admission from effect delivery. It
first committed the incoming batch to router state, independently of the
first destination's readiness, and only then allowed the scheduler to occupy
the lookahead channel. This made both storage slots genuine but reached the
same 500,000-clock timeout. After a few hundred useful state reads, the
profiles showed no selectable actor work while inter-shard producer inputs
remained backpressured for the rest of the run.

The extra slot lets several schedulers commit another round of actor state and
effects without reserving space in the destination mailboxes. Eventually each
router can hold an ordered batch whose next effect targets a full producer
path, while the destination scheduler has its own completed effect result
waiting behind a full two-batch window. This is a cyclic backpressure wait,
not an insufficient router register. Increasing mailbox or channel depth
would only move the finite-buffer threshold and is not a general fix.

The ablation was therefore reverted before synthesis. It would have added
only one scheduler-state bit and reused an already-present wide channel, but
an area figure for a design which does not make progress would be misleading.
A future multi-batch design needs credits backed by end-to-end destination
reservations, or a routing discipline which provably breaks these wait cycles.
Until then the one-completed-batch rule remains part of the shared scheduler's
deadlock discipline rather than merely a throughput knob.

### Compact scheduled effects

The shared executor previously carried every entry action as a complete
`Egress`: an eight-bit output port and a 128-bit AXI frame, repeated to the
maximum action count. Most of those bits are static. For a given phase and
action index, the compiler already knows the output port, message selector,
and payload width. `EntryEffects` now carries the entered phase, the runtime
predicate for each action, and one packed vector containing only the actual
message payloads. The egress router reconstructs each complete frame as it
serializes the batch. This changes neither action order nor the existing
one-batch progress rule.

For `phi_halo_cell`, the effect record shrinks from 693 to 397 bits and the
complete executor result from 1,294 to 998 bits. The paper-parameter profile is
cycle-identical at 6,792 measured clocks, or 283 clocks per decoder step. A
fresh pair of out-of-context XC7 maps of that profile topology reports the
following controlled comparison:

| effect representation | estimated logic cells | flip-flops | LUT1-LUT6 | `DSP48E1` |
| --- | ---: | ---: | ---: | ---: |
| complete `Egress` array | 58,084 | 66,701 | 70,502 | 48 |
| packed dynamic payloads | 56,590 | 64,289 | 69,924 | 48 |

The compact form therefore removes 2,412 flip-flops (3.6%) and 1,494
estimated logic cells (2.6%) without changing throughput. The smaller result
also makes a future, progress-safe multi-batch window less expensive, but it
does not itself supply the destination reservations that such a window needs.
