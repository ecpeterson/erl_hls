# Current-state topology queries

Query channels, FIFO occupancy and committed actor state to investigate backpressure without recording history. Queries are passive: a stalled debug reader cannot stall application traffic. Instrumentation can still cost area and affect timing.

Start with the [common inspection API](debug-targets.md). Use physical queues to follow transport waits and actor snapshots to interpret application state; neither alone proves deadlock.

## Generate a diagnostic build

Run `tools/topology_debug.py` on the application's generated RTL and RAM shell. For the D3 profile:

```sh
compiled=$(cd "$stage/compiled" && pwd -P)
python3 tools/topology_debug.py \
  --top phi_decoder_profile_top --clock aclk \
  --reset aresetn --reset-active-low \
  --stage "$stage/topology-debug" \
  "$compiled/phi_decoder_profile.v" "$compiled/phi_decoder_profile_top.v" \
  "$compiled/hls_1r1w_ram.v"
```

Supply Yosys on `PATH` or through `--yosys`. All observed channels must share the selected clock; crossings are rejected. Clock/reset defaults are `clk` and active-high `reset`. Preserve the application's actual reset polarity.

Compile `instrumented.v`, `debug_top.v` and `priv/rtl/debug/{hls_debug_frame_rx,hls_debug_route,hls_topology_debug}.v`, selecting `hls_debug_application` as top. Actor projections also require `hls_actor_snapshot.v`. The wrapper preserves application ports and adds `s_dbg_*`/`m_dbg_*`. Reserved-port collisions require connecting the inner query service to an existing router instead.

Keep `manifest.json` with the **exact bitstream**. Its embedded fingerprint covers resource wiring and source hashes. Resource IDs and hierarchy names are build-local; logical actor identities come from a verified catalog. A projection and width-compatible RTL alone do not prove semantic correspondence.

## Query and inspect waits

```erlang
{ok, Bytes} = file:read_file("manifest.json"),
Manifest = json:decode(Bytes),
{ok, Debug} = hls_debug:start_link(undefined, {fabric, DebugFabric, 2}),
{ok, Session} = hls_topology_debug:open(Debug, Manifest),
{ok, Sample} = hls_topology_debug:query(Session, ResourceId),
{ok, Report} = hls_topology_debug:inspect_waits(Session, [ResourceId], #{max_queries => 1024}),
ok = hls_topology_debug:write_wait_report(Session, [ResourceId], #{}, "wait.json").
```

`open/2` verifies the manifest fingerprint and catalog counts. Replies identify the resource, observation cycle and value; invalid IDs, codes or occupancies are rejected. Queries time out after ten seconds. After timeout or reset, establish a fresh transport session and catalog.

```sh
python3 tools/topology_debug_report.py manifest.json --find actor_0
python3 tools/topology_debug_report.py manifest.json wait.json
```

The walker follows blocked channels to consumers and FIFO pop boundaries, probes possible outgoing dependencies, and rechecks visited resources. Its budget reserves rechecks and reports truncation. Reports distinguish external sinks, ambiguous connections, changes and repeatedly blocked cycles.

Each query samples one edge and holds that reply stable; separate queries are not an atomic snapshot. Equal samples do not establish continuous blockage or stall duration. Wiring cannot identify every internal continuation or arbitration condition, so a blocked cycle is a **candidate**, not proof of deadlock. The 64-bit cycle counter resets with the application; nonincreasing observations are rejected, but a reset followed by a long gap can escape detection.

## Physical observations

| Resource | Meaning |
| --- | --- |
| Channel | Sampled `valid` and `ready`. Constant or ambiguous connections cannot establish dependencies. |
| FIFO | Stored `occupancy`, capacity, `free_slots`, and push/pop channel IDs. Acceptance still depends on the sampled ready bit. |

Depth-zero bypass FIFOs are wires. Empty bypass transfers may occupy no storage; some full FIFOs accept a simultaneous pop/push. Unsupported queue implementations retain handshake probes and appear in `unsupported_queues`; unexpected shapes in recognized implementations fail generation. Physical FIFO depth is distinct from an actor's mailbox depth.

## Register-backed actor snapshots

Set `direct_actor_debug => true` in the topology profile, pass `artifact_requirements/2` options to actor translation, and use the same option in `xls_actor_debug:projection/3`. Shells must forward outputs using `xls_actor_observation:bindings/2`, `wires/1` and `ports/1`; the latter ties readiness high. Enabling an artifact alone does not instrument an arbitrary wrapper.

Snapshots describe the committed state **entering** an actor step and can lag through its output pipeline. A stalled next-state computation is not published. Phase, failure, reduction and mailbox fields share one publication. Initial state can become visible before the initial entry executes. Constant observation readiness is mandatory: a backpressured observation consumer could stall the actor.

Snapshots preserve logical actor identity and require the current build's projection and manifest. They retain no callback data, accumulator values, member bitmaps or message history.

## Direct-actor mailbox observations

Direct observations include mailbox counts. Query `hls_debug:info(Actor, [message_queue_len, postponed, reserved, free_slots])`:

- `message_queue_len`: received, unconsumed entries, including postponed messages.
- `postponed`: entries waiting for a phase boundary.
- `reserved`: zero or one outstanding admission credit; its frame may still be in transport.
- `free_slots`: capacity minus depth and reservations.

Thus `message_queue_len + reserved + free_slots = mailbox_capacity`. Free zero does not forbid arrival using an existing credit. Upstream frames without credit are excluded. Until the first publication, `mailbox_initialized` is false and counts are `undefined`.

## Reduction observations

`hls_debug:info(Actor, reduction)` returns `undefined` before initialization, `idle`, or a map containing status, opening phase/name/key, population, received/remaining counts and pending failure. It identifies neither the missing fixed members nor the accumulator.

A failed fold drains its remaining valid contributions before releasing terminal actor failure. A complete failed window can remain visible after the actor stops. Queries do not consume, cancel or release it. See [reduction semantics](actor-reductions.md).

## Shared counter/trace and query transport

Add `--monitor-rx s_axis --monitor-tx m_axis --monitor-routed` for a passive monitor on 32-bit AXIS streams; omit `--monitor-routed` for unaddressed frames. Each prefix must supply data, valid, ready and last with appropriate directions.

| Endpoint | Service |
| --- | --- |
| 1 | `hls_debug:get_counters/1,2` and `get_trace/1,2` on a boundary handle |
| 2 | Topology queries and scoped actor inspection |

Register both clients with the same fabric broker. Queries serialize across services, including trace drains. An unread reply delays later debug traffic, while application execution and observation updates continue. A permanently incomplete request or unread reply requires transport recovery/reset; there is no router timeout. Counter/trace timestamps and capacity follow the [boundary protocol](debug-protocol.md), independently of query timestamps.

Boundary monitoring also requires `hls_debug_monitor.v`, `hls_debug_tap.v`, `hls_trace_store.v` and generated XLS observer/server RTL. The [query wire reference](topology-query-format.md) specifies inner packets and observation layouts.
