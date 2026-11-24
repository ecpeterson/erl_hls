# Umbrella OTP Stages 0–5 audit (Stage 5 in progress)

Stage 0 closed on 2026-11-23 with validated filters and no imported history. Stage 1 then imported those filtered histories and landed the selected 390 modules as nine OTP applications without changing their application boundaries. Commit `f92f8b0` completed the application-seam preflight, and `6b1246c` completed Stage 2 by extracting a process-free `hls_core` and making its semantic model authoritative across the umbrella. Commit `8bdbfb0` completed the Stage 3 ownership redraw. Commit `d44618a` completes Stage 4 by separating canonical deployed-execution artifacts and runtime packaging from compilation. Stage 5 has completed the identity-bound feedback capability and its finite routed witness; final immutable-revision qualification and canonical remote cutover remain open. The [source inventory](umbrella-otp-inventory.md) remains the historical record of the original 330-module, eight-application feature-branch audit and its selected-mainline reconciliation.

## Import selection

The initial audit used the in-progress feature checkouts below. The untracked Fabric experiment tree was not an audit input and remains untouched.

| Repository | Audited feature revision | Relation to selected mainline |
| --- | --- | --- |
| erl_hls (local directory erl_xls) | `a9198df1705a8eb313d20e78871ed53225488f15` | Feature work is merged; selected mainline has 18 additional commits and the feature has one merge-only commit. |
| hls_fabric | `131bd191d39011253e6b86e496c86f1080dfc678` | Feature work is merged; selected mainline has 25 additional commits and the feature has three merge-only commits. |
| hls_spacetime | `efee619df1b37c3e11e0496d2eabc4231ce84623` | The audited tree is an ancestor-equivalent input; selected mainline adds merge and documentation history. |

Current `origin/main` tips were fetched before selection.

| Repository | Selected revision | Production modules | Selected applications |
| --- | --- | ---: | --- |
| erl_hls | `b86502cc0149731409d878f9aec6c5264ae3f2eb` | 151 | erl_hls, hls_runtime |
| hls_fabric | `4481afbde5a4ab1594141d698c74e0859ef8c72c` | 229 | hls_fabric, hls_lowering, hls_phi, hls_snowflake, hls_spacetime_observer, router |
| hls_spacetime | `3597ecf93ea789c745bc3014ea2c4de8cd5fb243` | 10 | hls_spacetime |

The selected trees contain 390 literal production-module identities and no duplicate module names or gitlinks. Relative to the retained 330-module audit, 64 identities were added and four were removed. The inventory records the exact delta. The selected Fabric revision pins compiler/runtime revision `ef0b280728671e49c79b5cecc13150f92754a41a` and optional spacetime revision `c2b0c328d095fa8410231a9120c1298393ae2e31`; standalone baseline tests therefore still exercise those declared revisions rather than the selected import tips.

## Stage 1 application graph and ownership

Edges omit stock OTP applications.

| Application | Project dependencies | Responsibility retained for the mechanical merger |
| --- | --- | --- |
| hls_runtime | — | Runtime values, codecs, domains and actor lifecycle |
| erl_hls | hls_runtime | Source analysis, compiler interfaces and XLS lowering/emission |
| hls_fabric | hls_runtime | Deployed nodes, sessions, transport and device protocols |
| hls_lowering | erl_hls, hls_runtime, hls_fabric | Multi-actor build, topology and deployment-plan elaboration |
| hls_phi | erl_hls, hls_runtime, hls_fabric, hls_lowering | Phi examples and application-specific assembly |
| hls_snowflake | hls_runtime, erl_hls, hls_fabric, hls_lowering | Snowflake examples and application-specific assembly |
| hls_spacetime_observer | hls_runtime, erl_hls, hls_lowering, hls_spacetime | Translation of observations into offline evidence |
| router | — | Standalone routing and barrier application |
| hls_spacetime | — | Offline evidence reconstruction, latency models and viewer |

The Stage 2 preflight declares Snowflake's direct compiler use and the observer's direct compiler/runtime use. Every compiled import and remote type edge between the nine applications is now declared by its caller. These declarations make the mechanical baseline honest; they do not ratify the current application boundaries as the target architecture.

## Retained-path and history manifest

The compiler repository remains the base history. The other two selected histories were filtered into collision-free staging prefixes and then mechanically landed according to this manifest. The landing set contains 2,716 paths and has zero path collisions.

| Source | Filtered staging | Final landing |
| --- | --- | --- |
| erl_hls | Base history is unchanged. | `src/`, `include/`, `priv/`, `test/`, `test_data/` and `attic/` move under `apps/erl_hls/`; `apps/hls_runtime/` remains; root build, CI, documentation, tool and working-note paths remain umbrella-owned. |
| hls_fabric | Retained paths are prefixed with `imports/hls_fabric/`. The entire historical `experiments/` prefix and `apps/hls_snowflake/reference/scaling_fixtures.py` are excluded. | Root `src/`, `include/`, `test/` and `test_data/` land under `apps/hls_fabric/`; existing `apps/*`, `platforms/*` and `bin/*` retain their paths; `docs/*`, `tools/*` and `yap/*` land under `docs/hls_fabric/`, `tools/hls_fabric/` and `yap/hls_fabric/`; README, license, style and agent-policy files land under `apps/hls_fabric/`. |
| hls_spacetime | Retained paths are prefixed with `imports/hls_spacetime/`. | `src/`, `priv/`, `test/`, `test_data/`, `web/`, `test-js/`, `scripts/`, package metadata, README, licenses, notice and style policy land under `apps/hls_spacetime/`; `docs/*` and `yap/*` land under `docs/hls_spacetime/` and `yap/hls_spacetime/`. |

