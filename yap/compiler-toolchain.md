# Compiler toolchain ownership

- [x] Package ordinary actor lowering as `hlsc`, with include/macro/source options, diagnostics and an explicit optional XLS recipe.
- [x] Own source-bundle copying, hashing, manifest schema and the detachable XLS consumer in erl_hls; downstream emitters supply scheduling and deployment policy.
- [x] Share a small fixed-option parser and diagnostic wrapper without registering applications or creating a plugin framework.
- [x] Validate compiler and hls_fabric #117 together; retain logs outside the source tree.

This does not migrate the older experiment cache or plotting/report tooling. Standard rebar commands build/check/package each application; no custom provider is necessary. A future provider can call the same native API.

Validation: 1,140 compiler EUnit cases, 19 source-checker self-tests, source-contract audit (4,936 inherited gaps, zero new), Dialyzer, relocated compiler with real includes/macros and Python/rebar blocked, and detached-driver success/retry/hash/failure cases pass. Actual XLS conversion/optimization/codegen and Icarus elaboration pass for a dedicated actor; this is a build smoke test, not a behavioral or timing claim. Fabric integration passes its 414 EUnit cases, relocation/schedule checks and whole/split/mixed example emission. Logs: external archive `runs/erlang-local-cells-2026-10-16/post-campaign-cleanup-3/`. An initial test expected `pub proc Top` while existing lowering emits `proc Top`; the assertion was corrected without changing lowering.
