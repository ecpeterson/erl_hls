# Coalesced scalar states in passive interpretation

The retained N2 Phi numerical-rebalance recordings exposed a missing observer binding: optimized XLS IR kept six one-bit startup states with initial value zero and the same unconditional next value one, while codegen emitted one RTL register. The missing five leaves made otherwise recorded numerical updates appear to have unresolved predicates.

The dependency planner now admits an absent scalar state-read through a unique observed representative only when one proc gives both states equal widths, equal literal initial values, and the same sole next-value expression and predicate. Their equality follows inductively over the proc's common transitions and holds. This is a source-IR argument with XLS codegen as a trust boundary; it is not a proof of native equivalence, and sampled value equality is never sufficient. Native register declarations remain bound independently so alias leaves cannot make an emitted register's own update ambiguous.

Zero or multiple observed representatives, different initial values/updates/predicates/widths, multiple updates or procs, and unsupported initializer syntax leave the missing state unresolved. Capture interpretation still checks every known enabled D result against the recorded RTL D before attaching its operational inputs. The alias change supplies no new activity samples, native paths, clock estimates or gate-sensitization claims.

A before/after observation-plan comparison retains every source/IR/RTL digest, signal declaration, register, actor, state layout, dependency node and original binding; only five previously absent dependency leaves are added in each retained Phi variant. A fresh observation digest distinguishes that corrected interpretation. The physical catalogue keeps its original observation identity, with the explicit plan comparison supplying the correspondence to the new interpretation.

- [x] Finish local module tests, contracts and type analysis.
- [x] Verify matched unblocked and blocked numerical corridors in both retained recordings, including independently checked stage writes and publication payloads.

Local qualification passed 21 focused dependency tests, strict contracts for both changed modules, and observer-application Dialyzer using retained dependency context. The final formatted/parser code reconstructs exactly the plans used for the fresh interpretations. The retained baseline checks all 7,637 enabled D values; the scoped candidate checks 8,121 of 8,129, retaining eight unresolvable boundary-register writes as unknown. Every selected numerical/private/commit/outbox write is checked. Matched actors 2 and 3 at cycles 1777–1782 and actor 2 under stalls at cycles 1860–1867 have connected recorded numerical corridors.

The blocked baseline corridor also contains four writes to the link-6 ordering matrix. Their private-word input masks do not overlap the Phi field; they are control ancestry admitted by whole-word events, not private numerical copies. Both variants hold their primary intermediate values during the stall. Corridor event counts therefore do not measure numerical complexity or performance.
