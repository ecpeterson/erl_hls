# Compiler regressions and CI

After installing the [toolchain prerequisites](toolchain.md), run a feature case from the repository root:

```sh
python3 tools/run_regression.py /path/to/xls --cases comparisons helpers
python3 tools/run_regression.py /path/to/xls --changed-since origin/main --dry-run
python3 tools/run_regression.py /path/to/xls --changed-since origin/main
```

The runner compiles the Erlang fixtures once, then executes selected cases serially. Fixture writers still produce DSLX and BEAM-derived expectations. The shared external executor handles commands, process-group timeouts and per-step diagnostics; case recipes specify conversions, schedules, simulations, expected compiler diagnostics and SAT checks. An expected rejection must fail with its specified diagnostic: a crash or unrelated tool error is not a passing negative test.

Without a stage argument, each case creates a fresh run directory below its inventory's `_build/` directory. An explicit stage is used directly for one case, or contains one subdirectory per case when several are selected. Each selected case directory must be absent or empty. Fresh directories prevent stale generated files from satisfying a later check and retain failed runs for inspection. The existing `tools/test_*.sh XLS_ROOT [STAGE]` entry points delegate to the same runner. Use `--list` for the inventory and `--all` for every case, including explicitly local-only cases. This feature runner does not replace EUnit, source-quality checks or the separate debug/formal drivers.

Add a localized regression by keeping its Erlang fixture/oracle writer, defining a case in `tools/regression_cases.py` with the shared execution primitives, and recording its name, default stage, CI group and exact fixture dependencies in `tools/regression_inventory.json`. Do not copy a shell pipeline or add another CI command. A dependency may narrow selection only when every affected case is listed; shared compiler inputs and unknown paths require full coverage.

## Selection and retained diagnostics

Pull requests compare their checked-out integration tree with the target branch. Pushes to `main` compare with the preceding commit. Markdown and rendered documentation alone skip compilation and RTL jobs; source-contract and Dialyzer checks still run. The local runner and CI use the same inventory to select cases for known fixture changes. Shared sources, dependencies, workflows, unknown paths and unavailable history select every routine case. Local-only cases remain outside routine CI. Independent checks within a selected CI job still run.

Successful CI runs retain a small qualification record keyed by all tracked non-documentation content, including tests, dependency pins and workflows. An exact match skips repeated integration jobs on report-only follow-ups. Failed or cancelled runs cannot create that record. Missing or evicted records simply cause testing again. GitHub's branch cache isolation applies; a PR record does not qualify a later `main` build.

Manual workflow dispatch always runs tests. The selector's Git-history tests cover renames, deletions, executable prose and input changes. Save important measurements outside CI; its artifacts are disposable diagnostics.

Successful jobs upload no artifacts by default. Failures retain diagnostics for two days; manual dispatch can request them with **diagnostics**. Failed regression records and their failing step logs take precedence over completed steps. Each bundle contains at most 4 MiB of file data: up to 256 files, 256 KiB each. Large logs retain their tails; oversized structured files and generated Yosys netlists are omitted, with omissions listed in the bundle index. Job summaries report compressed upload sizes. Compiler caches and successful-input qualification records are unaffected.
