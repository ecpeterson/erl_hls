# Timing profiles

A timing profile is a saved, application-independent graph of work, counters and dependencies. Collect once, then render or query it without rerunning simulation. Keep the recording, clock origins, source/tool digests and validation results beside it; a plot alone is not reproducible evidence.

`tools/hls_profile.py` reads schema 1 JSON with `unit: "ns"`:

- `tracks`: unique `id`, `name`, optional `group`.
- `events`: unique `id`, `track`, `name`, integer `ts` and `dur`, optional `args` and `category`. Zero duration denotes an observed instant. Use separate tracks for simultaneous or overlapping work.
- `edges`: `source`, `target`, `kind`, nonempty `evidence`, optional nonnegative `delay_ns`. An edge means the source finishes before the target starts. Delays count only when the adapter explicitly attributes them; elapsed time between two observations is not automatically a causal delay.
- `counters`: `track`, `name`, integer `ts`, finite `value` exactly representable as a double.
- `metadata`: provenance and `dependency_scope`, describing which dependencies were observed or reconstructed and which remain unknown.

Convert every clock to a common trace-relative nanosecond origin. Retain original cycle, period and reset/epoch information in arguments. Adapters must resolve transaction identity and record their evidence; the exporter cannot infer causality from temporal proximity.

```sh
python3 tools/hls_profile.py timing.profile.json \
  --perfetto timing.perfetto.json --svg timeline.svg \
  --start 1000 --end 1600 --target completion-42
```

Open the JSON in [Perfetto](https://ui.perfetto.dev). Its supported [Chrome trace format](https://perfetto.dev/docs/getting-started/other-formats) carries slices, arguments, counters and causal flows. The SVG has native hover details and bold dependency lines for the selected longest chain. Imported consumer slices retain incoming dependency evidence in `profile_dependencies`, because Perfetto does not import Chrome flow arguments. The exporter reserves that argument plus `event_id`, `duration_ns` and `display_duration_ns`. Counter names include their track identity so same-named series remain separate. Flow arrows attach to event starts; the graph's timing constraint uses source completion.

`--window` restricts exports to complete events inside `--start`/`--end`, retains the preceding counter values and records how many boundary dependencies were omitted. Without it, SVG zooming leaves the analysis graph intact.

`--target` computes the longest sum of work durations and declared delays among recorded paths ending at that event. It reports accounted time, elapsed time and the difference as **unassigned time**. This is a critical path only for a complete timing model: missing resource dependencies, unmeasured waits and incomplete captures can change the answer. It is not a prediction of speedup after changing the hardware. Equal-score paths use a deterministic ID tie break.

The source-fragment fixture's existing `phi_profile_timeline.py` accepts `--profile`, `--perfetto` and `--period-ns`. Its original SVG retains its causal-neighborhood highlighting. Its events are instants, so they do not alone establish a duration-weighted critical path. Repeated dependencies from aliased neighbors are retained as an edge's `multiplicity`.

Run `python3 tools/test_hls_profile.py` for format/graph tests. To check a real export with the official [Trace Processor](https://perfetto.dev/docs/analysis/trace-processor):

```sh
python3 tools/verify_perfetto_profile.py /path/to/trace_processor \
  timing.profile.json timing.perfetto.json
```

The check compares every imported event ID, nanosecond timestamp, duration, flow endpoint and counter sample; a successful JSON parse alone is insufficient.

Adapters may give a zero-duration boundary event `display_duration_ns` equal to its observed clock period. SVG and Perfetto draw that cycle as a block; `dur` and causal accounting remain unchanged. This denotes the cycle containing a handshake, not a measured computation latency. Include that distinction in event evidence. Visible bins on one track must not overlap, and a window retains only complete displayed bins. Native import verification checks the displayed durations as well as identities and causal endpoints.

The SVG labels blocks where space permits. Adapters can distinguish `service`, `wait`, `unknown` and `handshake` categories by color; classification must describe recorded evidence. A wait slice is elapsed dependency time, not resource occupation.
