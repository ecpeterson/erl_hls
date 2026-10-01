# Specializing actor state

A fixed topology can establish that some actor fields have one value in each reachable phase. Shared schedulers can omit those fields from RAM and executor messages, reconstructing them from the actor identity and phase. Callbacks, message checks, effects and logical actor identities retain their ordinary behavior.

Set `specialize_state => true` in every scheduler group sharing the actor module. The compiler derives constants from current actor source, typed startup messages and the schemas emitted by internal producers. Entry callbacks and internal events participate in the analysis. Unknown expressions and legal values changed by codec normalization discard facts; incomplete analysis retains full storage. A raw external ingress permits every declared schema, regardless of its advertised schema list. This does not assume foreign frames are filtered upstream.

The current option supports exact `hls_statem` actors without retained calls. Actor-owned reductions retain their full private storage; completion callbacks participate in the data analysis with unconstrained internal-event values. Families and route relations are rejected when specialization is requested. Groups of one module use a common field layout; mixed opt-in keeps the full representation. No executor is duplicated per actor.

The scheduler debug projection includes the logical fields, physical offsets and per-instance/slot/phase constant table. Phase, failure and mailbox queries retain their meaning; their physical offsets follow the compact layout. Artifact requirements carry the captured source options; validation rejects a table derived from different source. Regenerate topology, actor artifacts, RAM bindings and the debug projection together.

This is a storage optimization. It neither removes protocol checks nor establishes contribution uniqueness, epoch validity, commutativity or fixed collection membership. Membership changed by ordinary callbacks remains mutable. Compare complete RTL behavior and native area/timing before selecting it for a deployment: reconstructing constants introduces selection logic.
