# CI coverage

CI selects tests from the complete diff against the PR target branch, or the preceding commit on a `main` push. Markdown and rendered documentation alone skip integration jobs. Source contracts and Dialyzer still run. Executable examples, fixtures and unknown paths require tests; unavailable history requires every group.

Scheduler changes run software checks, focused RTL regressions, the execution backend and complete D3 shared-scheduler memory with source-fragment reductions. Small noisy board tests cover both ordinary and offloaded reductions. Packed-link sweeps, direct-actor bridge experiments and board bring-up run when their inputs change; dependency and workflow changes select every group. `tools/ci_groups.json` records these boundaries. Rules select the first matching group set; unrecognized files fail closed.

Successful workflows retain a qualification record keyed by all tracked non-documentation content, including dependencies, test harnesses and workflows. An exact match skips repeated integration jobs on report-only follow-ups. Failed or cancelled jobs cannot qualify inputs; missing records cause testing again. GitHub's branch cache isolation applies, so PR records cannot qualify `main` builds. This saves repeated testing without relying on commit flags or a truncated changed-files API.

Manual dispatch always runs tests. The CI workflow's **extended** option adds direct/ordinary and shared/ordinary D3 references plus the full packed-link performance grid. The Execution backend workflow also runs complete D3 debug qualification when dispatched manually. Use these for changes to those paths or for broader release qualification; no periodic sweep runs automatically.

Automatic tests retain active reset/restart, BEAM comparison, independent clocks, blocked peers, framing, credit isolation, reduction collection, publication ordering and debug-query witnesses. The eighteen-tile D6 simulation and physical timing campaigns remain local measurements. These witnesses do not establish general equivalence.

Diagnostics expire after seven days. Retain important measurements in the external artifact archive; see [artifact storage](artifacts.md). Timeouts allow runner variation; reducing passing-job time requires fewer executions, not shorter deadlines.
