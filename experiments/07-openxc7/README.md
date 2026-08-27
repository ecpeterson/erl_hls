# Native openXC7 experiments

This experiment checks whether the open-source Xilinx 7-series toolchain can
build `erl_xls` designs natively on Apple Silicon. It has two targets:

- a small counter smoke test for `xc7z010clg225-1` and `xc7z020clg484-2`; and
- the current two-process, packet-routed `regsvc` fixture, including a separate
  routed debug path and both instrumentation monitors.

The flow generates exact-package chip databases and runs Yosys,
nextpnr-xilinx, Project X-Ray frame generation, and bitstream assembly. By
default, openXC7 packages and outputs remain in ignored directories beneath
this experiment.

## Setup

From this directory, install Apio and its packages into the experiment-local
directories. Apio requires Python 3.11 or newer; this setup was tested with
Python 3.13.

```sh
python3 -m venv .venv
PIP_CACHE_DIR="$PWD/pip-cache" \
    .venv/bin/pip install apio==1.5.1
APIO_HOME="$PWD/.apio" \
APIO_REMOTE_CONFIG_URL="file://$PWD/apio-1.5.x.jsonc" \
    .venv/bin/apio packages install
```

The package manifest pins openXC7 2026.08.20 and OSS CAD Suite 2026.08.19.
Every build verifies the installed package metadata before using it. The
environment, toolchain, chip databases, and build outputs use about 5 GiB
before the much larger `regsvc` netlists and routing files are generated.

## Counter smoke test

```sh
./run.sh
```

This builds both exact parts at a 100 MHz target. Outputs are written beneath
`build/smoke/`. On an M2, the first run takes about 85 seconds including both
chip databases; a cached run takes about nine seconds.

## Export the generated `regsvc` RTL

XLS remains on the Linux UTM, so first export a fresh, verified RTL set:

```sh
./fetch_regsvc_rtl.sh
```

The exporter creates fresh local and remote stages, runs local EUnit, checks
the pinned remote XLS version, and runs the complete generated-RTL/Icarus
regression on UTM. It retrieves exactly the five generated modules needed by
the routed fixture, verifies their top module names, records input and output
SHA-256 hashes, and atomically publishes the result at
`build/regsvc/generated-rtl/`.

Rerun the exporter after changing the compiler, generated DSLX inputs, or
`regsvc`. The build script resolves the published result to an immutable
content-addressed release, checks its XLS version and output hashes, and
verifies the live handwritten RTL inputs against the same manifest.

The UTM defaults match the main simulation flow. They can be overridden with
`ERL_XLS_REMOTE_HOST`, `ERL_XLS_REMOTE_ROOT`, and `ERL_XLS_REMOTE_XLS`.

## Build the routed pair

```sh
./run_regsvc.sh
```

The default target is `xc7z020clg484-2`. The script first synthesizes the
four-interface logical fixture out of context for an architectural resource
estimate. It then simulates, synthesizes, and routes a two-pin compile harness.
The harness enumerates application and debug test cases for both endpoints,
uses LFSRs for payload and flow-control variation, and folds all responses into
a registered rotating digest. A flip-flop-retention check guards against
pruning translated-process state without pretending that PS-facing AXI streams
are physical board pins or creating one large combinational output path.

The same design can be retried explicitly on the smaller part:

```sh
./run_regsvc.sh xc7z010clg225-1
```

`all` requests the `xc7z020` build followed by the `xc7z010` attempt. Timing
misses are retained in the reports and do not prevent bitstream assembly;
placement or routing failures still stop the build.

## Current result

The raw routed pair synthesizes to an estimated 16,546 logic cells and 21,724
flip-flops. It infers no block RAM or DSP resources: the current generated
FIFOs, trace buffers, and state snapshots expand into LUTs and registers.

The compile harness successfully places, routes, and assembles for
`xc7z020clg484-2`. A representative deterministic run uses 21,627 of 106,400
`SLICE_LUTX` sites and 21,881 of 106,400 `SLICE_FFX` sites. It reaches 44.21
MHz against the requested 100 MHz; the critical path is about 0.9 ns of logic
and 21.7 ns of routing across the debug snapshot handshake. This is a useful
baseline, not a timing-closed implementation.

The same pair packs to 61% of LUT and 62% of flip-flop sites on
`xc7z010clg225-1`, but the pinned nextpnr cannot produce a legal placement with
the tested placers and settings. Reducing register-expanded instrumentation
storage is therefore the clearest next step before treating the smaller device
as a routed-pair target.

The `xc7z020` place-and-route takes roughly 20 minutes on the M2. Machine-
readable Yosys statistics and nextpnr timing/utilization reports are retained
under `build/regsvc/`.

## Bitstream safety and scope

The XDC files select package-valid pins solely to make place-and-route
possible. They are not board constraints. Do not program any bitstream from
this experiment until the pins and I/O-bank voltages have been checked against
the corresponding board schematic.

This is a PL compile proof. It does not instantiate PS7, exercise DMA, validate
a board design, or demonstrate the harness transactions in silicon. A focused
Icarus test checks application tags 3–10 and debug tags 1–4 at both endpoints
and observes application and debug responses. The existing routed RTL and
bridged EUnit regressions remain the fuller behavioral correctness checks.

Repeated builds print a checksum of deterministic Project X-Ray frames rather
than the final `.bit`, whose metadata includes its build time and input path.
