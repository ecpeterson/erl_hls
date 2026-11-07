# hls_spacetime

Inspect saved FPGA execution as work spread over placed circuitry and clock cycles. The standalone Erlang library validates event/version histories, reads bounded simulator traces, and imports physical catalogues and timing sidecars. It starts no processes and depends only on OTP. Backend observation adapters stay with their producers; application stimuli stay with their applications.

The browser viewer consumes saved JSON without running the compiler, simulator or Vivado. It shows a rotatable clock stack, a synchronized flat chip and timeline, exact recorded dependencies, storage residence and explicit mapping/ancestry gaps. It does not infer routed geometry or a physical execution period.

## Local viewer

Node 22 or later is sufficient; the viewer has no package dependencies. Prepare the retained example from the external S3/S4 archive directories, then serve it locally:

```sh
node scripts/prepare-example.mjs \
  --physical-archive /path/to/spacetime-2026-11-06/physical-1 \
  --capture-archive /path/to/spacetime-2026-11-06/capture-1 \
  --output web/data
npm start
```

Open the printed loopback URL. `web/data/` is ignored; no capture is uploaded. “Open file” also accepts a prepared `spacetime-view` JSON projection. The full original evidence stays in the external archive, with content identities in the projection. See [the viewer guide](docs/viewer.md) for controls and interpretation.

## Library and checks

Use OTP 28.0.2 and rebar3 3.24.0:

```sh
rebar3 eunit
rebar3 dialyzer
npm test
```

Read [the execution contract](docs/contract.md), [native import](docs/native.md), [protocol-stream trace dialect](docs/trace-format.md), [optional RAM witness](docs/memory-witness.md), and [local source checks](docs/source-quality.md). The compiler-owned RAM primitive/testbench are supplied explicitly for the optional witness; the library has no compiler dependency.

`src/` owns validation and readers; `priv/` contains the recorder header and vendor extraction boundary; `web/` owns browser rendering and graph indexes; `scripts/` contains saved-file preparation and a read-only loopback server. Tests use localized fixtures. The authoritative [campaign plan](yap/spacetime-visualization.md) and evidence notes live in `yap/`.