Fabric `.github/`, root Git attributes/ignore, Rebar configuration/lock and source-contract baseline, and spacetime root Git ignore and Rebar configuration/lock, were compared and merged into umbrella controls. Their staging copies were removed after integration; their filtered history remains reachable.

Fabric commit `e735f6d` moved maintained product paths out of historical experiment locations:

- XC7 product material moved to `platforms/xc7/`.
- Snowflake actors, Erlang sources, fixtures and references moved to `apps/hls_snowflake/`.

The filter deliberately removes the earlier experiment-prefixed history, so these retained paths begin at the migration commit. Current XC7 packaging provenance strings, the tracked timing archive input and recorded historical artifact metadata are retained because they are self-contained product inputs or records; none reads from the excluded tree.

The Snowflake scaling workflow is resolved by keeping `apps/hls_snowflake/reference/scaling_fixtures.py`, its excluded-tree dependency, its fixtures and its history external with the experiments. The filtered Snowflake reference README says that the scaling workflow and fixtures remain in the external experiment repository. The independent maintained Erlang phase-witness helper and test, and all other Snowflake product fixtures and reference scripts, remain.

One retained working note named an excluded private consumer. The filtered blob replaces that identifier with `external consumer`. The selected filtered histories contain no excluded consumer identifier, code, fixtures, artifacts, dependency details or commit-message reference.

## Filter validation and commit mappings

`git-filter-repo` 2.47.0 was installed only in a temporary directory and run against disposable clones. The complete filter was repeated from fresh clones. Both runs produced identical commit and tag mappings.

The Fabric filter retained only a synthetic `import-main` ref at the selected revision and tag `xls-ram-9f360fc89-05a16983`, removed every `experiments/` path and every version of the scaling script, prefixed the result with `imports/hls_fabric/`, replaced the trailing scaling-controls README section with the external-workflow notice, and replaced the excluded consumer identifier in the one retained note. The spacetime filter retained the selected mainline ref and prefixed every path with `imports/hls_spacetime/`. The compiler ref was not rewritten.

| Source ref | Filtered ref |
| --- | --- |
| erl_hls `b86502cc0149731409d878f9aec6c5264ae3f2eb` | Identity base: `b86502cc0149731409d878f9aec6c5264ae3f2eb` |
| hls_fabric `4481afbde5a4ab1594141d698c74e0859ef8c72c` | `878b44269266d6f2c33f844c4aa5eff4d6dd3936` |
| hls_fabric tag `xls-ram-9f360fc89-05a16983`, target `d2b611297ffbddb5d7e4a106a57a1ed4457ccb40` | Tag target `4e3f1dd15c403d5d0b9f7087ae6dc039579437be` |
| hls_spacetime `3597ecf93ea789c745bc3014ea2c4de8cd5fb243` | `83f19aa922623a5b5bea46176fb0baee1d28c5a4` |

Fabric history has 99 retained commits from 107 selected reachable commits; eight experiment-only commits disappear. Spacetime retains all 47 selected reachable commits. Validation established:

- Selected-tip path sets exactly equal their source trees after the declared exclusions and staging prefixes.
- Every retained blob is byte-identical except the two deliberate Fabric documentation redactions: the scaling README section and the excluded-consumer reference.
- No reachable path escapes its staging prefix; no excluded path, gitlink or excluded consumer identifier occurs in reachable trees, blobs or commit messages.
- The spacetime path and blob set is exact aside from its staging prefix.
- `git fsck --strict` passes after reflog expiration and garbage collection.
- Applying the final landing rules yields 2,716 unique paths and zero collisions.

These hashes validate the filter specification used for the actual import. Commit `4f84e4d` merges the filtered Fabric tip, `b8e7137` merges the filtered spacetime tip, and `0ed0d67` lands both staging trees in their final umbrella paths. The retained tag resolves to `4e3f1dd15c403d5d0b9f7087ae6dc039579437be`. The filtered refs and tag are ancestors of the Stage 1 branch; their original unfiltered source objects are absent. All 16 staging-control files are deleted from the final tree.

## Regression baseline

The baseline used OTP 28.0.2, ERTS 16.0.2 and Rebar3 3.24.0.

