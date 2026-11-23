# Erlang source toolchain

The source-toolchain consolidation and its post-campaign follow-ons are complete. Use [building](../../docs/hls_fabric/building.md) for the supported commands and `Notes/erl_xls/Roadmap.md` for the sole active task list (G2/G6/G8). The [original implementation record](https://github.com/ecpeterson/hls_fabric/blob/28f8bd1562f7f429a8f482c4d73776b04cdc2e31/yap/erlang-source-toolchain.md) preserves intermediate limitations, exact validation counts and resolved failures; its former “next” tasks are not pending work.

- Replaced the duplicate Python compiler preparer with ordinary rebar dependencies and a relocatable OTP release.
- Gave `erl_hls` ownership of `hlsc`, source preparation, diagnostics, source bundles and the optional external XLS driver; retained placement, execution and application presets in fabric.
- Moved source analysis and deployment composition in process, retaining checked results through emission rather than writing and rereading intermediate ETF files.
- Moved Phi-specific progress modeling beside the application through the generic model-provider boundary.
- Completed canonical identity, layouts, plan/inspect/preview APIs and backend/build-profile selection through the later cleanup PRs [#138](https://github.com/ecpeterson/hls_fabric/pull/138), [#139](https://github.com/ecpeterson/hls_fabric/pull/139), [#140](https://github.com/ecpeterson/hls_fabric/pull/140), [#142](https://github.com/ecpeterson/hls_fabric/pull/142) and [#145](https://github.com/ecpeterson/hls_fabric/pull/145).
- Separated build/runtime/application packages, promoted maintained examples and retired obsolete experiment trees. [Disposition](retired-experiments-01-06.md).

Compiler analysis and hardware lowering remain Erlang-owned; external tool execution, reports and plots are separate boundaries. Remaining Python at those boundaries is not itself unfinished migration. A retained experiment should acquire a native source frontend when it becomes a maintained build path, rather than creating a blanket rewrite queue.

Evidence remains in `hls_artifacts/runs/erlang-local-cells-2026-10-16/post-campaign-cleanup-2` through `post-campaign-cleanup-5` for initial packaging, framed-role relay repair, retained planning and application-model extraction. Subsequent cleanup evidence retains the complete identity/layout/driver/package qualifications. These local builds and finite witnesses do not qualify a new physical implementation or live deployment. No archived failure or missing historical input is repaired by repeating a completed experiment.
