# Repository instructions

Read [STYLE.md](STYLE.md) before changing code or documentation. Every PR must follow its source-contract, brevity and documentation rules.

Run the checks in [docs/source-quality.md](../../docs/hls_fabric/source-quality.md), plus tests appropriate to the change. Follow [CI coverage](../../docs/hls_fabric/ci.md) when choosing an extended hardware run; do not dispatch the full performance sweep for routine documentation or unrelated changes. Complete contracts for changed declarations; use the CI audit to find remaining migration work. Keep Fabric working notes in `yap/hls_fabric/`, outside `docs/`. Do not claim the whole tree is documented while the audit reports gaps.

Keep long-lived worktrees and compiler caches outside system temporary directories. macOS may delete old `/tmp` files even while a worktree is in use; use it only for disposable scratch.

Use `rebar3` directly for Erlang dependencies, compilation and checks; `rebar3 release -n hls` packages the `hls-fabric` source-emission command. Keep retained measurements in the external artifact archive, never in `_build/` or source directories; see [docs/artifacts.md](../../docs/hls_fabric/artifacts.md).

Before decoder architecture experiments, read the current [campaign cost policy](../../yap/hls_fabric/physical-architecture-options.md#routing-and-area-policy). Budget LUT growth against cumulative device headroom; do not restore a universal no-growth gate or treat cycle savings as routed-clock evidence.

Run memory-intensive local builds, simulations and profile exports one at a time. Use bounded profile windows and prefer the authorized remote machine for large physical runs. Report expected memory before unavoidable large local jobs; do not fill local memory merely to increase parallelism.
