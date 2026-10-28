# Compiler entry points and bundles

`hls_compile_cli` implements the standalone `hlsc` command using `hls_cli` for options and `hls_diagnostic` for structured text/JSON errors. `hls_compile:actor/3` is the equivalent Erlang API: it passes source context to `xls_parse`, retains the emitted failure codebook, and packages the result. Downstream build frontends can reuse its compiler-support snapshot APIs.

`hls_artifact_bundle` owns fresh output directories, support-tree snapshots and the hashed `source-build.json` manifest. The emitter supplies literal codegen flags and descriptive metadata; this packaging layer does not select placement or run external tools. The separate `priv/tools/compile_source_build.py` driver consumes the published bundle.

Compiler passes belong to [frontend](../frontend/README.md) or [backend](../backend/README.md), not the CLI. Runtime sessions belong to `runtime/`. Keep option parsing and diagnostics reusable without coupling them to a particular application or deployment.
