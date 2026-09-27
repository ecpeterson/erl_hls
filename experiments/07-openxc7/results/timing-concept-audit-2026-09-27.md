# What the timing paths compute

This analysis uses the selective two-stage executor from [PR #181's measurements](timing-feedback-2026-09-27.md). It adds no compilation or routing result. The [evidence](timing-concept-audit-2026-09-27.json) pins report members, path cuts and the mapped DSP census.

## Arithmetic is not mostly wiring

| Saved worst path, Default placement | Cell delay, ns | Interconnect, ns | Setup period, ns |
|---|---:|---:|---:|
| DSP → mailbox | 8.584 | 6.221 | 15.151 |
| State RAM → executor | 10.194 | 4.880 | 15.144 |
| Scheduler → reduction enable | 1.653 | 12.729 | 14.904 |

Cell delay includes RAM/DSP clock-to-output where applicable. Setup/skew adjustments explain the difference between data-path sums and period. The native route's roughly 92% wiring fraction must not be substituted for these vendor arithmetic paths.

The expensive arithmetic is exact rounded division by twelve in `phi_field`, implemented by `hls_fixed::round_ratio` as a signed 37×39-bit reciprocal product. Yosys maps each product to six DSPs plus fabric addition; three DSPs lie in series on the reported paths. In the DSP-launched path, their cell arcs alone total **6.135 ns**, before fabric partial-product addition, rounding and publication. Thus even removing every routing delay would not make this mapped computation fit a 5 ns stage.

Reviewed cuts on that path give:

| Sequential portion of one combinational path | Data delay, ns |
|---|---:|
| Reciprocal product: DSP cascade and fabric partial-product addition | 7.605 |
| Rounding and callback-result selection | 3.527 |
| Effect packing and executor-result receive | 0.769 |
| Publication through destination-mailbox input | 2.904 |

These are contiguous portions of one saved route, not independently timed components. The last portion is not yet attributed to individual publication/admission operations. The RAM-launched path spends 3.104 ns on RAM launch/response selection, 4.240 ns on operand selection and weighted-numerator preparation, and 7.731 ns on the reciprocal product. Arc rounding accounts for a 0.001 ns difference from the reported total.

## Duplicated completion datapaths

`shared_execute` selects between `shared_machine_complete(machine)` and `shared_machine_aggregate(...)`. The latter validates/applies the incoming aggregate and then invokes `shared_machine_complete` again. Inlining produces two copies of each field recurrence, although only one completion source is selected for an activation.

This survives both optimization and mapping: each executor has four reciprocal multipliers, two center and two bulk. Two executor instances therefore use **48 DSPs for reciprocal products**, out of 56 DSPs total. The remaining eight implement four unsigned 31×3-bit products. Source stacks distinguish the two completion call sites; this is not an inference from DSP count alone.

Selecting the completion input before calling the shared callback is an erl_hls lowering experiment. It can share combinational hardware without serializing two actors. Input-selection delay and altered placement can still worsen timing; the previous factored-arithmetic experiment already showed that fewer DSPs alone do not establish a speedup.

## Optimization ownership and missing analysis

Receive zeroing originates in XLS's `CloneNodesIntoBlockHandler::HandleReceive`. The current codegen pipeline performs basic simplification after adding flow control, but does not run the stronger conditional-specialization pass there. XLS has predicate-dominator analysis, currently focused on select arms. Proving payload irrelevance under register enables, sends, RAM enables and later valid state may need more than enabling an existing pass. A general correction belongs in XLS codegen/block optimization; erl_hls can make validity relationships explicit and provide minimal reproductions. Global `gate_recvs=false` changes the receive contract and is not a valid general fix.

The immediate analysis gap was interpretation: the retained reports already distinguish substantial multiplier cost from routing-dominated control, and source stacks expose callback duplication. The remaining reporting work is to join physical paths to **storage → dispatch → numerical operation → commit → publication** and join those boundaries to simulated per-round feedback latency. An XLS stage or proc name is not necessarily a physical boundary when its channels bypass storage. Retain unknown attribution explicitly and price proposed registered cuts against the actual 2×4 workload.

The [revised experiment order](../yap/timing-next-cones.md#architecture-first-revision) prioritizes input normalization and an independently staged numerical path over isolated gate changes.
