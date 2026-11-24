# Documentation currency audit

Reviewed against fabric `e735f6d` plus this documentation-only revision and the selected compiler source. This is a read-only source/API/path review, not new runtime, RTL or physical evidence. Existing experimental measurements retain their original scope and archive keys. Root README and documentation navigation now point to the maintained Phi walkthrough.

The cross-checks use the current `hls_build`/`hls_source_build`/`hls_scheduler_build` paths, retained `xls_protocol_network` and scheduler plans, `hls_build_profile`, runtime envelope/partition codecs, selected compiler tools/assets, application manifests and `tools/hls_fabric/ci.sh`. In particular, ordinary actor frames are configurable; application/bridge envelopes and existing capture decoders have separately checked limits. Profiling rendering does not imply a general capture interface or a live-device trace facility.

## Guide inventory

Every existing `docs/**/*.md` and application Markdown guide is listed below. “Retained” means reviewed with no change required; it does not claim independently rerun examples. The new walkthrough is included separately from the original 59-file inventory.

| Guide | Disposition | Review outcome |
| --- | --- | --- |
| [apps/README.md](../../apps/README.md) | Retained | Build/runtime/example application boundaries match the current app manifests. |
| [apps/hls_lowering/README.md](../../apps/hls_lowering/README.md) | Retained | Planning/build-library role and exclusions match current ownership. |
| [apps/hls_lowering/priv/rtl/README.md](../../apps/hls_lowering/priv/rtl/README.md) | Retained | Shared shipped support is distinguished from application shells and platform RTL. |
| [apps/hls_lowering/src/README.md](../../apps/hls_lowering/src/README.md) | Corrected | Restricted lowering examples to the tiny counter; decoder ownership belongs to separate applications. |
| [apps/hls_lowering/src/backend/README.md](../../apps/hls_lowering/src/backend/README.md) | Retained | Retained plans, backend rendering and source artifacts match current modules. |
| [apps/hls_lowering/src/backend/sv/README.md](../../apps/hls_lowering/src/backend/sv/README.md) | Retained | SystemVerilog shell role and incomplete board-design boundary remain explicit. |
| [apps/hls_lowering/src/backend/xls/README.md](../../apps/hls_lowering/src/backend/xls/README.md) | Retained | XLS generator entry points and retained failure metadata remain current. |
| [apps/hls_lowering/src/examples/README.md](../../apps/hls_lowering/src/examples/README.md) | Retained | Only the small counter belongs to the lowering library. |
| [apps/hls_lowering/src/examples/counter/README.md](../../apps/hls_lowering/src/examples/counter/README.md) | Retained | Public source/scheduler configuration paths remain current. |
| [apps/hls_lowering/src/planning/README.md](../../apps/hls_lowering/src/planning/README.md) | Retained | Planner responsibilities and runtime exclusions match current modules. |
| [apps/hls_lowering/src/toolchain/README.md](../../apps/hls_lowering/src/toolchain/README.md) | Corrected | Distinguished the counter entry from decoder application packages. |
| [workloads/hls_phi/README.md](../../workloads/hls_phi/README.md) | Retained | Optional example release, host entry points and deployment limits remain current. |
| [workloads/hls_phi/include/README.md](../../workloads/hls_phi/include/README.md) | Retained | Application records and geometry-specific macros retain their stated ownership. |
| [workloads/hls_phi/priv/README.md](../../workloads/hls_phi/priv/README.md) | Retained | Provider and shell assets are resolved from the example application. |
| [workloads/hls_phi/priv/rtl/README.md](../../workloads/hls_phi/priv/rtl/README.md) | Retained | Application shells remain separate from shared support and board pins/clocks. |
| [workloads/hls_phi/src/README.md](../../workloads/hls_phi/src/README.md) | Retained | Application source, topology and driver entry points remain current. |
| [workloads/hls_phi/src/phi_phenom_topology.md](../../workloads/hls_phi/src/phi_phenom_topology.md) | Corrected | Corrected relative links after application relocation. |
| [workloads/hls_phi/test/README.md](../../workloads/hls_phi/test/README.md) | Retained | Application-specific semantics and finite witness ownership remain current. |
| [workloads/hls_phi/test/rtl/README.md](../../workloads/hls_phi/test/rtl/README.md) | Retained | Application benches are correctly separated from shipped support and platform probes. |
| [workloads/hls_phi/test/rtl/debug/README.md](../../workloads/hls_phi/test/rtl/debug/README.md) | Retained | Public debug-wire witness scope and driver path remain current. |
| [workloads/hls_phi/tools/README.md](../../workloads/hls_phi/tools/README.md) | Retained | Checkout-only measurement drivers and dedicated graph check remain current. |
| [workloads/hls_snowflake/README.md](../../workloads/hls_snowflake/README.md) | Retained | Common source build, example-release closure, finite oracle and experimental alternatives remain current. |
| [workloads/hls_snowflake/include/README.md](../../workloads/hls_snowflake/include/README.md) | Retained | Shared application actor records/macros remain correctly located. |
| [workloads/hls_snowflake/priv/README.md](../../workloads/hls_snowflake/priv/README.md) | Retained | Installed application fixture ownership remains current. |
| [workloads/hls_snowflake/priv/fixtures/README.md](../../workloads/hls_snowflake/priv/fixtures/README.md) | Retained | Named finite corpus ownership and provenance remain current. |
| [workloads/hls_snowflake/reference/README.md](../../workloads/hls_snowflake/reference/README.md) | Corrected | Corrected the reference generator invocation after relocation. |
| [workloads/hls_snowflake/src/README.md](../../workloads/hls_snowflake/src/README.md) | Retained | Ordinary actors, reference model and separate experiment tools remain correctly distinguished. |
| [workloads/hls_snowflake/test/README.md](../../workloads/hls_snowflake/test/README.md) | Retained | Local semantic checks and the one small source-protocol integration remain correctly scoped. |
| [docs/README.md](../../docs/hls_fabric/README.md) | Corrected | Added maintained Phi source-to-runtime navigation. |
| [docs/actor-pids.md](../../docs/hls_fabric/actor-pids.md) | Corrected | Scoped the 96-bit bound to the scheduled-PID gateway; general actor layouts are configurable. |
| [docs/admission-reductions.md](../../docs/hls_fabric/admission-reductions.md) | Retained | Admission credit/reduction contract and bounded evidence remain current. |
| [docs/application-streams.md](../../docs/hls_fabric/application-streams.md) | Corrected | Separated fixed rectangle limits, selected ordinary layout and framed-builder admission; fixed activation RTL owner. |
| [docs/artifacts.md](../../docs/hls_fabric/artifacts.md) | Retained | External archive lookup keys intentionally retain historical paths; they are not live checkout references. |
| [docs/building.md](../../docs/hls_fabric/building.md) | Corrected | Documented framed-builder limits and separated the optional scheduled Snowflake experiment from the ordinary source build. |
| [docs/ci.md](../../docs/hls_fabric/ci.md) | Retained | Current two-integration, localized-component and manual-trigger coverage matches tools/hls_fabric/ci.sh. |
| [docs/clock-domains.md](../../docs/hls_fabric/clock-domains.md) | Retained | Shared RTL owner, digital witness scope and pending physical CDC/PHY requirements remain explicit. |
| [docs/device-bridge.md](../../docs/hls_fabric/device-bridge.md) | Corrected | Derived scheduler crossing/packet widths from the selected layout and replaced stale CI/actor ownership claims. |
| [docs/device-sessions.md](../../docs/hls_fabric/device-sessions.md) | Retained | Session ownership, reconnection and failure boundaries match runtime modules. |
| [docs/distributed-memory.md](../../docs/hls_fabric/distributed-memory.md) | Corrected | Replaced former CI-matrix claims with the current D2 coalesced ordinary-reduction integration; kept larger evidence scoped. |
| [docs/exclusive-collections.md](../../docs/hls_fabric/exclusive-collections.md) | Retained | Collection ownership and capacity contracts remain current. |
| [docs/execution/README.md](../../docs/hls_fabric/execution/README.md) | Corrected | Updated package checkouts, frame configuration, retained scheduler-plan flow, common profile owner and platform/application ownership. |
| [docs/execution/actor-outboxes.md](../../docs/hls_fabric/execution/actor-outboxes.md) | Retained | Credited publication semantics and optional finite witness remain current. |
| [docs/execution/actor-reductions.md](../../docs/hls_fabric/execution/actor-reductions.md) | Corrected | Repaired the aggregate mux link to the generic retained DSLX module. |
| [docs/execution/debug-targets.md](../../docs/hls_fabric/execution/debug-targets.md) | Corrected | Selected the shared scheduler profile required by the RAM-debug example. |
| [docs/execution/initialization.md](../../docs/hls_fabric/execution/initialization.md) | Corrected | Marked the larger fixture optional and resolved compiler RAM support through the selected dependency. |
| [docs/execution/mixed-topologies.md](../../docs/hls_fabric/execution/mixed-topologies.md) | Retained | Placement, shared effect routing and optional mixed witnesses remain current. |
| [docs/execution/phi-walkthrough.md](../../docs/hls_fabric/execution/phi-walkthrough.md) | Added | Source-backed N6/3+3 walkthrough from application through plan, bundle, XLS, attachment, feedback and collective retirement. |
| [docs/execution/repetition-code.md](../../docs/hls_fabric/execution/repetition-code.md) | Corrected | Distinguished the dedicated application profile from the shared scheduler placement profile. |
| [docs/execution/scheduler-pipeline.md](../../docs/hls_fabric/execution/scheduler-pipeline.md) | Retained | RAM-safe tool requirement and pipeline witness scope remain current. |
| [docs/execution/topology-debug.md](../../docs/hls_fabric/execution/topology-debug.md) | Corrected | Resolved diagnostic tools and RTL through the selected compiler and documented retained projection inputs. |
| [docs/execution/zynq-ps-probe.md](../../docs/hls_fabric/execution/zynq-ps-probe.md) | Corrected | Identified the explicit platform regression as outside routine CI. |
| [docs/indexed-collections.md](../../docs/hls_fabric/indexed-collections.md) | Retained | Indexed storage and retained scheduler binding contracts remain current. |
| [docs/locality-baseline.md](../../docs/hls_fabric/locality-baseline.md) | Retained | Measurement scope and retained historical evidence remain appropriately bounded. |
| [docs/partitioned-reductions.md](../../docs/hls_fabric/partitioned-reductions.md) | Retained | Partitioned reduction ownership and finite evidence remain current. |
| [docs/profiling.md](../../docs/hls_fabric/profiling.md) | Corrected | Separated reusable rendering from private scheduler-specific capture; stated fixed default-width message reconstruction and source-protocol limits. |
| [docs/return-contexts.md](../../docs/hls_fabric/return-contexts.md) | Retained | Return-context ownership and supported transformation boundary remain current. |
| [docs/source-protocol.md](../../docs/hls_fabric/source-protocol.md) | Corrected | Updated configurable ordinary ABI, fixed bridge envelope, retained planning/emission flow, one transport commit, application ownership and optional integration scope. |
| [docs/source-quality.md](../../docs/hls_fabric/source-quality.md) | Retained | Current moved-source, package/application boundary, formatting and contract procedures match tools/rebar configuration. |
| [docs/state-specialization.md](../../docs/hls_fabric/state-specialization.md) | Retained | Build-time specialization boundary and retained layout claims remain current. |
| [docs/tiles.md](../../docs/hls_fabric/tiles.md) | Retained | Explicit mesh experiment and capacity/timing limitations remain current. |

## Local validation

The example release was built from the real pinned compiler/runtime dependencies. The exact `hls-repetition --width 6 --split 3` source emission, both CLI help commands, retained summary/placement/schedule views and external compilation dry-run all pass. The dry-run verifies actual input/tool/library hashes without executing XLS. Seventeen existing host-loop/relay tests pass, as do 30 source-checker tests, the application-boundary audit and Dialyzer. The audit reports 289 inherited contract gaps with zero new/changed gaps.

The reviewed compiler and fabric guide inventories receive a joint relative-link/heading check; owned cross-repository GitHub paths resolve against the matching local checkout. Historical artifact keys remain historical, and external websites are not fetched. Larger optional profiling, multi-board and physical examples were checked against their entry points rather than rerun for a documentation change. Runtime release/package and formatting checks are also retained with the command evidence under `hls_artifacts/runs/erlang-local-cells-2026-10-16/post-campaign-cleanup-42/`.
