# CI coverage

Automatic GitHub Actions runs are suspended. The workflow accepts manual dispatch only. Restoring the pull-request trigger is a separate decision after reviewing the reduced suite’s cost. Do not add a second run on merge to `main`.

The same entry point runs locally and in Actions, serially with one tool installation:

```sh
bash tools/ci.sh all /path/to/xls /absolute/fresh/output
```

Use OTP 28.0.2, rebar3 3.24.0, Python 3, XLS, Icarus 13 with its matching VPI compiler, Yosys and Verilator on `PATH`. See [source quality](source-quality.md) for contracts and Dialyzer. `software` accepts `-` instead of an XLS path. Other selectable tiers are `components`, `phi` and `snowflake`; there is no extended matrix. The output directory must be new. Failed outputs are retained.

| Tier | Coverage |
| --- | --- |
| Software | EUnit including the local distribution carrier, tooling/parser/packaging unit tests, source contracts and Dialyzer. Release relocation uses mock external tools and does not claim XLS correctness. |
| Components | DSLX queue/mailbox/scheduler/effect/gather units; small source-action witnesses and scalar-owner receipt/completion contracts; plain/scalar/gather inspection projections; return-route allocation, asynchronous FIFO, credit and packed framing; six host-versus-RTL codec cases at one/three payload words, plus ordinary serialization and packed-word checks at one/nine payload words; a counter-driven trace-probe fixture; four-counter egress and three-actor framed relay fixtures. No decoder application, mapped-area check or performance grid. |
| Phi integration | One noisy D2 memory experiment in the coalesced scheduler, ordinary reductions, two clocks and stalls; compare corrections, quiet closeout and readout with BEAM. Build the devices once without an unused bridge harness, then compile and run the profiling harness. |
| Snowflake integration | One D2/H2 surface window in the source-protocol backend. Eight finite syndrome sheets, startup, overlapping host offers, independent output stalls and reset; compare round and per-sender correction frames with the ordinary BEAM/reference witness. |

These are the only application integration tests. The finite witnesses are development regressions, not QEC validation, general equivalence or hardware performance evidence. The Snowflake fixture explicitly selects independent buffered command delivery; the coordinator's acknowledgment barrier controls the next phase. Its original scheduler topology uses queued broadcast.

The previous D3 direct/shared/offloaded matrix, multiple protocol-Phi widths and placements, full decoder debug builds, board bring-up, connected-area sweeps and packed-link load/latency grids no longer run in CI. Their experiment drivers remain available for a specific change or measurement. Routine coverage does not claim their former size, placement, timing or area coverage. Add a small component regression when fixing a mechanism; do not add another full decoder configuration to the default suite.

Generated ordinary protocol receivers import a single source owner definition per module instead of duplicating that definition into every receiver. Each receiver still has independent state and inbox wiring; this is compilation reuse, not hardware sharing. Manifests bind the imported file and its hash. Publication rendering also groups identical selector results and emits contiguous bit slices, preserving the complete checked projection. Shared-arithmetic owners retain their distinct generated ABI.

One workflow job installs tools once and runs the selected tier(s), with a 25-minute hard limit. Individual external compiler/test stages retain their shorter deadlines. Cached dependencies and Dialyzer tables save setup work; qualification-cache keys, path-selection rules and duplicate workflows have been removed. Each invocation writes `times.tsv` with setup and tier wall times. These describe host time, not simulated throughput. The full manual Linux qualification took 9m38s with warm XLS, Icarus and Dialyzer caches; see [the measured run](https://github.com/ecpeterson/hls_fabric/actions/runs/40117299694). Cold tool installation remains unmeasured. Restoring automatic runs remains a separate decision.

Successful jobs upload no artifacts by default. Failure or explicit diagnostic requests retain a bounded bundle for two days: at most 4 MiB of file data, 256 files and 256 KiB per file. Large logs retain their tails; oversized structured reports and generated netlists are omitted and listed in the index. Preserve important evidence in the external artifact archive; see [artifact storage](artifacts.md).
