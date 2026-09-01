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
effect list, so the phi actors' five-slot flipping sequences do not depend on
incidental mux-tree buffering before they can complete.

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
    Coordinator["ERTS runner +<br/>phi_memory_experiment"]
    Gateway["future PL-PS adapter"]

    Coordinator -->|"ordered commands"| Gateway
    Gateway -->|"one SpatialFrame stream"| CR["control_router<br/>only application ingress"]
    Gateway -->|"decoded events"| Coordinator

    subgraph Fabric["generated one-fabric topology"]
        PX["phi_x"] -->|"cardinal torus"| PX
        PZ["phi_z"] -->|"cardinal torus"| PZ

        PX -->|"request"| SX["syndrome_x"]
        SX -->|"announcement"| PX
        PZ -->|"request"| SZ["syndrome_z"]
        SZ -->|"announcement"| PZ

        SX <-->|"queries / replies"| DE["data_even"]
        SX <-->|"queries / replies"| DO["data_odd"]
        SZ <-->|"queries / replies"| DE
        SZ <-->|"queries / replies"| DO

        SX -->|"diagnostic copy"| XO["x_announcements"] --> Gateway
        SZ -->|"diagnostic copy"| ZO["z_announcements"] --> Gateway
        PX -->|"correction + post-move status"| XE["x_decoder_events"] --> Gateway
        PZ -->|"correction + post-move status"| ZE["z_decoder_events"] --> Gateway
        DE -->|"Pauli reply"| DM["data_measurements"] --> Gateway
        DO -->|"Pauli reply"| DM

        CR -->|"whole grid: noise_cutoff"| DE
        CR -->|"whole grid: noise_cutoff"| DO
        CR -->|"whole grid: noise_cutoff"| SX
        CR -->|"whole grid: noise_cutoff"| SZ
        CR -->|"point: pauli_update<br/>line: pauli_query"| DE
        CR -->|"point: pauli_update<br/>line: pauli_query"| DO
    end

    XE -. "map each correction<br/>to a point update" .-> Coordinator
    ZE -. "map each correction<br/>to a point update" .-> Coordinator
    XE -. "complete quiet + empty<br/>same-step X status" .-> Coordinator
    ZE -. "complete quiet + empty<br/>same-step Z status" .-> Coordinator
    DM -. "XOR Distance replies" .-> Coordinator