| Check | erl_hls selected mainline | hls_fabric selected mainline | hls_spacetime selected mainline |
| --- | --- | --- | --- |
| `rebar3 fmt --check` | Pass | Pass | Pass |
| Compile and EUnit | Pass; 1,290 tests | Pass; 1,390 default tests and 1,467 fresh-clone `spacetime` profile tests | Pass; 155 tests |
| `rebar3 dialyzer` | Pass | Pass in default and `spacetime` profiles | Pass |
| Source contracts | 26 checker self-tests pass; 442 files, 3,279 inherited gaps, zero new/changed | 30 checker self-tests pass; 630 files, 289 inherited gaps, zero new/changed | Compiler checker reports 18 files and zero findings |
| Package boundaries | Four checker self-tests pass; 49 runtime modules, zero violations | 322 library modules, zero example dependencies; assembled release has 97 runtime modules and zero violations | Not applicable to the standalone escript |
| Artifact assembly | `rebar3 release` passes with the existing SASL-upgrade warning | `rebar3 release -n hls_fabric` passes with the same warning | `rebar3 escriptize` passes |

The exact previously blocked feature revisions were also rerun outside the Work sandbox: Fabric passes all 1,135 default and 1,147 spacetime-profile EUnit tests, including the 21 TCP-distribution listener cases; spacetime JavaScript passes all 574 cases, including both HTTP listener cases. On the selected Fabric mainline, reusing one checkout after the default suite once produced an exclusive-create collision in generated `_build/test/recovery-application-*` state. The exact ref passed all 1,467 profile tests in a fresh clone, identifying this as a checkout-reuse harness hazard rather than a listener or product failure.

Additional selected-mainline checks pass: the spacetime C++17 trace-transport round trip and 12 rejection cases, and all 14 route-hash worker Python tests. Network access was required once to resolve the optional Fabric spacetime profile; its Dialyzer run then analyzed 229 files and passed.

## Stage 1 mechanical umbrella

The default project contains `erl_hls`, `hls_runtime`, `hls_fabric`, `hls_lowering`, `hls_phi`, `hls_snowflake` and `router`. The `spacetime` profile adds `hls_spacetime` and `hls_spacetime_observer`. Root `{deps, []}` replaces every project cross-checkout pin with umbrella application resolution. The compiler application keeps its ordered first-file configuration; the root release configuration keeps separate compiler, build-tool, examples and deployed-runtime closures. The existing Fabric CI workflow and local actions are integrated at the umbrella root.

Tool, fixture, documentation, release-overlay and application-resource paths were adjusted mechanically for their new roots. The root source-contract checker owns the combined tree and preserves inherited gaps by unique module identity; duplicate test-only module names remain scoped to their original applications. `tools/test_umbrella_eunit.sh` creates fresh temporary application projections so those private fixtures are tested without renaming them or co-loading colliding test modules. Fresh roots also avoid the previously observed generated recovery-state collision.

Static integration checks find nine application descriptors, 390 production modules, zero duplicate production module names, zero active project dependency pins, zero tracked excluded-tree paths, zero excluded private-consumer references, zero physical staging files and zero broken source-tree symlinks. Filtered Fabric and spacetime histories retain 99 and 47 commits respectively. `git fsck --strict --no-dangling` passes. Maintained literal command targets and relative links under the imported Fabric, platform and working-note trees all resolve; historical archive keys remain records rather than runnable checkout links.

The combined qualification used OTP 28.0.2 and Rebar3 3.24.0.

| Check | Stage 1 result |
| --- | --- |
| Fresh compile | Default seven-application build passes; the `spacetime` nine-application profile passes. |
| EUnit | Compiler projection: 1,290/0; default Fabric projection: 1,390/0; Fabric `spacetime` projection: 1,467/0; standalone spacetime projection: 155/0. |
| Dialyzer | Default passes over 371 project files; `spacetime` passes over 390 project files. |
| Source contracts | 33 checker tests pass; 1,080 files report 3,544 inherited gaps and zero new or changed gaps. |
| Package boundaries | Four checker tests pass; runtime source 49/0, application graph 327 modules/zero example dependencies, and assembled runtime release 98/0. |
| Artifact assembly | All four named releases pass and expose executable launchers; the spacetime escript builds and its four-command help contract runs. |
| Relocated toolchains | Compiler release tests pass 5/5; Fabric build and examples release tests pass 3/3 using mock external tools. |
| Spacetime front ends | JavaScript passes 574/574 with loopback access; native C++ trace transport passes its round trip and 12 rejection cases; route-hash Python tests pass 14/14. |
| Formatting and hygiene | Root formatting, shell syntax, Python syntax, YAML parsing, `git diff --check` and the focused command/link audit pass. |

Additional bounded Python and CI-policy inventories pass: 175 unit cases, 16 backend/import-policy cases, nine platform packaging mocks, seven root CI-recipe cases and the XLS RAM installer case. These are tool-orchestration witnesses, not native XLS or RTL equivalence.

The restricted Work sandbox still rejects local listeners: the Fabric projection had 30 listener-only failures there, and JavaScript had two HTTP-listener failures. The same final projections pass completely with loopback access as recorded above. One immediate repeat of the compiler projection during harness development hit the timing-sensitive abrupt-device-death lease test; the fresh final compiler projection passes all 1,290 cases. This remains a retained transient rather than a strengthened timing claim.

Release assembly must name one of the four configured releases; bare `rebar3 release` correctly rejects the ambiguous selection. Each named release retains the existing warning that SASL is absent, so it is not upgrade-capable. A stale pre-relocation `_build/default` initially produced missing-source warnings and obsolete beams; moving that generated cache aside and rebuilding from scratch removed them. Fresh releases contain the expected 102 compiler source files.

