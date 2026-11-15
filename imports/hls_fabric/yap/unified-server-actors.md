# Unified server actors

Companion to [erl_hls #49](https://github.com/ecpeterson/erl_hls/pull/49), originally qualified at `eeb1b876d42d8e6d2818ca92631762e14f9a45a3` for both compiler and runtime. Both development checkout links and stale generated checkout projections were moved aside before pinned-dependency qualification. Fetched revisions are recorded with each qualification below.

`xls_scheduler_actor` now consumes the common actor artifact for bounded servers as well as state machines. `xls_machine_codegen` packs immediate reply failure status without a retained-call table; the scheduler drains retained callers only when such storage exists. Source-protocol owners retain the callback-kind field. The domain bridge allocates one in-flight caller route for an immediate server, while its source contract remains immediate and contains no retained-call bound. Internal casts into call schemas remain rejected.

The small protocol call fixture is now an immediate `hls_gs`, exercised by the existing local-owner backpressure/reference tests and domain-interface admission. A separate retained-server source spelling runs the same two-actor shared-RAM workload as the state-function fixture. Their wire behavior intentionally differs only in the existing reserved-ID server fault notification; the server bench requires exactly one such notice. Current terminal fault encoding is checked rather than obsolete unmarked reason words.

Local commands use OTP 28.0.2, the pinned `xls-optimized-2026-09-30` installation, serial execution and a 6 GiB descendant-process RSS guard. No Actions, EC2 or board run. Logs/manifests under `_build/unification-checks/` are disposable; failures are retained separately.

- `pin-and-native-1`: 1,385 of 1,386 native cases passed. The remaining existing supervisor witness reused a directory named only by a VM-local counter. Its stage now also includes wall-clock nanoseconds; the isolated rerun in `fabric-qualified-2` passed. No actor/domain assertion failed in that pinned run.
- `unification-local-1`: finite source variation, projection and immediate-server owner checks, including stalled reply publication and atomic/split action agreement. Local activation conversion also covers reduction/gather entries.
- `unification-server-shared-2`: two-actor retained-server public-port RTL at p2 and p3, each with 17 expected replies plus exactly one fault notice. Checks include fullness, continuation priority, independent actors, stale handles, stalled reply stability, failure and RAM reset. Both structural checks found no errors or combinational loops.

- `unification-statem-shared-1`: the original state-function workload passed the same p2/p3 RTL checks with 17 replies each. Its local direct test passed; the pinned XLS JIT then aborted in `shared_internal_burst_test` with an LLVM bitwidth assertion. The remaining event/reduction/reply tests passed under the DSLX interpreter in `fabric-statem-resume-1`; the script now selects that evaluator explicitly. No JIT-equivalence claim follows from those units.
- Source contracts passed with 289 inherited gaps and zero new/changed gaps. The full-tree documentation debt remains open.

- `fabric-types-release-1`: default-profile compilation, Dialyzer and formatting passed; 317 library modules had zero example dependencies; the runtime-only release's 95 modules had zero package violations. Release assembly retains the existing no-SASL upgrade warning. This final job peaked at about 1.4 GiB RSS; no guard fired.

These checks are finite witnesses and structural/type evidence, not all-input proofs, area/timing forecasts or board qualification. Application port and trial-lifetime measurement remain separate master-roadmap work.

## Compiler CI repair pin

The affected-consumer checks used repair pin `3d79d59f4b49faf9de24b18c7840ee0f1ceceb8f`, which validates raw server wire tags before an enum cast, preserving unknown-tag rejection in the DSLX interpreter. The compiler also repaired stale diagnostic/control-history fixtures and passed three control RTL schedules. No fabric implementation changed.

`ci49-fabric-pin-1` fetched and verified both compiler/runtime Git HEADs at this pin without checkout overrides. All 18 affected protocol-reply, local-execution and composition tests passed, as did Dialyzer, formatting and source contracts (289 inherited gaps; zero new/changed). This serial check used 45.98 seconds and peaked at 769,664 KiB; no guard fired. The earlier broad and physical-interface witnesses above were not rerun for this pin repair.

The final compiler/runtime pin is `ee2d0280ab8662e338d242eac625075969a83e58`. `ci49-fabric-final-pin-1` fetched both repositories and their actual Git HEADs were verified, without checkout overrides. Compiler/runtime production trees (`src`, `apps`, `include`, `priv`, `rebar.config`, `rebar.lock`) are byte-identical to the tested repair pin above; subsequent compiler commits change only fixtures, test orchestration and documentation. The 18 affected consumer witnesses and type/contract checks are reused rather than rerun. The final compiler adds one local/CI qualification entry point and fixes serial-fault expectations through explicit reset.
