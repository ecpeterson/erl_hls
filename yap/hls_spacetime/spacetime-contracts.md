# Spacetime S2: executable evidence contract

2026-11-06. **S2 complete; S3 next.** This is the first implementation slice worth committing. No commit or PR was created. The [maintained contract](../docs/contract.md), three `src/toolchain/hls_spacetime*.erl` modules, saved `test_data/spacetime_example.term` and EUnit regressions form one reviewable change. Existing timing-profile code remains unchanged.

The cycle companion separates value ancestry, required control, observed resource ordering and electrical activity. It validates event/version/activation/reset identities, observer sequence coverage, storage history, masked writes, read latency and supported collisions. Full overwrites do not invent old-value dependencies; passive holds do not reserve ports. Physical mappings allow folded/shared resources and keep ambiguous/unmapped evidence explicit. JSON encoding preserves wide masks as hexadecimal strings, with exact bounded cycle/sequence numbers.

The saved example is synthetic, including its timing, checkpoint and placement. Its Phi/data labels illustrate the S1 feedback shape without asserting an actual decoder recording. The RAM example is also synthetic. No source-protocol capture, compiled-RTL witness, native measurement, physical equivalence or live-device claim is added by S2. The stopped EC2 instance was not contacted or started.

## Validation

- `rebar3 eunit --module=hls_spacetime_tests`: 43 tests passed, including rejecting duplicate identities, missing interiors/footers, false completeness, future/cross-reset ancestry, stale storage, unsupported collisions, wrong read latency, missing results, incompatible build mappings and unsafe text/number encodings.
- Existing `tools/test_hls_profile.py`: 13 tests passed; schema-1 nanosecond consumers retain their behavior.
- Pinned erlfmt check, source-checker tests, full source-contract audit, strict audit of the three new modules, Dialyzer and package-boundary checks passed. The complete audit still reports 3,334 inherited gaps across 382 files, with zero new gaps. No whole-tree documentation claim.
- Checks were local, serial and guarded at 6 GiB. The successful cold type-check sequence took 65.38 s, peaking at 615,956,480 bytes; final affected checks after exact-mask encoding took 11.26 s, peaking at 499,892,224 bytes. Both owned groups exited 0 with no guard and no remaining process. The earlier source audit found missing test specs/comments; those were supplied before qualification. Formatter invocation setup failures and the earlier audit remain in local diagnostics.

Compact logs, generated JSON example and final source hashes are retained in [contracts-1](/Users/ecpeterson/Documents/code/hls_artifacts/runs/spacetime-2026-11-06/contracts-1/result.json). `_build/spacetime-s2` contains disposable local diagnostics and build caches; these are not an indefinite retention exception.

## S3 handoff

Use this contract from the direct-backend capture path. S1 remains the registered workload/source baseline; new observation bindings need their own exact identity and must not silently alter the implementation measured later. Add real accepted-action and storage observations, explicit sequence footers and offered-input/output-ready replay schedules. Keep physical catalogue `null` until matching native evidence exists. S3 should reuse S1's successful oracle while its source/input identities remain valid.

The validator checks consistency of producer declarations. It cannot detect a recorder that omitted actions and renumbered them, infer unsupported RAM collision behavior, authenticate native evidence or recover value-sensitive gate ancestry from names. Qualification of observations and physical association remains S3/S4/S6 work. Multi-clock/device coordination and retained cross-reset ancestry are outside schema 1. No extra full decoder regression or native run was added for this schema task.
