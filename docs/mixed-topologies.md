# Mixed actor placement

A topology can combine exact actor instances and rectangular actor families. Logical routes and startup messages describe the application; `scheduler_groups` independently assigns actors to homogeneous shared executors. Ungrouped actors instantiate their ordinary register-backed `Service`. A singleton does not acquire a state RAM or shared scheduler merely because its neighbors use one.

Exact routes address a particular family member using its existing instance ID. A family relation can address a fixed singleton:

```erlang
#{actors => #{source => source_actor, collector => collector_actor},
  families => #{workers => #{module => worker_actor, shape => [2, 2]}},
  routes => [{{source, work}, queued,
              [{actor, {workers, X, Y}} || X <- [0, 1], Y <- [0, 1]]}],
  route_relations => [{{workers, result}, [{actor, collector}]}],
  ...}
```

The complete description must still give every declared output exactly one route. Exact routes have exact actor sources; individual family members do not override their family's relations. Recipient coordinates are checked against the family shape. Schemas and field layouts must match across each route. The current direct-frame transport also requires matching numeric schema selectors at source and destination.

One placement can share all four workers:

```erlang
#{workers => #{members => [{family, workers}],
              state_storage => block_ram, mailbox_storage => block_ram}}
```

Another can split them into two interleaved executors, using `{family, workers, {interleaved, 0, 2}}` and `{family, workers, {interleaved, 1, 2}}`. An exact actor with the same callback module can join either group using `{actor, Id}`. Groups require complete family coverage and one callback module per executor. These placement choices retain the logical `{actor, Id}` and `{family, Id, Coordinates}` identities used by the debug catalog.

## Physical routing

`xls_topology_dslx` selects the materialized backend when a graph combines exact actors and families, schedules exact actors, or leaves some families direct while sharing others. It expands family members into physical endpoints and routes a complete frame either to a direct actor's admitted ingress or to a shared executor's slot-addressed request input. Startup messages precede ordinary routed inputs at each destination. Shared startup messages must fit that actor's mailbox because initialization finishes before the executor dispatches application work.

Each physical source and logical recipient share an ordered lane across all aliased output ports. A queued fanout waits for all selected lane sends before advancing to the next effect. Shared routers use the same retained-batch and return-credit implementation as the compact family backend. Return credits have dedicated producer inputs and cannot wait behind application requests for mailbox capacity. Direct actors retain their existing admission-credit contract and do not contend for shared lookahead credits.

All shared executors in a mixed graph use one global effect-window arbiter. A direct actor can transmit backpressure between shared groups, so partitioning solely by immediate shared-to-shared edges would be unsafe. `weak_components` is rejected for mixed graphs until its dependency analysis includes these indirect paths.

For exact-only graphs, supplying `scheduler_groups` opts into this placement-capable backend, including `scheduler_groups => #{}` for an entirely direct realization. Omitting the key retains the original scalar backend.

The materialized backend currently accepts closed graphs, two-dimensional families, RAM-backed shared state/mailboxes, and direct or queued fanout. Rectangle ingress and source-fragment reduction placement are rejected explicitly. Ordinary actor-owned reductions retain their actor implementation. Generated source and physical routing resources scale with the deployed population and its source/destination incidences; this path is intended for bounded mixed deployments. Wholly direct and wholly shared regular-family graphs retain the compact channel-array backend used by D3.

## Inspection and validation

Set `direct_actor_debug => true` and, when there are shared executors, `mailbox_debug => true` in the physical profile. Obtain actor compilation options from `xls_topology_dslx:artifact_requirements/2`; one module used in both placements needs both sets of diagnostic ports. Generate `xls_scheduler_debug:projection/4` from the exact artifacts and bind one `hls_debug_catalog:hardware/4`. Direct and shared actors expose the same logical identities, phase and failure information. Shared actors additionally expose their scheduler's mailbox/work observations; direct mailbox reservation counts are not yet projected.

`bash tools/test_mixed_topology.sh XLS_ROOT` runs a closed feedback workload as all-direct actors, one worker executor, two interleaved worker executors, and a group containing both a family and an exact worker. A singleton source sends two aliased work messages to each of five workers. Each worker checks input order and emits two aliased results; a singleton collector checks all twenty distinct results before reporting and triggering the next round. The RTL must match all 32 reports from the CPU realization of the same normalized routes, including the final feedback completion.

The test exercises pipeline depths two and three, holds the external output blocked, inspects all actors and follows the blocked sink through public debug queries, then releases it and requires recovery. It rejects combinational cycles and checks cycle-by-cycle equivalence between the original generated RTL and its passive debug instrumentation. It does not assert a global arrival order between workers or identical cycle timing across placements.
