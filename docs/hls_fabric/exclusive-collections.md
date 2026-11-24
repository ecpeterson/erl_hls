# Exclusive epoch collections

A materialized scheduler group may set `admission_reductions => exclusive_epoch` to fold contributions before their actor opens a reduction. The actor still opens the collection, supplies its key, membership and initial value, and consumes its result through the ordinary reduction-completion callback. Ordinary actor lowering remains the reference semantics.

This option is an **unchecked protocol assertion**, with a compiler warning. It requires:

- One member-based collection site with a commutative monoid and contribution expressions independent of actor state.
- Exclusive ownership of its contribution message tags. Those messages must have no ordinary callback meaning beyond contributing or waiting for that collection.
- Exactly one contribution per selected member, with one common key. Early arrivals must match the key and membership eventually supplied by the actor.
- No interleaving of different keys while a collection is incomplete. A complete but unconsumed collection still owns its bank; a successor waits in its producer input until release. A sheet identifier is insufficient if several collections occur within one sheet.

Only the first requirement's source shape is checked statically. The compiler does not establish the other protocol properties or the monoid laws. In particular, a closed topology alone does not establish them.

The collector accepts early inputs and inputs received while a callback is in flight. Opening validates accumulated identities and combines the partial result with the actor's initial value. There is no contribution fallback to the ordinary mailbox. Ordinary dispatch omits collector-owned clauses and rejects a contribution that bypasses its collector; tag identities and wire encodings remain unchanged. Detectable violations—including duplicate/foreign members, incompatible keys and malformed reserved frames—fail the owning actor with `REDUCTION_PROTOCOL`. A reducer failure instead retains the selected collection's outstanding obligations and is delivered at completion. Missing opens or contributions can still wait forever; a replay after the bank has been released is not generally distinguishable from a new collection.

Debug queries use live collector metadata rather than the older actor RAM snapshot. The `early` status identifies input awaiting an open, with arrived identities where the query has room; selected membership and the missing-member count are still unknown. After opening, expected and seen masks identify missing members. Completion consumption requests release of storage. An effect caused by that consumption may become visible before release completes; a successor contribution waits for release. The ordinary output reservations and backpressure rules still apply.

## Dedicated actors

For a dedicated `hls_statem` actor, set `direct_collections => #{Module => exclusive_epoch}` in the topology profile. All instances of that module must use dedicated execution. Generate actor artifacts with the returned `artifact_requirements`; standalone generation uses `direct_collection => exclusive_epoch`. Retained calls and internal-event continuations are not supported by this option.

The same exclusivity and epoch obligations apply. Contributions bypass the ordinary mailbox, with bounded storage per producer and fair selection of one contribution per activation. Ordinary messages retain their mailbox and per-producer order; a preceding ordinary message can hold up that producer's later contribution. Startup contains ordinary initialization messages; reserved contribution tags there are rejected at compilation. Startup precedes ordinary routed traffic, while routed contributions may accumulate early. Backpressure can stall the actor and collector together.

Pass the same `direct_collections` map to `xls_scheduler_debug:projection/4`. Live observations distinguish early, open and complete collections using the existing query interface; mailbox depth counts ordinary messages, not held producer inputs or contributions already folded. Reset clears all three kinds of storage together.

Failures are not transactions: opening validation follows the callback that requests it, and effects committed before a conflict is discovered remain visible. A detected protocol fault stops further collection/publication; a failed reducer still drains its required participants before reporting failure through the actor.

## Ownership boundaries

`CollectionBank` is the value passed through the common transition: key, seen members, partial value and failure obligations. A shared service persists that bank in `CollectionContext`, alongside the phase and entry-pending metadata needed for validation and debug. It contains no copy of actor application data. A dedicated service retains its bank directly. `CollectionOwners` separates initialization, opening and consumption ownership. A registered `CollectionCommand` transfers opens and releases from retirement to the collector.

Shared and dedicated collectors use the same pure input-fold transition. Their arbitration and backpressure remain separate: a shared engine selects among actor slots, while a dedicated engine serves one actor. Debug observations read the bank that currently owns collection progress. The columnar ownership layout intentionally avoids imposing a wide indexed record update on every flag change.

See [building](building.md) for the umbrella APIs and complete decoder configuration.
