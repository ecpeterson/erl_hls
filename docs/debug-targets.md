# Scoped debugging targets

`hls_debug:info(Target, Item)` uses the item/result convention of [`erlang:process_info/2`](https://www.erlang.org/doc/apps/erts/erlang.html#process_info/2): a single item returns `{Item, Value}`, and a list returns a list of those pairs in the requested order. A target identifies what is being observed. `scope` and `capabilities` describe that target without contacting it. Unsupported items return `{error, {unsupported_items, Scope, Items}}`; they never silently fall back to a different queue or process.

| Target | Inspection items | Meaning |
| --- | --- | --- |
| BEAM PID | `message_queue_len`, `status`, `reductions`, `memory` | Native process information; for an `hls_gs` hardware proxy this describes the host proxy. |
| `{hls_statem, Pid}` or a bound CPU actor | `message_queue_len`, `mailbox_capacity`, `free_slots`, `reserved`, `postponed`, `phase`, `lifecycle`, `reduction`, `beam_message_queue_len` | The reference actor's bounded mailbox and scheduler state, with its front-end BEAM queue reported separately. |
| Hardware actor with a verified snapshot binding | `phase`, `enter_pending`, `failed`, `failure`, `reduction`, `initialized`, `cycle`, `observation`, optional mailbox counts/work flags, and binding metadata | Last published committed actor state, direct mailbox counts, and optional backend metadata. Queries do not wait for the actor. |
| Hardware actor with a metadata-only binding | `identity`, `module`, `placement`, `mailbox_capacity`, `boundaries` | The supplied build plan's logical identity, physical placement, declared capacity, and related monitored boundaries. Live actor mailbox occupancy is not available. |
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

## Open reductions

Reference actors and hardware actors with snapshot providers support `hls_debug:info(Actor, reduction)`. This singular item describes an application reduction; the native PID item `reductions` remains ERTS's execution counter.

An idle window returns `idle`. An active one includes `status`, opening `phase`, reduction `name`, `key`, declared `population`, `received`, `remaining`, and `failure`. CPU inspection returns `#{class => Class, reason => Reason}` for a pending reducer exception, without exposing its stack or accumulator. Hardware decodes a failure code and optional source location. A pending exception does not stop inspection or close the window: valid remaining contributions must still arrive. The CPU process exits when the final contribution releases the exception; hardware retains its terminal failure latch. Before the first committed hardware write, the reduction observation is `undefined`.

Hardware actors need the optional [register-backed actor provider](topology-debug.md#register-backed-actor-snapshots).

## Hardware actors and monitored boundaries

Generate actor observations with `direct_actor_debug => true`, instrument the RTL using its actor projection, and open a verified topology session. Bind logical actors with `hls_debug_catalog:hardware(Plan, #{}, Boundaries, Session)`. The empty placement map selects dedicated actors. The catalog rejects a mismatched projection or resource manifest before querying.

`phase` is the Erlang phase atom. Requested fields share one sample. Before the first state publication, `initialized = false` and the phase, failure and reduction fields are `undefined`. CPU failure ordinarily terminates the process; hardware retains a failure latch.

`observation` identifies the committed-state resource and its manifest fingerprint. The snapshot can lag an in-flight callback and its timestamp dates the query rather than the last state write. The `failure` item is `none` for a healthy initialized actor, or a map such as `#{code => 276, kind => case_clause, file => <<"actor.erl">>, line => 42}`. Protocol failures may omit `file` and `line`. The code is artifact-local; use the decoded reason and origin. All requested actor items share one sample. Direct snapshots include mailbox depth, postponed entries, reservations, and free slots. It retains no event history or state age. After reset, acquire a fresh transport session and catalog. Counters, traces, and physical wait inspection retain their separate scopes.

A boundary monitor observes its routed stream. Internal actor traffic that does not cross that boundary is excluded. Counters measure accepted beats/frames and stalled cycles; traces retain accepted headers. Neither claims actor-level event tracing. Several actors can share the same related boundary.

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

For a build with [mailbox observations](topology-debug.md#direct-actor-mailbox-observations), query `message_queue_len`, `postponed`, `reserved` and `free_slots` just as on CPU. Counts, phase, failure and reduction metadata share one committed-state publication. An outstanding admission credit appears as `reserved = 1`; free space excludes it.

`observation.mailbox` is `actor_step` or `unavailable` for dedicated actors. Additional backends may supply an explicit local observer with `hls_topology_debug:with_actor_observer/2`; wire metadata never selects executable code.