```

At the default distance three, the plan has 54 actor instances, 34 compact
route relations, and 54 explicit startup messages: one for every actor. The
route-rule count is independent of distance; only the family bounds and startup
entries grow. PRNG seeds are deterministic, distinct, and nonzero across all
six families. The noise seeds are deliberately mixed so the first
distance-three syndrome plane is not spatially uniform.

Each syndrome announcement carries its `{X, Y}` coordinate; the external port
identifies the X or Z plane. Announcements are diagnostic and do not close an
experiment. They are nevertheless lossless branches of the syndrome-to-phi
fanout, so a runner must drain both streams continuously or it will stall the
decoder. Each phi cell retains that coordinate and may emit one
`phi_correction` after its four anyon-move actions for the step, followed by a
`phi_status` reporting occupancy and propagated noise-quiet state. Correction
and status share one plane boundary, which preserves each source cell's order
while leaving cross-cell merge order unspecified. The plane, syndrome
coordinate, and selected direction together identify the neighboring data-
qubit edge; the single event stream does not mean that a phi cell is associated
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
Pauli measurement. The reply carries a request ID, physical data coordinate,
and parity bit. Both data families share one fairly merged output; request IDs
and coordinates make its unspecified cross-family order irrelevant.

These `external` endpoints currently become output channels on the generated
DSLX `Top` proc. The RTL benches consume them directly. They are not yet wired
to `hls_fabric`, a PL-PS frame adapter, or an ERTS process; a deployment must
make that gateway and correction-application policy explicit.

The one application ingress is the externally addressed `control_router`
service. Its envelope contains an ordinary actor frame plus an internal target
and inclusive rectangle. `noise` selects all noise actors, while `data`
selects data actors for Pauli queries or correction updates. Coordinates name
stable logical services, like registered process names, rather than actor
incarnations; one broadcast may therefore straddle lifecycle churn. The
present whole-topology reset flushes router and actor traffic together.
Independent restart will need lifecycle-owned flushing or generation checks at
the leaves.

The current physical lowering uses one lossless, statically unrolled
distributor per family. It finishes the selected family sends before accepting
another envelope, but top-level router acceptance is bounded network admission,
not simultaneous actor-mailbox admission. The raw channel assumes that its
eventual gateway has validated rectangle bounds and target/schema combinations;
frame lengths and constrained field values are part of that check. Pauli
updates are at-most-once, and retry will require an explicit duplicate policy.
`hls_spatial_router.x` also defines tested pair, quadrant, and leaf building
blocks for a later generated tree inside one fabric. Neither implementation
defines how a global rectangle is partitioned, addressed, or retried across
multiple FPGAs. A multi-FPGA adapter must intersect the rectangle with each
local partition and re-originate explicitly addressed per-fabric commands;
partial delivery and failure semantics remain unresolved.

`phi_memory_experiment` is the example-local, pure ERTS reducer for closing one
memory experiment. It first sends a whole-grid cutoff. Every data reply then
propagates its persistent quiet bit through the syndrome announcement and phi
status. The reducer translates each sparse correction into a point-addressed
`pauli_update` immediately. A complete same-step status set from both decoder
planes closes the decoder only when every coordinate is quiet and empty.
Because each cell's status follows its optional correction on the same ordered
plane output, the two complete sets also fence all earlier correction events.
The reducer then issues one horizontal-line `pauli_query` after the queued
point updates and XORs the `Distance` replies. This is a sound completion
witness, not a liveness guarantee: the current fixed-round decoder can leave
symmetric nonempty anyon configurations stationary. Until its tie-breaking or
stopping rule is strengthened, the ERTS runner must bound the closeout wait and
report nonconvergence rather than inferring completion from elapsed time. This
first protocol assumes one lossless, non-restarting fabric activation; a reset
or gateway failure aborts the experiment rather than invoking unspecified
retry behavior.

The present noise configuration is still a plumbing fixture. Its common high
threshold deliberately produces frequent binary events rather than modeling a
full Pauli channel. The explicit startup list also caps this example at
distance 50; the compact route representation itself has no such bound. A
PL/host adapter must still transport the reducer's ordered commands and each
source's ordered decoded events. A physically calibrated noise model remains
later decoder work.

### Distance-three synthesis progression

The last out-of-context XC7 mapping progression, before the Pauli snapshot
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

### Distance-three RTL simulation

`tools/run_phi_noise_topology_sim.sh` is the opt-in full-graph regression. It
regenerates the distance-three DSLX, runs XLS conversion, optimization, and
Verilog generation on the configured build host, then compiles and runs
`phi_noise_topology_tb.sv` with Icarus. The cost is deliberately excluded from
the routine CI job.

The distance-three bench holds one announcement stream under backpressure,
checks that its frame remains stable, and otherwise continuously drains every
output. It accepts announcements in arbitrary merge order and requires every
coordinate from both planes in steps zero through two, proving that steps zero
and one completed everywhere. The current deterministic fixture also produces
sparse corrections; the bench compares those as coordinate/direction sets
rather than as one globally ordered trace. It also requires a complete status
set after each checked step. Those sets are regression goldens for this
fixture, not a logical-correctness or winding test.

The same bench drives `control_router` over the nondegenerate physical
coordinate space. It broadcasts a future cutoff over the full 3-by-6 data
grid, requires all 18 phi cells to report quiet in that exact step, queries the
three data qubits on physical row four, applies one point-addressed X update,
and queries the row again. The XOR of the three Z-anticommutation replies must
toggle. This verifies rectangular target embedding and the correction/query
path in the synthesized D3 network; it deliberately does not wait for empty
decoder planes or claim a logical-correctness result.

The routine distance-one smoke bench does drive `control_router`. It sends one
whole-fabric cutoff, waits for propagated quiet status, queries one data line,
applies one point-addressed X update, and observes the corresponding
anticommutation change on a second query. Distance one aliases decoder routes,
so this smoke test exercises control plumbing rather than the nondegenerate
drain criterion.

On the 4-core, 8-GiB UTM using the pinned XLS build, the saturated
fixed-point-field run measured about 23 seconds and 302 MiB for DSLX conversion,
6 minutes 22 seconds and 3.18 GiB for optimization, 1 minute 10 seconds and 286
MiB for code generation, 27 seconds and 469 MiB for Icarus compilation, and 2
minutes 8 seconds and 149 MiB for simulation. The generated Verilog is about
8.5 MiB and 148,292 lines. These are host build costs, not an FPGA utilization
estimate;
the runner saves compact timing and digest reports but does not copy that
Verilog into the repository.