## Stage 2 application-seam preflight

The compiled dependency audit now treats every direct project-application BEAM import and remote type as a manifest edge. It checks the seven default applications and all nine applications in the `spacetime` profile while retaining the rule that generic compiler, runtime, Fabric, lowering and router libraries cannot depend on Phi or Snowflake. The combined default and spacetime snapshots inspect 761 modules and report zero missing applications, undeclared edges or reverse example dependencies.

Two manifest corrections make current executable dependencies explicit before semantic extraction:

- `hls_snowflake` now declares `erl_hls`. `snowflake_actor_run` and `snowflake_actor_topology` normalize compiler-owned topology values, `snowflake_actor_topology` writes compiler-owned emitted artifacts, and `snowflake_source` exposes the compiler topology type. Moving these calls behind the current lowering application would merely create a pass-through; Stage 3 will relocate or reshape compiler ownership deliberately rather than conceal the present edge.
- `hls_spacetime_observer` now declares `erl_hls` and `hls_runtime`. Its stream and publication planners compare compiler-owned packaged resources and frame configuration, then validate dimensions with the runtime-owned frame-layout API before translating observations. The manifest test records the two computed-resource owners independently of the current static imports.

Neither correction enlarges a configured release closure because `hls_lowering` already carried the same dependencies transitively.

Provider review found that `phi_field` and `hls_pauli` already implement both host-runtime and compiler-provider callbacks but declared only `hls_type`; both now also declare `xls_type`. All other production compiler providers already declared that behavior. Existing focused tests exercise both provider dispatch paths.

The preflight records the current authorities for runtime values, live protocols, deployment planning, compiler APIs, observer translation, routing and offline evidence. It did not test or reject semantic consolidation. Static dependency closure could not determine whether shared models belonged in `hls_core`, compiler machinery should move to `hls_compile`, physical adapters should move to `hls_target`, or existing application identities should be narrowed or retired. The shared-model decision is resolved below; the ownership redraw remains Stage 3 work.

Computed resource and tool/configuration review requires no immediate repair on the current graph. This validates the relocated packaging baseline only; later architectural stages may move toolchain adapters and their resources while preserving application-relative lookup. Production resources resolve through the owning application's `code:priv_dir/1`; the observer's variable application paths are exactly the newly declared owners plus its existing lowering, observer and spacetime dependencies. Production sources contain no repository-relative `apps/`, `tools/`, `_build/` or checkout-parent resource path. Root release overlays remain distinct, installed launchers self-locate, compiler-tool wrappers retain one implementation authority, and profile selection never falls back to another build. Focused backend isolation passes 16/16, relocated Fabric toolchain tests pass 3/3 and relocated compiler toolchain tests pass 5/5.

The software CI tier now compiles the `spacetime` profile before running one combined default/spacetime boundary audit. Seven package-auditor tests cover calls, remote types, release ownership, broad snapshots and computed observer resources; two CI-policy tests pin the profile compile and audit ordering. Both profile compiles, the 49-module compiler package boundary and the 98-module assembled Fabric runtime boundary pass. Source-contract checks retain 3,544 inherited gaps across 1,080 files and report zero new or changed gaps. Dialyzer passes over 371 default and 390 spacetime project files. Fresh listener-capable EUnit projections match the Stage 1 baseline: compiler 1,290/0, default Fabric 1,390/0, Fabric `spacetime` 1,467/0 and standalone spacetime 155/0. All four named releases and their launchers pass; the spacetime escript builds and exposes its four-command help contract. The retained SASL warning still means the releases are not upgrade-capable.

No seam-preflight check needs hardware, EC2 or another environment. This does not discharge the semantic, physical or external-consumer exit criteria of the restored campaign.

## Stage 2 common semantic model

Commit `6b1246c` adds the process-free `hls_core` application and completes the Stage 2 extraction without beginning the Stage 3 ownership redraw. The default profile now contains 375 production modules across eight applications; the optional `spacetime` profile contains 394 across ten. `hls_core` contains 30 production modules: 21 previously shared API, identity, codec and diagnostic modules, plus nine model authorities. The existing application boundaries and distinct computation, execution, communication, optimization and physical-implementation representations remain intact.

Edges below omit stock OTP applications. They describe the post-Stage 2 executable graph, not the tentative Stage 3 target architecture.

| Application | Project dependencies after Stage 2 |
| --- | --- |
| hls_core | — |
| hls_runtime | hls_core |
| erl_hls | hls_core, hls_runtime |
| hls_fabric | hls_core, hls_runtime |
| hls_lowering | hls_core, erl_hls, hls_runtime, hls_fabric |
| hls_phi | hls_core, hls_runtime, erl_hls, hls_fabric, hls_lowering |
| hls_snowflake | hls_core, hls_runtime, erl_hls, hls_fabric, hls_lowering |
| hls_spacetime | hls_core |
| hls_spacetime_observer | hls_core, hls_runtime, erl_hls, hls_lowering, hls_spacetime |
| router | — |

