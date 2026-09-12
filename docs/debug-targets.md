# Scoped debugging targets

`hls_debug:info(Target, Item)` uses the item/result convention of [`erlang:process_info/2`](https://www.erlang.org/doc/apps/erts/erlang.html#process_info/2): a single item returns `{Item, Value}`, and a list returns a list of those pairs in the requested order. A target identifies what is being observed. `scope` and `capabilities` describe that target without contacting it. Unsupported items return `{error, {unsupported_items, Scope, Items}}`; they never silently fall back to a different queue or process.

| Target | Inspection items | Meaning |
| --- | --- | --- |
| BEAM PID | `message_queue_len`, `status`, `reductions`, `memory` | Native process information; for an `hls_gs` hardware proxy this describes the host proxy. |
| `{hls_statem, Pid}` or a bound CPU actor | `message_queue_len`, `mailbox_capacity`, `free_slots`, `reserved`, `postponed`, `phase`, `lifecycle`, `beam_message_queue_len` | The reference actor's bounded mailbox and scheduler state, with its front-end BEAM queue reported separately. |
| Hardware actor with a verified snapshot binding | `phase`, `enter_pending`, `failed`, `initialized`, `cycle`, `observation`, plus the metadata below | Last committed shared-actor state. Queries do not wait for the actor or scheduler. |
| Bound hardware actor | `identity`, `module`, `placement`, `mailbox_capacity`, `boundaries` | The supplied build plan's logical identity, physical placement, declared capacity, and related monitored boundaries. Live actor mailbox occupancy is not available. |
| Physical topology resource | `name`, `resource_kind`, `cycle`, `value`; FIFO `capacity`, `occupancy`, `free_slots`; channel `valid`, `ready` | One passive FPGA resource sample. A physical FIFO can carry a frame, a credit, or an internal request; its occupancy is not an actor's mailbox depth. |
| `{boundary, DebugClient, Id}` | `scope`, `capabilities` | An explicitly named monitored interface supporting `get_counters` and `get_trace`. |

All structured targets support `scope` and `capabilities`; bound CPU actors also support `identity`, `module`, `placement`, and `boundaries`. Capabilities list supported information items and whether counters, event traces, or wait inspection are available. Metadata queries can still describe a target after its process or connection has gone away; successful live inspection is not implied by having a handle.

## CPU mailboxes

```erlang
{message_queue_len, BeamQueued} = hls_debug:info(Pid, message_queue_len),
Actor = {hls_statem, Pid},
[{message_queue_len, Admitted}, {postponed, Postponed}, {free_slots, Free}] =
    hls_debug:info(Actor, [message_queue_len, postponed, free_slots]).
```

For a reference actor, `message_queue_len` counts committed, unconsumed entries in its bounded mailbox, including postponed entries. `reserved` counts capacity claims without a committed message, and `free_slots` is capacity minus committed and reserved entries. The current CPU scheduler admits and commits synchronously, so it does not expose an intermediate reservation between callbacks. `postponed` is a subset of committed entries, not an additional queue to add to that count.

The BEAM mailbox is upstream of this bounded queue and can also contain control messages. The two counts must not be added and presented as one atomic mailbox snapshot. Native `gen_statem` postponement likewise has an internal queue beyond its process mailbox; passing any ordinary PID to this interface retains the native process meaning.

Actor state uses the existing `hls_statem:info`/`sys:get_state` path and is observed between callbacks. It requires that the actor return control to its runtime. A query for only `beam_message_queue_len` uses native process inspection and does not wait for the callback. If both are requested, the state and BEAM queue are sampled separately. `info/3` supplies a timeout for state and hardware queries; the default is five seconds. A missing process yields `undefined`, and an inspection timeout yields `{error, timeout}`. Native process inspection uses the BIF's own behavior rather than that timeout.

The phi-memory CPU fabric exposes its logical actor bindings directly:

```erlang
Catalog = phi_memory_cpu_fabric:debug_targets(Fabric),
Ids = hls_debug_catalog:actors(Catalog),
{ok, Actor} = hls_debug_catalog:actor(Catalog, {family, phi_x, [0, 0]}),
hls_debug:info(Actor, [identity, placement, message_queue_len, postponed]).
```

A different CPU launcher can use `hls_debug_catalog:cpu(Plan, Processes)`, where `Plan` is the normalized topology and `Processes` maps every `{actor, Id}` or `{family, Id, Coordinates}` to its `hls_statem` PID. Missing or extra bindings are rejected. These bindings explicitly name reference actors; a transport proxy is not an actor binding. Handles belong to that process incarnation and must be reacquired after a restart.

## Shared hardware actors and monitored boundaries

```erlang
Plan = hls_topology:from_module(phi_noise_topology),
Profile = phi_noise_topology_dslx:profile(),
Boundary = {boundary, DebugClient, {phi_memory_gateway, host_stream}},
Catalog = hls_debug_catalog:hardware(
    Plan, maps:get(scheduler_groups, Profile), [Boundary]),
{ok, Actor} = hls_debug_catalog:actor(Catalog, {family, phi_x, [0, 0]}),
hls_debug:info(Actor, [identity, placement, mailbox_capacity, boundaries]),
{ok, Counters} = hls_debug:get_counters(Boundary),
{ok, Events} = hls_debug:get_trace(Boundary).
```

Shared placements identify the scheduler group ID, its generated zero-based index, and the actor's slot within it. Interleaved families use the normalized scheduler plan's member instances and local indices; they do not assume that a logical row-major index equals a physical slot. Ungrouped actors have direct placement. The supplied plan and explicitly related boundary handles are host declarations, not a bitstream identity check. They do not associate generated signal names or physical resource IDs with logical actors. Physical resource sessions independently verify the RTL manifest fingerprint.

To inspect committed shared-actor state, generate a diagnostic build with [actor projections](topology-debug.md#shared-actor-snapshots), open its verified topology session, and pass that session as the fourth catalog argument:

```erlang
Catalog = hls_debug_catalog:hardware(Plan, Specs, [Boundary], Session),
{ok, Actor} = hls_debug_catalog:actor(Catalog, {family, phi_x, [0, 0]}),
hls_debug:info(Actor, [identity, placement, initialized, phase, enter_pending, failed, cycle]).
```

This binding checks the complete compiler projection against the manifest, including phase names and scheduler slots. A different plan, shard count, or actor-resource map is rejected before querying. `phase` is the actor's Erlang phase atom, also used by CPU inspection. Low-level actor resources return the manifest's binary phase name. Multiple fields in one call share a single sample. `initialized = false` gives `undefined` for phase and flags. CPU failures ordinarily terminate the process, so CPU targets do not advertise a persistent hardware failure latch.

`observation` identifies the committed-state resource and its manifest fingerprint. The snapshot can lag an in-flight callback and its timestamp dates the query rather than the last state write. It does not report mailbox depth, failure reason, source location, event history, or how long a state has persisted. After reset, acquire a fresh transport session and catalog. Counters, traces, and physical wait inspection retain their separate scopes.

The phi-memory monitor observes the routed host application stream around the whole gateway. Requests can be distributed to many embedded actors, and internal actor traffic does not pass through that boundary. Its counters count accepted stream beats/frames and stalled cycles; its routed trace records accepted inner application headers with their source/destination endpoints. After missed observations it suppresses headers until an accepted `TLAST` restores framing, and reports that loss through framing status and event gap flags. Neither measures actor activations, scheduler utilization, or all messages delivered to an actor. Operation tags and 8-bit transaction IDs are not globally unique actor identities. Several actors may therefore list the same related boundary.

Scoped counter/trace results include `scope => #{kind => boundary, id => Id}`. Both `get_counters(Actor)` and `get_trace(Actor)` reject the request without contacting the device. Select an entry from `boundaries` explicitly to inspect shared observations. This matters especially for `get_trace`: it drains that monitor's bank for every client of the boundary, not just the actor through which it was discovered. The [counter/trace protocol](debug-protocol.md) defines wrapping counters, observation drops, event overflow, and drain-on-read behavior. Timeouts do not cancel a device-side trace drain; after a transport timeout or reset, establish a fresh transport session.

The low-level `hls_debug:get_counters(DebugClient)` and `get_trace(DebugClient)` forms still accept a debug-client PID. That PID is a protocol client, not an application process. Use scoped targets in application-facing tooling. For native process event collection and statistics, use ERTS tracing or [`sys:statistics` and `sys:trace`](https://www.erlang.org/doc/apps/stdlib/sys.html); hardware boundary events and counters do not claim those semantics. Inspecting a CPU actor does not enable a recorder or install tracing flags.

## Physical queues and current waits

```erlang
{ok, Resource} = hls_topology_debug:resource(Session, ResourceId),
hls_debug:info(Resource, [scope, resource_kind, occupancy, free_slots, cycle]),
{ok, Report} = hls_debug:inspect_waits(Resource, #{max_queries => 1024}).
```

Select FIFO items for a FIFO target and handshake items for a channel target. All dynamic items requested together for one physical resource share one sampled value and cycle. Two separate calls are separate observations. A metadata-only query, including `capacity`, performs no device request. Free slots do not imply push readiness: registered readiness or same-cycle pop credit can affect the actual handshake.

`inspect_waits` explores and rechecks candidate backpressure dependencies; it does not collect an event trace. The multi-seed form remains `hls_topology_debug:inspect_waits(Session, Seeds, Options)`, with `write_wait_report/4` for saving a report. The [topology query contract](topology-debug.md) explains non-atomic walks, bounded query budgets, uncertain dependencies, and clock resets. CPU process links and output connections are not inferred to be wait dependencies, and CPU or logical actor targets currently reject this operation.

Live scheduler mailbox counts and actor-level events require semantic observation points and generated identity mappings beyond the physical FIFO exporter. A scheduler's request FIFO, pending input registers, mailbox RAM, and active continuation are different resources; reporting the first visible queue as the actor's mailbox would give misleading answers under backpressure.
