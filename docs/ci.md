# CI selection

Pull requests compare their checked-out integration tree with the target branch. Pushes to `main` compare with the preceding commit. Markdown and rendered documentation alone skip compilation and RTL jobs; source-contract and Dialyzer checks still run. Executable examples, fixtures, dependencies, workflows, unknown paths and unavailable history require tests.

Successful CI runs retain a small qualification record keyed by all tracked non-documentation content, including tests, dependency pins and workflows. An exact match skips repeated integration jobs on report-only follow-ups. Failed or cancelled runs cannot create that record. Missing or evicted records simply cause testing again. GitHub's branch cache isolation applies; a PR record does not qualify a later `main` build.

Manual workflow dispatch always runs tests. Diagnostics expire after seven days; retain important measurements in the repository rather than relying on CI artifacts. The selector's Git-history tests cover renames, deletions, executable prose and input changes.