`hls_logical_identity`, `hls_process_interface` and `hls_logical_topology` are the shared authorities for logical actor identity, typed communication requirements and topology. The topology model supports compact families and bounded materialization of arbitrary ranks, including the maintained two-dimensional rectangle ingress form. Exact instances retain their family identity and provenance. The compiler's richer interface catalog now projects to this core representation and validates exact agreement instead of maintaining a parallel protocol topology.

The extraction also establishes shared implementation constraints and flag rendering, a host-codec and protocol-application contract, and exact source/RTL/observation provenance through `hls_observation_build`. Compiler backends, partitioning, Phi CPU execution, observations and debug catalogs consume the core catalog. Duplicate backend, partition, Phi and debug expansions and the former protocol-topology authority are removed. Runtime messages, device protocols, persisted artifacts and checked caches remain genuine boundaries rather than being collapsed into in-memory calls.

Partition plans now retain the authoritative process-interface catalog through device-local, scheduling and tiled derived plans. This changes deterministic partition-term fingerprints and associated metadata; stale generated partition artifacts must be rebuilt. Actor identities, encoded messages and emitted RTL are unchanged by that metadata retention. The internal `hls_partition_schedule:topology/1` helper consequently accepts the partition or local-plan map rather than a bare actor list; every in-tree caller is updated.

The [system model](../docs/system-model.md) distinguishes four layers: logical system, proposed implementation plan, realized implementation and measured characterization. This prevents planned placement or scheduling from being mistaken for realized hardware, and prevents either from being mistaken for measurement. Stage 5 can therefore feed measured timing and resource evidence back into a later plan without making that feedback part of the Stage 2 model.

The final qualification used OTP 28.0.2 and Rebar3 3.24.0.

| Check | Stage 2 result |
| --- | --- |
| Fresh compile and EUnit | Listener-capable fresh projections pass: compiler 1,307/0; default Fabric 1,394/0; Fabric `spacetime` 1,472/0; standalone spacetime 156/0. The distribution cases that fail with `nodistribution` in the restricted sandbox pass with loopback listener access. |
| Dialyzer | Default passes over 375 project files; `spacetime` passes over 394. |
| Source contracts | 33 checker tests pass. The changed-file comparison covers 1,087 files, reports 3,352 inherited gaps and zero new or changed gaps. Strict checks pass for the 12 new core model/test files and the changed actor-identity declaration. The unchanged API/support declarations moved into `hls_core` retain 157 previously recorded strict gaps, so the application is not claimed wholly documented. |
| Package boundaries | Eight package-checker tests pass. Core plus runtime contain 58 modules with zero violations; the assembled runtime release contains 105 with zero violations; combined default and optional-profile application snapshots inspect 769 project modules with zero violations. |
| Artifact assembly | All four named releases pass with the retained SASL-upgrade warning. The spacetime escript builds and its `validate`, `import`, `join` and `sdf-arcs` help contract runs. |
| Relocated toolchains | Compiler release tests pass 5/5 and Fabric build/examples release tests pass 3/3 with their maintained mock external tools. |
| Formatting and hygiene | Root formatting and both source/package checker suites pass; the committed diff passes whitespace validation. |

No native XLS, RTL, Vivado, EC2 or board run is required for this extraction because it changes no generated actor or wire semantics. That is a scoped architectural result, not native or physical equivalence evidence. The excluded experiment history and private external-consumer material remain outside the umbrella. No Stage 3 application extraction or ownership move is included.

## Stage 3 synthesis and optimization boundaries

Commit `8bdbfb0` redraws ownership around the seven-application architectural spine while retaining the four product, observer and router applications in the optional eleven-application profile:

- `hls_compile` owns computation synthesis: source analysis, compiler interfaces, XLS lowering and emission, logical topology construction, compiler headers and compiler DSLX support.
- `hls_fabric` owns process-free communication planning, protocol projections, logical routing renderers and Fabric DSLX/RTL. Live nodes, wires, sessions and transport processes moved to `hls_runtime`; that move is required for Fabric to be a synthesis library rather than a second runtime.
- `hls_target` replaces `hls_lowering` and owns target materialization, partition and scheduler implementation, physical/SDF characterization readers, RTL support and external tool adapters.
- `hls_spacetime` owns pure partition, schedule and plan revision over core implementation contracts and supplied characterization. It does not start target or runtime services.
- `hls_core` adds authoritative implementation-plan and characterization values. `erl_hls` retains supported façade, configuration and orchestration entry points rather than compiler internals.

Edges below omit stock OTP applications. The synthesis path is acyclic, and no core, compile, Fabric or target module depends on the optimizer or façade.

| Application | Project dependencies after Stage 3 |
| --- | --- |
| hls_core | — |
| hls_runtime | hls_core |
| hls_compile | hls_core, hls_runtime |
| hls_fabric | hls_core, hls_runtime, hls_compile |
| hls_target | hls_core, hls_runtime, hls_compile, hls_fabric |
| hls_spacetime | hls_core, hls_target |
| erl_hls | hls_core, hls_runtime, hls_compile, hls_fabric, hls_target |
| hls_phi, hls_snowflake | hls_core, hls_runtime, hls_compile, erl_hls, hls_fabric, hls_target |
| hls_spacetime_observer | hls_core, hls_runtime, hls_compile, erl_hls, hls_fabric, hls_target, hls_spacetime |
| router | — |

