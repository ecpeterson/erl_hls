# Shared system and implementation model

`hls_core` owns the process-free terms shared across source analysis, compilation, communication planning, deployed execution and characterization. This boundary gives logical identities, process interfaces, communication requirements and retained implementation descriptors one authority without treating compiler summaries, runtime processes, wire formats or physical evidence as the same representation.

## Four layers

| Layer | Current authority | Establishes | Does not establish |
| --- | --- | --- | --- |
| Logical system | `hls_logical_identity`, `hls_process_interface`, `hls_logical_topology` | Computations, public message layouts, mailbox bounds, output ports, logical routes, fanout completion points, external boundaries, startup, families, ingress geometry and deterministic lanes | Placement, transport endpoints, process incarnations, numeric wire selectors or timing |
| Proposed implementation | Opaque `hls_build`, `hls_source_build` and `hls_scheduler_build` plans with `hls_build_profile` policy | A checked backend choice, placement/schedule/ABI policy, prepared sources and implementation constraints | Executed tools, generated-product identity, deployment admission or achieved timing |
| Realized implementation | Frozen `source-build.json` inputs followed by an immutable `compiled.json` release | Exact source-build, standard-library, tool and generated RTL identities | Native placement, timing closure, semantic refinement or workload behavior |
| Measured characterization | Validated `hls_spacetime` execution bundles, physical catalogues and explicit timing evidence | Evidence with a declared method, scope, finite horizon and exact observed-build correlation | Unobserved behavior, all-input proof, a universal clock period or optimization validity outside that scope |

The layers remain separate even when one pipeline produces all of them. A source bundle is not a realized implementation, a compiled release is not a measurement, and a matching identity is not evidence authenticity. Genuine JSON, ETF, file, cache, tool and device boundaries retain their serialization and independent validation.

## Core adapters

`hls_topology` is the compiler acquisition façade. It loads source-bound `hls_actor_interface` summaries, projects only stable process-interface facts, and delegates normalization to `hls_logical_topology`. The compiler summary remains richer because source freshness, callback effects, state layout, selectors and syntax positions are compiler facts rather than logical-system fields.

`hls_logical_topology` owns compact validation, family-route resolution, lane derivation and bounded materialization. A checked plan retains its exact `hls_process_interface` catalog and ordered exact/family instance provenance. Physical backends may reacquire richer compiler summaries for selectors, frame layout and startup encoding only after proving that those summaries project exactly to the retained catalog. Protocol, partition, observation and debug consumers use the core materialization and instance identities rather than expanding families independently.

`hls_implementation_constraints` owns the common topology-name, channel, egress, ordinary-frame and retained-schedule vocabulary. Compiler and Fabric wrappers add target-reserved names, observation switches, placement, RAM selection and tool execution. Their bundle-specific flag order remains an encoding boundary, not a second schedule authority.

`hls_host_codec` and `hls_protocol_application_schema` are retained implementation contracts in core. Lowering constructs them from checked source and topology facts. Fabric codecs interpret them at a real wire boundary; sessions, routing, queues, endpoint allocation and incarnation handling remain outside core.

`hls_observation_build` owns the exact `source`/`rtl`/`observation` correlation map shared by observer and spacetime code. Its components are opaque nonempty bytes. Producers remain responsible for establishing what each component identifies, while spacetime artifacts may impose stricter textual serialization rules.

## Identity domains

Logical IDs are atoms, integers or nonempty recursive tuples. They are not dense hardware indices, actor-key digests, endpoint numbers, Erlang PIDs, runtime incarnations, session/request IDs, filenames or artifact-local spacetime IDs. `hls_actor_identity` distinguishes an exact actor from a bounded family member in the canonical instance reference, and deterministically hashes that reference for retained manifests without converting the hash into the logical ID itself.

These distinctions are required for later joint optimization. A future optimizer may revise computation, communication, placement and scheduling from supplied characterization, but it must do so through explicit implementation contracts and preserve the logical system unless a separately checked transformation changes it.

## Dependency rule

`hls_core` depends only on OTP. The compiler, lowering, Fabric, runtime, examples and observer may depend on core; core may not depend on any of them. Runtime remains independent of compiler and lowering. Offline spacetime validation consumes the core correlation contract without acquiring compiler source or starting runtime processes.
