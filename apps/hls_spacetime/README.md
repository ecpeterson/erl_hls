# hls_spacetime

Inspect saved FPGA execution as work spread over placed circuitry and clock cycles. The standalone Erlang library validates event/version histories, reads bounded simulator traces, and imports physical catalogues and timing sidecars. It starts no processes and depends only on OTP. Backend observation adapters stay with their producers; application stimuli stay with their applications.

The browser viewer consumes saved JSON without running the compiler, simulator or Vivado. Its depth-tested 3D scene places computation routes within clock layers and storage links between them. Orbit, pan, zoom and a movable clock window reveal the spatial spread and residence of recorded values; the evidence inspector and flat chip are optional. Computation circuits retain every recorded write's structural fan-in, with function and static cone-delay colors. Prepared rendering indexes keep the complete source evidence separately retained instead of loading the entire native graph into the browser. Unknown mappings and ancestry stay explicit. The display does not infer metal centrelines, unrecorded read subsets, gate activity or a physical execution period.

## Local viewer

Node 22 or later is sufficient; the viewer has no package dependencies. Prepare any producer-validated bundle into a new directory, then serve it locally:

```sh
node scripts/prepare-view.mjs --bundle /path/to/bundle.json --output /path/to/fresh-view
npm start -- --data /path/to/fresh-view
```

For a publication containing complete computation circuits, prepare its rendering indexes once before serving:

```sh
node scripts/prepare-render.mjs --input /path/to/computation-publication --output /path/to/fresh-render-view
npm start -- --data /path/to/fresh-render-view
```

Use `--capture RECORDING_FILE` if the publication contains more than one computation capture. This offline step retains the original recording and native tables alongside a hash-bound rendering derivative; it runs no new measurement. See [computation routing](docs/computation-routing.md#prepare-rendering-indexes) for its inputs and limits.

Open the printed loopback URL. No capture is uploaded. “Open file” also accepts a prepared `spacetime-view` JSON projection. The [maintained workflow](docs/workflow.md) covers capture, native extraction, finite binding qualification, join, validation and routed-path attachment. It has no campaign-directory dependency. `prepare-example.mjs` remains the adapter for retained S3/S4 demonstration archives; it is not the entry point for new workloads. See [the viewer guide](docs/viewer.md) for controls and interpretation.

## Timing diagnostics

Generate an [explainable timing report](docs/timing-report.md) from a saved computation publication:

```sh
node scripts/report-timing.mjs --input /path/to/computation-publication --output /path/to/fresh-report
```

The report retains every selected write, one representative maximizing source-to-sink chain per known cone, logic/net contributions and explicit timing/mapping gaps. It runs no native tools and does not infer an achieved clock period.

## Library and checks

Use OTP 28.0.2 and rebar3 3.24.0:

```sh
rebar3 escriptize
rebar3 eunit
rebar3 dialyzer
npm test
```

Read [the execution contract](docs/contract.md), [native import](docs/native.md), [sample-stream trace dialect](docs/trace-format.md), [optional RAM witness](docs/memory-witness.md), and [local source checks](docs/source-quality.md). The compiler-owned RAM primitive/testbench are supplied explicitly for the optional witness; the library has no compiler dependency.

`src/` owns validation and readers; `priv/` contains the recorder header and vendor extraction boundary; `web/` owns browser rendering and graph indexes; `scripts/` contains saved-file preparation and a read-only loopback server. Tests use localized fixtures. The [campaign evidence index](yap/spacetime-visualization.md) and historical records live in `yap/`; the Notes master roadmap (`Notes/erl_xls/Roadmap.md`) is the sole active task list.