Fresh projections separately exercise computation synthesis, communication synthesis and physical target materialization, then exercise the optimizer with only its declared closure. The package auditor rejects duplicate module ownership as well as undeclared, reverse and forbidden edges, so a stale build cannot conceal an ownership error. Application-relative resource resolution now selects compiler, Fabric and target assets independently while preserving a deliberate flat-checkout fallback for standalone tools.

Generated bundles now identify compiler resources under `support/compiler` and target-owned protocol, debug and physical resources under `support/target`; Fabric-owned routing resources remain under `support/fabric`. Stale generated bundles must rebuild. This is a packaging and resource-identity change, not a claim that native XLS or RTL output is byte-identical.

The final qualification used OTP 28.0.2 and Rebar3 3.24.0.

| Check | Stage 3 result |
| --- | --- |
| Fresh compile and EUnit | Default and optional compiles pass. Listener-capable fresh projections pass: compiler 1,290/0; default Fabric 1,417/0; Fabric `spacetime` 1,495/0; standalone spacetime 136/0. |
| Independent boundaries | Computation synthesis 1/0, communication synthesis 1/0, physical target 1/0 and standalone optimizer 136/0; 139/0 total. |
| Dialyzer | Default passes over 382 project modules; `spacetime` passes over 400. |
| Source contracts | 33 checker tests pass. The changed-file comparison covers 1,099 files, reports 3,198 inherited gaps and zero new or changed gaps. Strict checks cover 15 new core, compiler, boundary and optimizer files with zero gaps. |
| Package boundaries | Ten package-checker tests pass. Combined default and optional snapshots inspect 782 modules with zero violations; core plus runtime contain 107 modules with zero violations, including the assembled runtime release. |
| Artifact assembly | All four named releases pass and expose executable launchers with the retained missing-SASL warning. The spacetime escript builds and exposes `validate`, `import`, `join` and `sdf-arcs`. |
| Resource/tool paths | Backend-context tests pass 18/18, local-actor tools 5/5, regression tools 14/14, XC7 packaging mocks 7/7 and relocated source-toolchain tests 3/3. Fresh simulation staging succeeds and copies 62 collision-free support libraries. |
| Native-format front ends | JavaScript passes 574/574; route hashing passes 14/14; the C++ trace transport passes its round trip and 12 rejecting cases; the route exporter and 19-case graph-exporter Tcl fixtures pass. |
| Formatting and hygiene | Root formatting, Python and shell syntax, stale-path scans, confidentiality/exclusion scans and committed-diff whitespace checks pass. The historical inventory is unchanged. |

These are software, packaging and synthetic native-interface witnesses. No native XLS/Yosys/Vivado, routed checkpoint, board or EC2 run was needed or performed. They establish the new authorities and the behavior of the maintained boundaries, not native synthesis, physical timing or board equivalence. The excluded history and private external-consumer material remain outside the umbrella.

## Stage 4 compilation and deployed-execution separation

Commit `d44618a` makes the deployment boundary explicit without changing the Stage 3 application ownership graph:

- `hls_runtime` owns the versioned canonical `hls_deployment_artifact` for partition applications, protocol deployments and mixed applications. Target emitters project their build results to deterministic ETF containing only the static schemas and bindings required by execution; target-only application-build metadata remains separately in `application-build.etf` for the observer.
- Artifact construction and decoding perform complete kind-specific static and relational validation. `decode/1` accepts at most 64 MiB of canonical ETF using existing atoms and does not intern new atoms. `load/1` applies the same bound and validation but may intern retained atoms from a trusted local build artifact. Both boundaries remain trusted because codec checks can load and invoke installed provider modules. SHA-256 identity detects byte changes; it does not authenticate a producer.
- Partition, protocol and mixed stream entry points now require a validated artifact. Fresh brokers, actor processes, sessions, reset ownership and admission remain runtime inputs rather than serialized capabilities. Raw pre-Stage-4 ETF and stale generated deployments are rejected and must be rebuilt.
- Source-aware debug-catalog construction moved behind the `erl_hls` façade. Compiler execution uses one exact, process-free runtime-provider call and does not start the runtime application or supervisor. The package auditor retains BEAM-level MFA evidence and permits only that call from `hls_compile` into `hls_runtime`; every other compiler-to-runtime call or remote type is rejected. Starting `hls_compile` as a standalone OTP application is not a supported launch contract because its declared provider closure still includes the runtime library.
- A runtime-only `hls_fabric` release contains only `hls_core`, `hls_runtime` and OTP. The public runtime consumer depends only on that execution closure and a precompiled callback; the public compilation consumer uses the façade, emits a deployment, and verifies that no runtime application or supervisor was started. Both consumers are exported from the exact immutable umbrella commit before their independent builds, with path traversal and symlink rejection.
- A clean runtime-only child loads a real target-emitted typed artifact without compiler or synthesis-tool applications. The assembled-runtime witness instead loads and validates an independently constructed canonical artifact, then separately executes a precompiled synthetic virtual-node deployment. Neither witness claims that its loaded artifact drives a stream. Installed XC7 link and repetition workflows now emit and load the versioned artifact while retaining their existing source-bound manifests.

