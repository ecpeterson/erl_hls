# Indexed collections

An `hls_statem` gather retains one typed value per selected member and delivers the complete set in member order. Unlike a reduction, it does not combine values as they arrive. The source API fixes a maximum capacity, captures a membership mask and key at opening, and supplies padding for inactive members. Member zero occupies list position one. Empty membership completes after the opening entry commits.

Set `gather_collection => true` on a materialized scheduler group to receive these contributions in separate storage. Generate actor artifacts from the topology's `artifact_requirements`; standalone shared-actor generation accepts the same option. Ordinary lowering remains available without this placement option. The initial placement supports one numeric-member gather site per actor module and message-only value construction.

Reserved gather messages must arrive through routed inputs; topology startup lists may contain only ordinary configuration messages.

The placement requires these protocol assertions:

- Gather message tags have no ordinary mailbox meaning.
- For a given key, source eligibility is uniform across contributions apart from member checks.
- At most two collection keys need storage at once. A key must identify the collection, not merely a sheet containing several collections.
- Reset flushes the scheduler, pending inputs and borrowed completion requests together. A stale completion cannot survive a full generation-counter wrap.

These properties are not yet verified by the compiler; generation emits a warning. Source phase guards still decide whether a provisional key is eligible. Opening validates stored membership before completion becomes visible. Detected duplicates, foreign members and invalid keys fail the actor, potentially before ordinary mailbox dispatch would inspect them; missing members can wait indefinitely. This is not a general deadlock-freedom guarantee for shared producer routes.

Accepted values have one authoritative store. Reserved contributions never fall back into the ordinary mailbox. A completed view remains immutable until its consuming activation retires, including output stalls. That activation may open an independent scalar reduction without overwriting the borrowed values. User callbacks should retain derived state, rather than copying the entire completed snapshot back into actor data.

Live observations describe progress and ownership; they do not expose a second copy of the payload. See the [implementation and verification plan](../../yap/hls_fabric/topology-specialization.md) for the remaining protocol-checking work.
