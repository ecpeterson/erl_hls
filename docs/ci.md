# CI selection

Pull requests compare their checked-out integration tree with the target branch. Pushes to `main` compare with the preceding commit. Markdown and rendered documentation alone skip compilation and RTL jobs; source-contract and Dialyzer checks still run. Executable examples, fixtures, dependencies, workflows, unknown paths and unavailable history require tests.

Successful CI runs retain a small qualification record keyed by all tracked non-documentation content, including tests, dependency pins and workflows. An exact match skips repeated integration jobs on report-only follow-ups. Failed or cancelled runs cannot create that record. Missing or evicted records simply cause testing again. GitHub's branch cache isolation applies; a PR record does not qualify a later `main` build.

Manual workflow dispatch always runs tests. The selector's Git-history tests cover renames, deletions, executable prose and input changes. Save important measurements outside CI; its artifacts are disposable diagnostics.

Successful jobs upload no artifacts by default. Failures retain diagnostics for two days; manual dispatch can request them with **diagnostics**. Each bundle contains at most 4 MiB of file data: up to 256 files, 256 KiB each. Large logs retain their tails; oversized structured files and generated Yosys netlists are omitted, with omissions listed in the bundle index. Job summaries report compressed upload sizes. Compiler caches and successful-input qualification records are unaffected.