The final qualification used OTP 28.0.2 and Rebar3 3.24.0.

| Check | Stage 4 result |
| --- | --- |
| Fresh compile and EUnit | Listener-capable projections pass: compiler 1,290/0; default Fabric 1,432/0; Fabric `spacetime` 1,510/0; standalone spacetime 136/0. |
| Independent boundaries | Computation synthesis 2/0, communication synthesis 1/0, physical target 1/0 and standalone optimizer 136/0; 140/0 total. The local distribution suite passes 22/22 with loopback listener access. |
| Dialyzer | Default passes over 384 project modules; `spacetime` passes over 402. |
| Source contracts | All 33 checker tests pass. The changed-file comparison covers 1,107 files, reports 3,198 inherited gaps and zero new or changed gaps. |
| Package and policy boundaries | All 23 package-checker tests pass. Combined default and optional snapshots inspect 786 module instances with zero violations; the source and assembled runtime closures contain 108 modules with zero violations. Root check-policy tests pass 7/7 and Fabric CI-policy tests pass 2/2. |
| Artifact assembly | All four named releases build and expose their launchers; the spacetime escript and its command-help contract pass. The compiler installed-toolchain witness passes 5/5, the relocated Fabric toolchain passes 3/3 and the runtime-only release audit plus execution witness passes 1/1. |
| External consumers | The two public consumers compile and run from an archive of exact commit `d44618a`. An independently maintained private consumer was also qualified at that exact revision in its own disposable environment; its detailed evidence and environment-specific limitations remain outside the umbrella. |
| XC7 software witnesses | Partition-link simulation passes three RTL cases, repetition-link restart checks pass 2/2 and packaging mocks pass 7/7. These are finite software/simulation witnesses, not native synthesis, timing or board qualification. |
| Formatting and hygiene | Root formatting, shell and Python syntax, confidentiality/exclusion scans, relative-link checks and committed-diff whitespace validation pass. The historical inventory is unchanged. |

The artifact validator is intentionally stricter than the public low-level `hls_record_codec:check/1`; malformed fields that the latter can accept are rejected at the deployment boundary. Tightening the low-level API remains a separate follow-up. The validator also accepts two runtime-safe forms not emitted by current builders: automatic activation on a view without identity and a partition application with no events. These do not weaken the current producer contract, but producer/consumer agreement should be narrowed before treating the artifact format as a stable external protocol.

No native XLS/Yosys/Vivado, routed checkpoint, physical timing, board or EC2 run was required or performed. Stage 4 changes packaging, validation and consumption boundaries; it makes no new native or physical equivalence claim. The excluded history remains external, and no private-consumer material or dependency detail enters the umbrella or its history.

## Stage 5 identity-bound feedback and cutover (in progress)

Stage 5 now implements the complete `logical system → proposed plan → frozen source recipe → build request → exact products → realized implementation → evidence/characterization → revised plan` chain. Logical identity hashes one canonical materialized topology. Plans bind placement, schedules, constraints, capabilities and revision provenance; a revision records both its direct parent and characterization basis. Recursive static-term validation rejects process identifiers, ports, references and functions before plan, topology or characterization identity is assigned.

The source-build v2 recipe binds every generated/copied input and optional plan/projection provenance. Its request identity separately binds the recipe, XLS tool bytes, standard library, target commands and host class; product identity binds exactly the request-dictated command outputs. A realized implementation binds request, product and plan provenance. Both Python and Erlang validators derive the expected product and RTL inventories from the request and frozen recipe rather than trusting self-declared rows. The whole-release cache revalidates selectors, request ownership, complete inventories and bytes; it rejects or quarantines corrupt entries, rejects cross-linked selectors without damaging the other request's entry, and rejects linked cache/release/output roots. Cold/warm, relocation, concurrency, changed-input/tool, cross-link, recomputed-inventory-tamper and byte-tamper tests pass.

Observation now uses an exact four-key source/RTL/observation/implementation binding. The observer validates the retained source recipe and compiled receipt, including request/product/implementation relations and the complete retained RTL byte inventory, before admitting that implementation identity. Characterization and plan revision require both the plan and exact realized implementation to match. These are correlation and local-integrity checks under the trusted build-directory/tool boundary; they do not authenticate a producer or establish semantic refinement or hardware behavior by themselves.

The first feedback witness uses three identical arithmetic actors over one logical topology and XC7 target. `local3` retains independent scalar-completion datapaths. Only after its exact routed characterization does the policy create `shared3`, which adds the maintained selection/return communication and shares one scalar-completion datapath. The plan constraint is exactly a 10 ns clock with the `minimize_dsp` objective; emission and revision reject another constraint map. Source projection checks topology identity, complete placement, one target, schedule membership, module homogeneity and the scalar-completion capability before writing target configuration.

The semantic witness covers all 32 reset positions with independent stalls. The combinational formal check quantifies all finite inputs for one generated action and proves completion, busy exclusion and ordinary API preservation; a deliberately false property produces a counterexample. It is not an unbounded temporal proof.

