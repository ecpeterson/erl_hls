# Repository instructions

Read [STYLE.md](STYLE.md) before changing code or documentation. Every PR must follow its source-contract, brevity and documentation rules.

Run the checks in [docs/source-quality.md](docs/source-quality.md), plus tests appropriate to the change. Follow [CI coverage](docs/ci.md) when choosing an extended hardware run; do not dispatch the full performance sweep for routine documentation or unrelated changes. Complete contracts for changed declarations; use the CI audit to find remaining migration work. Keep agent working notes in `yap/`, outside `docs/`. Do not claim the whole tree is documented while the audit reports gaps.

Keep long-lived worktrees and compiler caches outside system temporary directories. macOS may delete old `/tmp` files even while a worktree is in use; use it only for disposable scratch.

Use `python3 tools/build.py` to prepare the pinned compiler and run rebar3. Keep retained measurements in the external artifact archive, never in `_build/` or source directories; see [docs/artifacts.md](docs/artifacts.md).

Before decoder architecture experiments, read the current [campaign cost policy](yap/physical-architecture-options.md#routing-and-area-policy). Budget LUT growth against cumulative device headroom; do not restore a universal no-growth gate or treat cycle savings as routed-clock evidence.

Run memory-intensive local builds, simulations and profile exports one at a time. Use bounded profile windows and prefer the authorized remote machine for large physical runs. Report expected memory before unavoidable large local jobs; do not fill local memory merely to increase parallelism.
