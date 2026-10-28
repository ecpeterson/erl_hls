# Compiler documentation audit

Review baseline: `d40cce0`, branch `codex/documentation-paths`, 2026-10-28. Scope is all 35 `docs/*.md` guides, the root README and every compiler/runtime source-directory README. `AGENTS.md` and `STYLE.md` are governing instructions; `LICENSE.md` is unchanged legal text. Working/historical material under `yap/` is outside the public-guide currency audit.

This is a source-backed documentation review, not a new hardware qualification. The source review is supplemented by the local checks below; no XLS compilation, decoder RTL rerun or physical measurement was performed. Existing test descriptions were checked against their current drivers and cases. Remote documentation links were not fetched. The Phi walkthrough link targets the coordinated hls_fabric documentation change.

| Guide | Disposition | Checked authority and correction |
| --- | --- | --- |
| `README.md` | Updated | Package ownership; current golden staging and required remote stage argument. Evidence: rebar.config, tools/xls_goldens.sh, tools/run_xls_sim.sh. |
| `apps/hls_runtime/README.md` | Reviewed; current | Library package, dynamic provider semantics and broker-versus-downstream naming remain current. Evidence: hls_runtime.app.src, runtime imports and compiler provider split. |
| `apps/hls_runtime/src/api/README.md` | Reviewed; current | Actor/type/retained-codec vocabulary and compiler parse-transform boundary remain current. Evidence: API module exports and source tree. |
| `apps/hls_runtime/src/runtime/README.md` | Reviewed; current | CPU actors, device sessions and retained observation responsibilities remain current. Evidence: runtime module exports and package declarations. |
| `docs/README.md` | Updated | Navigates compiler/runtime, telemetry, downstream Phi, contracts and capture-vs-render scope. Evidence: source/package entry points and docs below. |
| `docs/actor-compilation.md` | Updated | Current emitted-artifact, layout and snapshot APIs; statem-only topology scope. Evidence: xls_parse, xls_actor_codegen, xls_statem_codegen, xls_actor_program, xls_statem_plan. |
| `docs/actor-names.md` | Reviewed; current | Checked names, enum/tag capacities and spelling remain current. Evidence: xls_names, hls_actor_source, test/xls_names_tests.erl. |
| `docs/actor-reductions.md` | Reviewed; current | Open/contribute/completion, fold assumptions and bounded progress observations remain current. Evidence: hls_statem, xls_statem_reduction_lower, hls_topology_debug, reduction fixtures. |
| `docs/application-framing.md` | Updated | Selected ordinary-frame capacity replaces universal three-word limit; explicit receiver/test capacities remain. Evidence: hls_frame_layout, priv/xls/lib/axis.x, frame_transport.x, application_frames regression. |
| `docs/bit-syntax.md` | Updated | Separates immediate and retained-server failure behavior. Binary widths/pattern limits remain current. Evidence: xls_binary_lower, xls_gs_immediate, xls_gs_deferred. |
| `docs/build-storage.md` | Reviewed; current | Explicit idle-build compression workflow, thresholds, exclusions and retention claims remain current. Evidence: tools/compact_build.py. |
| `docs/ci.md` | Reviewed; current | Inventory-selected/local-only cases, fresh stages, qualification keys and diagnostic caps remain current. Evidence: .github/workflows/ci.yml, tools/ci_plan.py, regression_inventory.json, ci_diagnostics.py. |
| `docs/compiler-differential.md` | Reviewed; current | Function-level grammar, BEAM oracle, bounded shrinking and optional RTL scope remain current. Evidence: tools/compiler_differential.py, compiler_differential_cases.py, test_compiler_differential.py. |
| `docs/control-flow.md` | Updated | Retained-server failure differs from immediate zero-state behavior; build validation and runtime catalog binding separated. Evidence: xls_gs_deferred, xls_failure_sites, xls_emitted, hls_debug_catalog. |
| `docs/debug-protocol.md` | Updated | Profile-only transport mode does not install a recorder; fixed debug packet/trace limits remain independent of ordinary actor capacity. Evidence: test/rtl/xls_sim_bridge.c, hls_debug runtime codecs, debug RTL. |
| `docs/debug-targets.md` | Updated | Documents retained runtime hardware/bind APIs and source-validating compiler convenience separately. Evidence: hls_debug_catalog:hardware/3, bind/3 and xls_actor_debug:catalog/3. |
| `docs/entry-outcomes.md` | Updated | Payload bound follows selected frame layout; transactional entry/order/path limits unchanged. Evidence: xls_statem_entry and xls_actor_codegen. |
| `docs/expression-ir.md` | Updated | Structured entries finalize through artifact/3, with emit/3 the IO-data wrapper. Evidence: xls_dslx, xls_clause_lower, xls_actor_codegen. |
| `docs/fabric-routing.md` | Reviewed; current | Physical packet-router ownership, service/host fixture and verification scopes remain current. Evidence: priv/rtl/fabric, tools/test_fabric_router.py, test_fabric_services.py, CI workflow. |
| `docs/formal-contracts.md` | Reviewed; current | Evidence taxonomy, assumptions and bounded snapshot statement remain current. Evidence: tools/test_actor_snapshot_formal.py and repository review policy; no new proof asserted. |
| `docs/host-transactions.md` | Updated | Identifies hls_runtime broker versus downstream application and moved Phi runner/CPU model. Route lifetime, limits and closure contract checked against hls_fabric runtime. |
| `docs/incremental-xls-builds.md` | Reviewed; current | Compiler-owned executor, flat/bundle adapters, frozen options and immutable release semantics remain current. Evidence: priv/tools/compile_xls.py, compile_source_build.py and executor tests. |
| `docs/indexed-gathers.md` | Reviewed; current | Capacity, membership, pending-event order, no-value observation and finite witnesses remain current. Evidence: hls_statem, xls_statem_gather_lower, statem_gathers case. |
| `docs/initialization.md` | Updated | Replaces stale source-banner claim and incorrect same-route/new-session guidance. Evidence: xls_init, xls_emitted, hls_fabric route retirement/closure. |
| `docs/local-helpers.md` | Updated | Uses compiler-owned telemetry-style arithmetic instead of removed Phi/Pauli source. Closure, scope and finite helper validation remain current. Evidence: xls_hardware_source, xls_helpers, telemetry_calibrator. |
| `docs/mixed-topologies.md` | Updated | Explicit statem-only dedicated topology, complete physical-profile fields and executable telemetry pointer. Removes scheduler-group startup policy from compiler contract. Evidence: hls_actor_interface, xls_topology_profile, xls_topology_dslx. |
| `docs/numeric-contract.md` | Updated | Selected frame bounds; custom-provider domain ownership; retained codec is runtime-owned. Numeric/bit/record rules retain their existing witnesses. Evidence: hls_type, hls_record_codec, hls_frame_layout, xls_struct_codec. |
| `docs/optimization.md` | Reviewed; current | Review method distinguishes semantics, generated dependencies and physical measurement; no changed APIs or new measurement claim. Evidence: STYLE.md and formal-contracts.md. |
| `docs/profiling.md` | Updated | Explicit capture prerequisite, memory/retention limits, timestamp bound, window endpoints and analysis options. Evidence: tools/erl_hls_tools/hls_profile.py validate/window/main and verify_perfetto_profile.py. |
| `docs/repetition-code.md` | Updated | Points to maintained hls_phi package and coordinated Phi walkthrough; telemetry owns compiler-only teaching path. Evidence: merged application move, src/examples/telemetry. |
| `docs/retained-replies.md` | Reviewed; current | Pending-call, continuation and failure semantics plus fixed ownership-storage formula remain current. Evidence: hls_reply_book, xls_gs_deferred, xls_statem_reply_codegen and retained-reply fixtures. |
| `docs/serial-counters.md` | Reviewed; current | Modulo packing and half-range ordering assumptions remain current. Evidence: apps/hls_runtime/src/api/hls_serial.erl, priv/xls/lib/hls_serial.x and serial regression. |
| `docs/service-contracts.md` | Updated | Removes retired full-decoder compiler-CI claim. Embedded contracts and immediate/retained failure distinction remain current. Evidence: hls_service_schema, hls_service_contract, service_contracts case and CI workflow. |
| `docs/source-context.md` | Updated | Current structured preprocessing diagnostics replace old raw tuple. Context/include/source-summary limits remain current. Evidence: hls_source, hls_pack, hls_actor_interface and source_context case. |
| `docs/source-quality.md` | Reviewed; current | Formatting, source contracts, migration and package-audit commands remain current. Evidence: rebar.config, check_source_contracts.py, check_package_boundaries.py and source-quality workflow. |
| `docs/toolchain.md` | Updated | Executable release/help/emit entry points, codebook sidecar, frame option and downstream scheduling authority. Evidence: hls_compile_cli, hls_compile, hls_artifact_bundle, release templates and external executor. |
| `docs/topology-debug.md` | Updated | Corrects fixed-member observation and wide-mask unavailable fields. Wrapper, finite-query and coherence scope remain current. Evidence: hls_topology_debug, xls_actor_observation, topology_debug.py. |
| `docs/topology-query-format.md` | Reviewed; current | Fixed query schema, snapshot bits and live/RAM projection are separate from ordinary frame layout. Evidence: hls_topology_debug runtime decoder and priv/rtl/debug/hls_topology_debug.v. |
| `docs/type-providers.md` | Reviewed; current | Host/compiler companions, custom extension and non-pinned retained-codec semantics remain current. Evidence: runtime hls_type/hls_record_codec and compiler xls_type/xls_provider_*. |
| `src/README.md` | Updated | Adds telemetry to ownership map and makes generated-fixture path repository-relative. Evidence: source tree and rebar application definitions. |
| `src/backend/README.md` | Reviewed; current | Backend versus frontend/runtime responsibility remains current. Evidence: source layout and module imports. |
| `src/backend/xls/README.md` | Reviewed; current | Shallow actor/analysis/emission/expression/topology/type ownership remains current. Evidence: matching subdirectories. |
| `src/backend/xls/actors/README.md` | Reviewed; current | Dedicated actor preparation/emission/debug ownership remains current. Evidence: xls_parse callers and actor module exports. |
| `src/backend/xls/analysis/README.md` | Reviewed; current | Source-closure, plan and fact-analysis boundary remains current. Evidence: analysis module exports and xls_actor_program. |
| `src/backend/xls/emission/README.md` | Reviewed; current | Target structure, names, imports and final failure allocation remain current. Evidence: xls_dslx/xls_emitted/xls_failure_sites. |
| `src/backend/xls/expressions/README.md` | Reviewed; current | Clause-state and expression collaborators remain current. Evidence: xls_clause_lower and local header imports. |
| `src/backend/xls/topology/README.md` | Reviewed; current | Checked dedicated topology preparation/rendering and profiles remain current. Evidence: xls_topology_dslx and topology module exports. |
| `src/backend/xls/types/README.md` | Reviewed; current | Compiler provider/record/frame renderers versus runtime widths/codecs remain current. Evidence: xls_type mapping and hls_runtime APIs. |
| `src/examples/README.md` | Reviewed; current | Small compiler fixtures and telemetry are distinguished from downstream decoder applications. Evidence: maintained example directories. |
| `src/examples/packed_samples/README.md` | Updated | Replaces obsolete generic api/backend paths with current runtime/compiler links. Evidence: packed_samples source and package map. |
| `src/examples/regsvc/README.md` | Updated | Replaces obsolete generic api/runtime paths with current runtime/compiler links. Evidence: regsvc source, RTL fixtures and package map. |
| `src/examples/telemetry/README.md` | Reviewed; current | Complete project, signed arithmetic, host pacing, source-bundle commands and finite RTL scope remain current. Evidence: telemetry.erl, actor/header/topology sources, telemetry_example_tests and local regression case. |
| `src/frontend/README.md` | Reviewed; current | Parse transforms/source validation remain compiler-owned while emitted codecs use runtime APIs. Evidence: hls_pack, hls_records, hls_actor_interface. |
| `src/toolchain/README.md` | Reviewed; current | CLI, source bundles and external tool boundary remain current. Evidence: hls_compile_cli, hls_compile, hls_artifact_bundle. |
| `src/topology/README.md` | Reviewed; current | Logical normalization stays separate from physical rendering and runtime routes. Evidence: hls_topology and backend/runtime consumers. |

## Local validation

The packaged release was built from the reviewed source and its documented `hlsc --help`, `hlsc emit` of `regsvc`, and `compile-source-build --dry-run` commands passed. The preview verifies the source bundle and actual tool/library hashes without executing XLS. Thirteen existing profile-renderer tests pass, as do formatting, Dialyzer, 26 source-checker tests and four package-auditor tests. The source audit reports 3,348 inherited gaps with zero new/changed gaps; all 37 runtime modules pass the package boundary check.

Both repositories' public-guide links and local heading anchors are checked together, including owned cross-repository GitHub paths resolved against these checkouts. External websites are not fetched. The changed source is Markdown only; no dependency, algorithm or CI policy changes are included. Evidence and the fresh source bundle are retained outside Git under `hls_artifacts/runs/erlang-local-cells-2026-10-16/post-campaign-cleanup-42/`.
