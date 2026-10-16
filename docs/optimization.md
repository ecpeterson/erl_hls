# Reviewing optimization and architectural changes

Use this review when changing the programming model, compiler representation or physical execution of an actor. Application contracts remain authoritative; see [actor compilation](actor-compilation.md) and [formal refinement](formal-contracts.md). The review records a hypothesis and its limits, not a guarantee of improvement or a new approval requirement. Scale its detail to the change; keep experiment-specific evidence in the artifact archive and working plans in `yap/`.

## Objective and coverage

State the end-to-end objective, workload and cumulative resource budget. For a synchronous step with mean cycle count `C` and period `T`, step time is `C × T`; changing recurrence changes the period required to meet the same step-time target. More cycles can buy routing relief. Fewer cycles are neither a prerequisite nor independent evidence of better routing.

Examine the population of competing bottlenecks at the candidate's required performance, with an explicit margin. Report counts, shared structures and untouched competitors, not only the current worst few paths. Distinguish endpoints from independent chains. Use consistent scopes and fixed thresholds across revisions; counts within each revision's own worst-relative band answer a different question.

A calculation which removes delay from selected paths in an unchanged layout is a sensitivity bound. It omits replacement paths, placement changes and resource interactions. Recompute the coverage argument after any change to cycles, sharing or storage; evaluate combinations rather than adding isolated gains.

## Semantics, representation and ownership

For each long dependency, identify which layer creates it:

| Layer | Question |
| --- | --- |
| Observable contract | Which event order, atomic observation or failure behavior must remain? |
| Compiler representation | Does a whole-state value, generic dispatch or shared result bundle introduce coupling beyond that contract? |
| Physical protocol | Which component owns each field, port, reservation and future result, and when does ownership transfer? |
| Placement and transport | Where must values and decisions travel, at what width, fanout and rate? |

Logical atomicity does not imply one-cycle computation, one physical state bank or simultaneous movement of every field. Conversely, a narrower helper or registered identifier can still control a wide remote multiplexer. Describe the communication removed, localized or bounded by the proposed architecture, including the surviving data selection and return path.

For each new boundary, enumerate all producers of payload, validity, selection, failure, ownership, credit, commit, forwarding, write/receive enables and debug observations. Record normal, blocked, failure and reset schedules, port conflicts, in-flight capacity, recurrence and achievable overlap. A check excluding selected source names does not bound the entire replacement cone. Maintain a single authority for mutable state; charge replication, cancellation and reconciliation explicitly.

Prefer compiler-derived facts where possible. If independent state ownership, ordering domains or protocol phases cannot be inferred, an explicit checked source contract may be appropriate. Distinguish a new semantic option from an implementation of existing semantics; provide a CPU/reference meaning for either. Do not silently weaken message order, visibility, failure precedence or bounded-storage behavior to obtain a timing improvement. Unproven application assertions remain assumptions.

When repeated transformations expose the same synchronization requirement, review the programming model or execution interface before rewriting the chain again. Failure reporting, selection, publication and debug are examples of potentially coupled responsibilities, not presumed universal causes.

## Evidence and metric meanings

Keep three obligations separate: observable semantic refinement, survival of the intended dependency change through lowering/mapping, and physical performance. Functional witnesses do not prove an arbitrary-history property; correct IR cuts do not prove locality. Document test horizons and assumptions using the [evidence labels](formal-contracts.md#evidence-labels).

| Measurement | Meaning and limit |
| --- | --- |
| Logic depth / cell delay | Combinational computation on a reported path; excludes interconnect cost. |
| Routed data-wire delay | Modeled delay of that path's routed connections; includes routing structure and loading, not just geometric distance. |
| Horizontal / vertical routing utilization | Tool-reported use of east–west / north–south routing resources in the configured layout; no workload-time or activity factor. |
| Local congestion | Regional routing demand relative to available resources; a global average can hide a hotspot. |
| Placement bounding box | Dispersion of selected cells; not occupied area, wire length or delay. |
| Critical wire delay × actual cycles | A cycle-weighted critical-path proxy; not a sum over all nets or live information. |
| Installed FF count × step time | Installed storage-capacity/time proxy; not measured live-bit occupancy. |

AMD describes [directional routing resources and congestion](https://docs.amd.com/r/en-US/ug949-vivado-design-methodology/Congestion-Area-and-Level-Definition) and distinguishes [design-wide and local router diagnostics](https://docs.amd.com/r/en-US/ug904-vivado-implementation/Router-Messaging). Keep report stage, device and tool version fixed for comparisons. Do not infer an exact wire-length change from a utilization percentage; the cited summaries do not specify an interchangeable physical-length weighting.

Compare full path delay, spatial dispersion, fanout/load, packing and regional routing pressure as well as area. Identify whether compared paths have corresponding endpoints or are different maxima from one semantic family. Even low-fanout connections can be long. Less area can accompany worse connectivity, and compact placement can itself cause pin congestion. A single placement does not isolate an edit's causal effect or establish a device timing floor.

## Experiment record and decision

Use a compact record with these fields:

- Observable behavior and end-to-end objective, including actual-cycle target and resource ceilings.
- Baseline bottleneck population, shared structures, margin and excluded cases.
- Before/after dependencies, owners, communication and recurrence/overlap schedule.
- Semantic obligations, compiler checks and expected physical mechanism; distinguish observations from predictions.
- Bounded measurement scope, source/tool identities, stop conditions, comparison and retained failures.

Proceed to bounded physical measurement when qualified evidence makes the hypothesis credible; do not require a perfect predictor. Preserve the best measured design. After a negative result, identify whether semantics, lowering, replacement dependencies or physical realization defeated the hypothesis. Reuse local improvements only when their combination demonstrates a benefit; a rejected combination does not prove its whole architectural family impossible.
