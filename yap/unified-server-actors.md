# Unified server actors

Implemented on `codex/unified-server-actors`, based on `8d40ab0`. The bounded `hls_gs` API remains public. `hls_server_source` normalizes its callbacks into one inert actor phase before common interface analysis, planning and XLS lowering; `hls_actor_callback` adapts the native callbacks to the same scheduler. Original expression order, source positions, continuation priority and server wire fault notifications remain observable. Four obsolete Erlang server engines and the separate DSLX driver are removed.

Immediate replies retain only 32-bit failure status, with no retained transaction table or allocation counter. Retained servers keep the declared bound. Common actor interfaces now admit servers to topology, inspection and domain startup. This does not make arbitrary OTP `gen_server` modules synthesizable, change supported return forms, or prove hardware equivalence. Physical proxies retain their transport implementation.

## Local evidence

All external work was serial, with OTP 28.0.2 and the pinned local XLS installation `xls-optimized-2026-09-30`. No Actions, EC2 or board run. `_build/unification-checks/` contains command, elapsed-time, exit/guard and log hashes; `_build/` products are disposable.

- `compiler-final-native-2`: 1,266 EUnit tests passed; 26 source-contract auditor tests and four package-auditor tests passed; 47 runtime modules had zero package violations. A new mixed-domain witness retires immediate, retained and state-function actors together and checks fresh replacement state/incarnation.
- `compiler-types-2`: after fixing two Dialyzer findings and preserving native-only atom requests/ignored info, 68 affected runtime/name tests passed; Dialyzer and formatting passed. Contract audit: 3,285 inherited gaps, zero new/changed gaps. The full-tree documentation debt is not closed.
- `unification-rtl-2/service_contracts/regression.json`: immediate-server finite public-port witnesses passed at p1/II1, p2/II1 and p3/II2, including malformed framing, reply contracts, stalls, reset and failure evaluation order.
- `unification-deferred-3/regression.json`: retained-server witnesses passed at p2/II2 and p3/II3, including release/drain, stale handles, caller fullness, continuation priority and failure after the last reply. The first shared-path attempt missed the reserved-ID continuation fault notice; the common reply renderer now preserves it.
- `unification-examples-1/names/regression.json`: 14 steps passed, including DSLX, IR and RTL names. `unification-init-2/regression.json`: 22 steps passed, including nonzero initialization at two schedules and rejection of refutable initializer matches. The initial fixture had a forward proc reference, corrected before the successful run.

These are finite witnesses and structural/type checks, not all-input proofs or area/timing/board qualification. Earlier failures remain in their separate logs. Initial memory accounting covered only the launcher process group and undercounted external-tool descendant sessions; subsequent runs tracked descendants and their groups under the 6 GiB guard. The final native/type runs peaked below 0.7 GiB and hit no guard.

The paired fabric change supplies packed-state codecs and bridge caller accounting for the immediate strategy, removes the scheduler's server fallback, and qualifies source-protocol owners and shared-RAM servers. Application migration remains a separate master-roadmap milestone.

## CI diagnostic-fixture repair

Run 43756018378 passed all 1,268 EUnit tests, source-quality checks and both mixed-topology cases, then rejected the standalone diagnostic fixture for its missing `hls_replies` declaration before checking message width. The fixture now declares its reply contract and also compiles with a four-word frame, isolating the intended three-word overflow diagnostic. No compiler/runtime behavior changed.

`ci49-packaging-1` passed the installed CLI/relocation, build-executor, source-diagnostic, IR-census and regression-runner suites (42 tests). `ci49-preflight-1` passed the real XLS source-attribution witnesses, simulation-input generation, the regsvc DSLX golden, formatting and contract checks (3,285 inherited gaps; zero new/changed). Both serial local checks stayed below 0.15 GiB under the 6 GiB guard. The push reruns the existing CI workflow; no separate workflow dispatch.

The next run (43765501846) passed packaging and differential checks, then found a control-failure fixture still calling the removed `service_step`. Its migrated common-machine witness reserves mailbox capacity, completes initial entry, compares actor state separately from mailbox bookkeeping, and checks valid egress. This exposed an unchecked raw-byte-to-`Tag` cast in server request validation: an unknown byte traps in the DSLX interpreter before reaching rejection. Validation now compares the raw byte with declared tags; unknown tags retain error 1, length mismatches error 3, and both preserve actor state.

`ci49-control-3` passed all 73 DSLX/JIT tests, seven constant-initializer rejections, and three public-port RTL schedules (p1/II1, p2/II1, p3/II2), including structural checks: 27 steps total, 100.35 seconds, peak 478,256 KiB. Earlier migration failures are retained. `ci49-final-quality-1` passed 99 affected EUnit tests, Dialyzer, formatting, source contracts and runtime package boundaries; the regsvc DSLX golden was regenerated. No physical measurement was repeated.
