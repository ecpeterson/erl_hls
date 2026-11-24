# Shared model contracts

This directory owns process-free data shared across compiler, lowering, Fabric, runtime and characterization consumers.

- `hls_logical_identity` defines recursive logical names without conflating them with indices, endpoints, PIDs or incarnations.
- `hls_process_interface` retains exact public schema fields, mailbox bounds and output domains needed to validate communication.
- `hls_logical_topology` and its helpers retain the validated interface catalog, normalize compact graphs, resolve family routes, derive lanes and materialize bounded exact graphs.
- `hls_host_codec` and `hls_protocol_application_schema` retain source-checked implementation descriptors for later wire consumers.
- `hls_observation_build` correlates source, RTL and observation identities without claiming evidence authenticity.
- `hls_implementation_constraints` normalizes shared topology capacities, names, frame selection and retained schedules while backend wrappers keep target-specific placement and observation policy.

Compiler acquisition, backend plans, live processes, wire encodings and measured evidence remain with their owning applications. See the [shared system model](../../../../docs/system-model.md) for the layer boundaries.

Physical backends may attach selectors, frame capacities and startup encodings from richer compiler summaries, but those summaries must project exactly to the retained core catalog. They do not reacquire a second logical schema authority.
