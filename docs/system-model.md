# Shared system and implementation model

`hls_core` owns the process-free terms shared across source analysis, computation synthesis, communication planning, target materialization, deployed execution and characterization. This boundary gives logical identities, process interfaces, proposed implementations and correlated evidence one authority without treating compiler summaries, runtime processes, wire formats or physical measurements as the same representation.

## Four layers

| Layer | Current authority | Establishes | Does not establish |
| --- | --- | --- | --- |
| Logical system | `hls_logical_identity`, `hls_process_interface`, `hls_logical_topology` | Computations, public message layouts, mailbox bounds, output ports, logical routes, fanout completion points, external boundaries, startup, families, ingress geometry and deterministic lanes | Placement, transport endpoints, process incarnations, numeric wire selectors or timing |
| Proposed implementation | Core `hls_implementation_plan`, with policy in `hls_spacetime` | Exact logical-system identity, complete actor placement, scheduler requests, owner-defined constraints/capabilities and revision provenance | Physical slots, generated source, executed tools, deployment admission or achieved timing |
| Realized implementation | `hls_target` materialization, frozen `source-build.json` inputs and immutable `compiled.json` releases | Exact target inputs, standard-library, tool and generated-product identities | Native timing closure, semantic refinement, deployment state or workload behavior |
| Measured characterization | Core `hls_characterization`, validated Spacetime execution artifacts and target-owned physical/timing adapters | Evidence with a declared method, scope, exact plan/implementation correlation and explicit metrics | Evidence authenticity, unobserved behavior, all-input proof, a universal clock period or optimization validity outside that scope |

The layers remain separate even when one pipeline produces all of them. A source bundle is not a realized implementation, a compiled release is not a measurement, and a matching identity is not evidence authenticity. Genuine JSON, ETF, file, cache, tool and device boundaries retain their serialization and independent validation.

## Core adapters

`hls_topology` is the compiler acquisition façade. It loads source-bound `hls_actor_interface` summaries, projects only stable process-interface facts, and delegates normalization to `hls_logical_topology`. The compiler summary remains richer because source freshness, callback effects, state layout, selectors and syntax positions are compiler facts rather than logical-system fields.

`hls_logical_topology` owns compact validation, family-route resolution, lane derivation and bounded materialization. A checked plan retains its exact `hls_process_interface` catalog and ordered exact/family instance provenance. Physical backends may reacquire richer compiler summaries for selectors, frame layout and startup encoding only after proving that those summaries project exactly to the retained catalog. Protocol, partition, observation and debug consumers use the core materialization and instance identities rather than expanding families independently.

`hls_implementation_constraints` owns the common topology-name, channel, egress, ordinary-frame and retained-schedule vocabulary. Computation and communication planners add source and routing facts; target planning adds reserved names, observation switches, physical layouts and tool choices. Bundle-specific flag order remains an encoding boundary, not a second schedule authority.

`hls_host_codec` and `hls_protocol_application_schema` are retained implementation contracts in core. Fabric planning derives codec requirements from checked source and topology facts, target materialization binds them to emitted interfaces, and runtime codecs interpret them at a real wire boundary. Sessions, live routing, queues, endpoint allocation and incarnation handling remain outside core.

`hls_observation_build` owns the exact `source`/`rtl`/`observation`/`implementation` correlation map shared by observer and spacetime code. Its components are opaque nonempty bytes. Producers remain responsible for establishing what each component identifies, while spacetime artifacts may impose stricter textual serialization rules.

`hls_implementation_plan` is the canonical proposal boundary. It binds one opaque logical-system identity to complete stable-actor placement, homogeneous scheduler requests, constraints, capabilities and planner provenance. `hls_spacetime` may construct or revise this value through pure policies. `hls_target` may interpret a checked plan, but physical layouts and tool inputs do not become fields merely because one target needs them.

`hls_characterization` binds metrics to the exact identities of one proposed plan, one realized implementation and one evidence object. Its declared method and scope keep analytical, simulation, synthetic and native evidence distinct. Validation establishes shape and correlation, not authenticity or physical sufficiency. Plan revision records the characterization identity as its basis, so a supplied value and the same value loaded from a caller-owned cache are indistinguishable to optimizer policy.

## Identity domains

Logical IDs are atoms, integers or nonempty recursive tuples. They are not dense hardware indices, actor-key digests, endpoint numbers, Erlang PIDs, runtime incarnations, session/request IDs, filenames or artifact-local spacetime IDs. `hls_actor_identity` distinguishes an exact actor from a bounded family member in the canonical instance reference, and deterministically hashes that reference for retained manifests without converting the hash into the logical ID itself.

These distinctions permit joint optimization without a reverse package dependency. The current pure optimizer can revise placement and scheduler requests from supplied characterization. Later computation/communication co-optimization must use the same explicit contracts, include physical timing feedback and preserve the logical system unless a separately checked transformation changes it.

## Dependency rule

The seven product applications have one-way ownership:

1. `hls_core` depends only on OTP.
2. `hls_runtime` depends on core and owns live execution, wire codecs and virtual-node supervision.
3. `hls_compile` owns computation synthesis and may use core/runtime contracts; it cannot depend on Fabric, target, Spacetime or the facade.
4. `hls_fabric` owns communication synthesis and may consume compiler facts; it cannot depend on target, Spacetime or the facade.
5. `hls_target` owns physical materialization and characterization adapters; it cannot depend on Spacetime or the facade.
6. `hls_spacetime` owns pure system-plan policy and offline execution analysis. It consumes core contracts and target-validated physical values, while target never calls back into it.
7. `erl_hls` is the CLI and orchestration facade over the lower applications.

The optional `hls_spacetime_observer` application is a coherent cross-layer integration adapter and may consume compiler, Fabric, target and Spacetime products. Keeping that adapter separate prevents its broad dependency closure from becoming an authority in any lower package. Example applications depend only on the product boundaries they exercise.

Static package audits enforce the prohibited reverse edges, and fresh boundary projections exercise computation, communication, physical materialization and optimizer policy independently. Runtime-only releases contain core and runtime code, not synthesis or optimization applications.
