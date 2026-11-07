# hls_spacetime

Inspect saved FPGA execution as work spread over placed circuitry and clock cycles. The standalone Erlang library validates event/version histories, reads bounded simulator traces, and imports physical catalogues and timing sidecars. It starts no processes and depends only on OTP. Backend observation adapters stay with their producers; application stimuli stay with their applications.

The browser viewer consumes saved JSON without running the compiler, simulator or Vivado. It shows a rotatable clock stack, a synchronized flat chip and timeline, exact recorded dependencies, visible register load/hold connections and explicit mapping/ancestry gaps. Accesses and selected storage words show their supported physical spread by default. Recorded read/write masks select bits; reads without a mask retain explicitly labelled whole-word context. Optional native timing paths show the ordered placed-cell sequence separately from execution dependencies. Saved native route sidecars add tile-level wire/PIP topology, with partial and intra-site gaps. A complete computation attachment associates native combinational fan-in with every recorded write and shares the full circuit graph across clock layers; functionality and static-delay filters change the display without discarding evidence. The viewer does not infer metal centrelines, unrecorded read subsets, gate activity or a physical execution period.

## Local viewer

Node 22 or later is sufficient; the viewer has no package dependencies. Prepare any producer-validated bundle into a new directory, then serve it locally:

```sh
node scripts/prepare-view.mjs --bundle /path/to/bundle.json --output /path/to/fresh-view
npm start -- --data /path/to/fresh-view
```

Open the printed loopback URL. No capture is uploaded. “Open file” also accepts a prepared `spacetime-view` JSON projection. The [maintained workflow](docs/workflow.md) covers capture, native extraction, finite binding qualification, join, validation and routed-path attachment. It has no campaign-directory dependency. `prepare-example.mjs` remains the adapter for retained S3/S4 demonstration archives; it is not the entry point for new workloads. See [the viewer guide](docs/viewer.md) for controls and interpretation.

## Library and checks

Use OTP 28.0.2 and rebar3 3.24.0:

```sh
rebar3 escriptize
rebar3 eunit
rebar3 dialyzer
npm test
```

Read [the execution contract](docs/contract.md), [native import](docs/native.md), [sample-stream trace dialect](docs/trace-format.md), [optional RAM witness](docs/memory-witness.md), and [local source checks](docs/source-quality.md). The compiler-owned RAM primitive/testbench are supplied explicitly for the optional witness; the library has no compiler dependency.

`src/` owns validation and readers; `priv/` contains the recorder header and vendor extraction boundary; `web/` owns browser rendering and graph indexes; `scripts/` contains saved-file preparation and a read-only loopback server. Tests use localized fixtures. The authoritative [campaign plan](yap/spacetime-visualization.md) and evidence notes live in `yap/`.
