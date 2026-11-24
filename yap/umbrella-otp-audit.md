# Umbrella OTP Stages 0–2 audit

Stage 0 closed on 2026-11-23 with validated filters and no imported history. Stage 1 then imported those filtered histories and landed the selected 390 modules as nine OTP applications without changing their application boundaries. Commit `f92f8b0` completed the application-seam preflight, and `6b1246c` completes Stage 2 by extracting a process-free `hls_core` and making its semantic model authoritative across the umbrella. The current optional-profile tree has 394 production modules across ten applications. The [source inventory](umbrella-otp-inventory.md) remains the historical record of the original 330-module, eight-application feature-branch audit and its selected-mainline reconciliation.

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

## Deferred qualification

Stages 0–2 establish the import contract, green mechanical umbrella and canonical shared semantic model. They do not establish the target Stage 3 application architecture or qualify native and physical behavior beyond the unchanged software witnesses above.

- Native XLS/Yosys compilation, source-map integration and extended RTL simulation against the combined umbrella still need their external tool environment.
- Vivado, physical timing and board qualification wait for a changed hardware boundary and the appropriate remote or board environment.
- The optional spacetime RAM witness still needs its explicit testbench and primitive environment.
- The external same-revision runtime-only consumer, separate compile-time consumer and assembled-release asset witnesses remain Stage 4 work.

Stage 3 is next: redraw computation, communication and physical-synthesis boundaries without hiding cycles behind pass-through adapters. Stage 4 then qualifies separated compilation and execution with external consumers, and Stage 5 adds the measured `plan → implement → characterize → revise` loop so physical feedback can optimize computation and communication together. No Stage 3 work has begun.
