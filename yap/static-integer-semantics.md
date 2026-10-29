# Static integer semantics

- [x] Evaluate untyped integer expressions before contextual XLS width inference, reuse the evaluator for binary sizes, and preserve straight-line constant aliases.
- [x] Keep typed arithmetic, source match/failure ordering and branch binding checks intact; remove the telemetry workaround.
- [x] Qualify actual source through BEAM, XLS and RTL and run local source/type/package checks.

The motivating expression `hls_type:as(hls_nums:s32(), 0 - (1 bsl 15))` previously became positive 32768 after an unsigned intermediate. It now produces −32768. Static helper/record results are checked at their final mathematical value; a declared u8 accepts `(1 bsl 8) - 1` without narrowing its intermediate. Explicit casts/providers/runtime values end the static domain. Branch joins do not infer new constants, failing operators remain observable, and retained constants have independent widths during runtime matches.

Local validation passes 1,056 EUnit cases, 220 BEAM-derived scalar interpreter/JIT/RTL cases, 210 literal-context vectors, the existing arithmetic/helper/failure/binary/shift regressions, and the shipped telemetry RTL witness without its workaround. Formatting, source checks, runner/package checker suites, package audit and Dialyzer pass. The source audit retains 3,334 inherited/current gaps with zero new/changed gaps. Finite witnesses do not establish arbitrary-program equivalence or hardware performance. Actions was intentionally skipped.

Evidence is retained outside the source tree in `hls_artifacts/runs/erlang-local-cells-2026-10-16/post-campaign-cleanup-43/`. Its `review.json` indexes successful checks and the baseline reproduction. Resolved failures include obsolete constant-alias rejection fixtures, a structured singleton guard predicate, a stale-BEAM attempt and a package audit before the default build existed; their logs remain preserved.
