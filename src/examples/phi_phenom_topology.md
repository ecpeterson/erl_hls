# Generated phi/noise topology

This deliberately small fixture connects one phi cell, one phenomenological
syndrome cell, and one phenomenological data cell. Its sources are split by
responsibility:

- `phi_phenom_topology.erl` declares actors, exact routes, startup messages,
  and the observable output as ordinary Erlang data.
- `phi_phenom_topology_dslx.erl` declares temporary physical choices for this
  executable fixture.
- `phi_phenom_topology.x` is generated and checked in as a golden artifact.

Actors exchange complete `axis::Frame` values through depth-one network
queues. Startup prefixes configure the two noise actors before their first
routed input. The syndrome announcement uses queued fanout: the actor send
completes at a common egress queue, after which a lossless distributor waits
for both the phi and observation branches. Each actor ingress ends at one
mailbox-admission gate.

The temporary startup-quiescence check evaluates the configured actors'
initial callbacks in the build VM. These fixture actors are trusted and
deterministic; emitted initial-effect summaries should replace that check.

The one-instance periodic topology makes four output ports of each actor
converge on one destination. The current binary mux trees preserve FIFO order
within each port but not aggregate same-sender order across those ports. The
physical profile therefore says `aliased_port_order => may_reorder`; the
generator derives and prints the three affected lanes. This is an explicit
fixture limitation, not a general Erlang ordering implementation. Aliased
external outputs remain unsupported.

Logical actor IDs may be tuple-indexed values such as `{phi, X, Y}`; generated
channel names use canonical numeric instance indexes. In this exact backend,
external IDs also become DSLX port names and must therefore be DSLX
identifiers.

The generated-RTL regression runs consecutive decoder steps, stalls the
observation port, checks that a complete frame remains stable, then verifies
that the graph continues. The shared actor codebook is validated, but
route-interface compatibility is still an explicit unchecked profile
assumption pending emitted actor interface summaries.

This generator consumes an exact heterogeneous graph, so its proc and channel
instances are explicit. A later parametric-family backend should retain regular
structure and use DSLX channel arrays and elaboration-time loop constructs
rather than flatten a large grid globally.
