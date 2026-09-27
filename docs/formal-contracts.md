# Formal contracts

Model a component as a state machine with transition `T(s, input)` and observable events. A channel event occurs when valid and ready are both true. State the contract before optimizing the implementation.

## Safety and refinement

A legal-state invariant `I` needs two obligations:

- **Initialization:** reset establishes `I`.
- **Preservation:** for every state and input, `I(s) ∧ A(s, input) ⇒ I(T(s, input))`, where `A` contains explicit environment assumptions.

Together these establish `I` for arbitrarily long executions satisfying `A`. Assuming the desired result as part of `A` does not prove it. When components are connected, their guarantees must discharge each other's assumptions.

For an implementation change, define a relation to the specification. With unchanged latency, compare outputs and next state on every legal transition. With added buffering or retiming, relate queued/in-flight messages and compare accepted message histories; internal cycles may differ. Equality of dead payload bits is unnecessary unless the interface exposes them.

A mailbox's abstract state is its ordered live messages and postponement flags. Physical slot numbers represent that sequence; they are not the sequence itself. Occupancy is bounded, live slots are distinct, unused slots have no postponement flag, and consumption removes the selected logical element. Separately, the scheduler must prevent reuse or modification of a slot while its transaction is in flight. Metadata invariants alone do not establish RAM payload correctness.

Design around a single owner for mutable state and explicit reservations for future results. For each bounded resource, define disjoint categories satisfying `free + queued + reserved = capacity`; state exactly when ownership transfers. These rules make local proofs tractable. They become guarantees only when implementations preserve them and composition discharges the assumptions.

## Progress

Safety does not imply progress. State what eventually happens and under which fairness assumptions. A continuously pending round-robin contender can be assigned a decreasing rank after each accepted competing grant. This bounds intervening grants; it cannot bound wall-clock time when a receiver may stall forever. Local queue proofs do not establish network or application deadlock freedom.

## Evidence labels

| Evidence | Claim it supports |
|---|---|
| Simulation witness | The exercised inputs/histories pass. |
| Bounded formal check | Every admitted history up to the stated cycle bound passes. |
| Combinational proof | Every admitted input valuation of the stated finite-width circuit satisfies the proposition. |
| Inductive proof | Initialization and arbitrary-state preservation establish a property for all execution lengths, under stated assumptions. |

Always report parameters, assumptions, property, method, verdict and exclusions. Several parameter instances are several theorems, not a proof for every possible width. Retain source/tool identities and solver logs; use a reachable witness or a deliberately broken implementation to check that assumptions have not made success vacuous.

`tools/test_mailbox_formal.py` checks exact selection and inductive metadata transitions at explicit actor/depth configurations. `tools/test_shared_completion.py` proves complete combinational result equivalence for its generated reduction fixture. `tools/test_actor_snapshot_formal.py` checks eight-cycle equivalence; it is bounded. The full application simulations remain witnesses.

These checks trust the specifications, assumptions, compiler/Yosys translations and solver. They do not prove the compiler, numerical application model, analog behavior or timing closure. SAT/SMT can discharge finite-state obligations; [Yosys induction strategies](https://yosyshq.readthedocs.io/projects/eqy/en/latest/strategies.html) also support sequential equivalence. Parameter-generic claims need separate mathematical proofs; the finite-width checks do not supply them.