Both native runs used Vivado 2024.2, part `xc7z030sbg485-1`, a 10 ns clock, one implementation thread and Default synthesis/place/physical-optimization/route directives. The exact RTL and executing Tcl are part of the frozen input, copied into the route output, used from those retained copies and checked against their declared hashes before evidence is accepted. Each route completed with zero setup, hold and pulse failing endpoints, zero unclocked registers/latches and zero unconstrained internal endpoints.

| Candidate | Plan | Request / product / implementation | Routed resources | Routed timing |
| --- | --- | --- | --- | --- |
| `local3` | `98f3d9b5926d0a9c5b8f2709d44d157999c4c237a738751a0e9d834b8d4e934e` | `4f05a12c4bedbe17663d1930d6c5fed4e0a90d74d660c18f2aecaefced4d0768` / `9bcd83a735d4f1a0a49bae7302e3a541dc1f2f1584ebeeb0b808ef14d80d13e7` / `8fc58040efde1bda9f29450757d4eec5a8115a0f60ce5d1a7de969296094025a` | 534 LUT, 465 FF, 3 DSP | setup WNS 4.478 ns; hold 0.082 ns; pulse 4.600 ns |
| `shared3` | `4939f73955c7140b8c31a266e366e80c06b6c79a44c8897bf5fb241b81d54b45` | `23e2d786b86fefa08ae7f515ff352cdf119f42533690468ab750fd6e49c6116d` / `ebe3ced3ac0b5787c3f7a850ac30d4f0bcb5012b058f5bbcd1729422424949a0` / `73f5c5831108ed8d9243db55ec82839717b355471e147c7abf36373a1a3b38f5` | 681 LUT, 480 FF, 1 DSP | setup WNS 1.800 ns; hold 0.081 ns; pulse 4.600 ns |

Both use logical identity `0ab7174a3e05559db89de1cf3e4367ea1b6661fc68ffa41a56d974e91b22ecc6`. The local route evidence identity is `15ac8211f8a15530ff7861e7f021050eb373f204db856ae8c36f3644715719d4`; characterization `87951dfee22acc3aee96ef334cbdaae7d1d4a2747f1badf4c3578cf0be8cbff5` records the local plan as parent and produces the shared plan. The shared evidence identity is `49c63b73f847271d3c913fc89106e66c25b86ede9247cf1050fe8d6dca9163b7`; characterization `c06c5f5267998aea172db3b7c88157f061bd54ffb06edcd48269b10856b178ad` retains that exact realized plan. The source result at `/private/tmp/otp-stage5-feedback-final` has canonical identity `847153a74ad9353f4dd5bce13eb0e7f6e5e4d39ed960a780ac311995f6c2d327`; the exact `result.json` byte digest is `c66a0efe7afbd5d1659a466df07609432d225c5242f4dda859638b795cc0eeb7`. Its two route-evidence records contain the digest inventory for retained inputs, reports and checkpoints. The durable 6,585,707-byte archive is `Evidence/OTP umbrella Stage 5 feedback 2026-11-23.tar.gz` in the campaign notes and has SHA-256 `b06c835c944999f244a1a61ba350737268e2dab4ab79aac41a3ac0a17afa39b2`; `gzip -t` passes.

The policy therefore selects a measured 3-to-1 DSP reduction while accepting 147 additional LUTs, 15 additional FFs and lower but positive measured setup slack. This is a finite computation/communication tradeoff under one explicit DSP objective and timing-feasibility gate, not a claim that every resource improves or that sharing is generally optimal. The runs make no board, maximum-frequency, route-seed-sensitivity, sustained-workload or producer-authenticity claim. External I/O is deliberately false-pathed in this out-of-context witness.

Cutover mechanics are implemented but not yet canonical remotely. The deployed release and application callbacks now use the `hls_runtime` identity, `erl_hls` is version `0.1.0`, transitional topology aliases and flat-checkout fallbacks are removed, and the pull-request workflow automatically selects the serial software tier while native/hardware tiers remain manual. One detached exact-revision checkout builds installed `hls_runtime` and `erl_hls` release closures; isolated consumers compile and run through only the selected closure, with duplicate/stale project applications rejected. The stable [repository history map](../docs/repository-history.md) publishes selected, retained, merge, landing and tag relationships.

The final software, release and exact-revision consumer matrix must still pass at the immutable Stage 5 commit. Canonical `main` still points to the pre-umbrella base and the retained tag is not yet present on the remote, so the repository-history page is a mapping specification rather than remote-state evidence. Stage 5 closes only after the branch and tag land on the canonical remote, those refs are verified, and the former repositories are retained as read-only provenance.

## Deferred qualification

Stages 0–4 establish the import contract, green mechanical umbrella, canonical shared semantic model, acyclic synthesis/optimization architecture and independently packaged compilation/deployed-execution boundary. Stage 5 adds the bounded identity-bound arithmetic feedback witness above, but canonical cutover remains open.

- Native XLS/Yosys, RTL, Vivado and physical evidence is established only for the exact arithmetic candidates above; other native flows retain their own qualification requirements.
- Board behavior and operating-frequency qualification remain outside this out-of-context route witness.
- The optional spacetime RAM witness still needs its explicit testbench and primitive environment.
- Final immutable-revision qualification, canonical remote refs and read-only former-repository provenance remain the Stage 5 exit gates.
