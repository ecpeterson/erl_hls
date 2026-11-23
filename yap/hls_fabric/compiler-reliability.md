# Compiler reliability integration

Local qualification on 2026-11-09, based on fabric `6338916`. Both `erl_hls` and `hls_runtime` now pin merged compiler `46eae00`; this PR is independent of the subsequent compiler topology-command PR. Evidence is retained under `hls_artifacts/runs/compiler-reliability-2026-11-09`. Actions was not used.

- [x] Exercise inline source attribution through a relocated fabric release, real source/helper lowering and a relocated source bundle. Controlled converter failures name generated actor expressions, imported helper expressions and unannotated wrapper code. The first two recover the expected original Erlang file/line, the wrapper remains unmapped, raw stderr is unchanged and failed attempts publish no compiled release. Successful retry retains all frozen input hashes. These tool stubs qualify diagnostic plumbing, not XLS semantics or hardware.
- [x] Refresh the four maintained Phi/noise DSLX snapshots with origin comments. Removing comments and line-edge whitespace yields identical code before and after in every file. Generated DSLX stays reviewable beside the source; no RTL is committed.
- [x] Include helper dependency hashes in owner-import expectations and verify emitted helper bytes before excluding generation-only fields from static-plan comparisons.

All three moved-release checks pass: source-protocol attribution/packaging, scheduler profile packaging and separate Phi/Snowflake example emission. The initial complete EUnit run passed 1,167 tests and exposed six stale snapshot/manifest expectations; after correcting them, those six pass through their normal EUnit selectors. Unchanged successful cases were not repeated.

Dialyzer, formatting, 30 source-auditor self-tests and source contracts pass (523 files, 289 inherited/current gaps, zero new or changed gaps). Application boundaries find no example dependencies across 276 library modules; package/release boundaries find no violations across 70 runtime modules. The development logs retain the failed expectations and initial test-harness filename/path assumptions. This qualification adds no new FPGA timing or live-device claim.
