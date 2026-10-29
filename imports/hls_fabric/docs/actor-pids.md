# Scheduled actor PIDs

A topology deployment exposes one external Erlang PID per scheduled logical actor. It uses the normalized `hls_topology` plan, `hls_scheduler_plan` placement, and generated actor codecs. A family coordinate is a logical identity; it is not necessarily the actor's row-major physical slot. Interleaved scheduler groups are supported by the descriptor.

The deployment constructor accepts `Plan`, scheduler specifications and a map from scheduler group ID to physical application endpoint. Every actor must belong to a scheduler group. Missing, extra, duplicate or out-of-range endpoint bindings are rejected. Standalone service and topology declarations can coexist in one node, but their physical endpoints must not overlap on the same application/debug stream.

The constructor describes a deployment; it does not synthesize an ingress connection for an arbitrary graph. The current executable gateway is the four-actor fixture: one family with a singleton-addressable ingress, two interleaved scheduler groups, and a public output stream. Its generated address table uses the same normalized placements as the host descriptor. Additional topologies need gateways which realize their own bindings without accidentally turning a unicast into multicast.

## Identity and messaging

`hls_node:services/1` returns `#{actors => #{LogicalId => Pid}, debug => DebugPid}` for each topology declaration. Logical IDs use the existing `{actor, Id}` or `{family, Id, Coordinates}` forms. There is no local proxy process for each actor. Actor PID numbers use a namespace disjoint from standalone application/debug services and follow sorted deployment/logical identity order within an activation.

`hls_statem:cast/2` sends an actor record through ordinary distribution. The connection validates its schema and packs it using the generated module. A valid cast returning `ok` does not promise that hardware has accepted or executed it. ERTS sender suspension can still occur under distribution saturation. Actor effects go to the topology's declared recipients and outputs; they are not replies to the most recent sender.

Synchronous application calls return `{error, unsupported_call}`. This control-plane rejection is not a fence for earlier casts; it does not kill the physical actor or disconnect other targets. CPU `hls_statem` also rejects application calls, but currently stops its BEAM actor when doing so; hardware actor termination/exit propagation is not implemented here. Malformed casts and other unsupported messages retain the endpoint prototype's connection-failure behavior.

Per-connection queueing belongs to a physical ingress endpoint. Casts to actors sharing that endpoint preserve the order in which their distribution connection received them, including broker admission retries. A blocked actor can therefore hold up later traffic through that shared ingress. Distinct endpoints have separate queues, subject to shared transport and distribution admission. The connection-wide waiting limit can pause later debug requests arriving on that same distribution connection; an independent peer connection can still use the physical debug stream.

Disconnecting a peer retires its return routes and pending host requests. It leaves actor RAM and node-activation PIDs intact and does not replay accepted casts. Restarting the virtual node creates new PIDs, so old identities cannot reach the replacement. Monitors currently describe availability of that virtual identity/connection; a terminal hardware actor failure does not yet emit an Erlang `DOWN` signal independently of the connection.

## Addressed cast envelope

The outer routed frame uses the scheduler group's physical destination endpoint and the connection's allocated source endpoint. Its inner header contains the generated actor selector, transaction ID 255 and flags 1. Flags identify the addressed-cast envelope. Payload word zero is the normalized scheduler-local slot, encoded as a little-endian `u32`; subsequent words are the ordinary generated record encoding, aligned with `hls_codec:align/2`. This scheduled-PID gateway currently accepts at most 96 record payload bits; `hls_node_topology` checks that bound. The extra slot word is removed before mailbox admission. This gateway limit is separate from the configurable ordinary frame capacity used by other build paths.

The fixture gateway validates endpoint, slot, selector, flags, transaction ID, word count and the actual end of the frame. Rejected frames drain through their final beat and never become actor input. The gateway supplies ordinary scheduler admission, preserving the generated mailbox/reservation machinery. It does not allocate reply contexts for casts.

## Inspection

During build-side preparation, retain `hls_shared_debug_catalog:prepare(Plan, Specs, [], Projection)`. Runtime clients use `hls_shared_observation:open(Binding, DebugPid, Manifest)` to verify the device fingerprint and attach the public actor catalog without source or scheduler analysis. The retained projection and manifest resources must match. `hls_node_topology:bind_debug/4` remains a build-side convenience for callers that still have compiler inputs. `hls_debug_catalog:actor/2` then supplies an explicit target for `hls_debug:info/2,3`, including committed phase, failure, mailbox depth, credits and scheduler status where present in the projection.

The shared debug PID addresses the topology query service. It does not create per-actor counter/trace histories or imply support for standalone boundary-monitor commands. A bare external PID is not a native `process_info` target; use the catalog handle. Host `hls_fabric:client_info/1` reports adapter work, not hardware mailbox depth. Its pending/queued counts select the logical PID, while its route and ignored-reply count describe the shared physical endpoint.

## Validation

[The RTL fixture](../yap/actor-pid-validation.md) checks addressing, codec rejection, stalled-output diagnosis and reconnect behavior through the public interfaces.
