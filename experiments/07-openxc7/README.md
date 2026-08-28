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
a registered rotating digest. Flip-flop and block-RAM retention checks guard
against pruning translated-process state or the four trace RAM primitives without
pretending that PS-facing AXI streams are physical board pins or creating one
large combinational output path.

The same design can be retried explicitly on the smaller part:

```sh
./run_regsvc.sh xc7z010clg225-1
```

`all` requests the `xc7z020` build followed by the `xc7z010` attempt. Timing
misses are retained in the reports and do not prevent bitstream assembly;
placement or routing failures still stop the build.

## Current result

| design | estimated logic cells | flip-flops | `RAMB36E1` |
| --- | ---: | ---: | ---: |
| register-backed trace baseline | 16,546 | 21,724 | 0 |
| block-RAM-backed trace | 12,542 | 16,454 | 4 |

Moving bounded trace events out of the observer's recurrent state reduces both
estimated logic cells and flip-flops by about 24%. Each instrumented hardware
endpoint uses two `RAMB36E1` primitives for its 128-bit-wide physical store, so
this two-endpoint fixture uses four and an otherwise identical N-endpoint
design would use 2N. Logical ping-pong banks share that physical store rather
than doubling it. Host-side `xls_gs` proxy processes do not themselves consume
FPGA memory. The resource regression requires exactly four block RAMs to
survive both raw-pair and compile-harness synthesis.

The compile harness successfully places, routes, and assembles for
`xc7z020clg484-2`. The deterministic run uses 14,527 of 106,400 `SLICE_LUTX`
sites, 16,611 of 106,400 `SLICE_FFX` sites, and 4 of 140 `RAMB36E1` sites. It
reaches 48.32 MHz against the requested 100 MHz. The critical path is now in
the translated application service, at about 1.8 ns of logic and 18.9 ns of
routing, rather than in the debug snapshot handshake. This is a useful compile
proof, not a timing-closed implementation.

For `xc7z010clg225-1`, nextpnr reports 41% of its logical `SLICE_LUTX` BELs,
47% of flip-flops, and 6% of block-RAM sites, but cannot produce a legal
placement. The LUT denominator counts the O5 and O6 BELs associated with
17,600 physical LUTs; those paired outputs are not independently placeable, so
41% is not a physical-LUT occupancy figure. The analytical placer cannot
legalize the design, while a separate simulated-annealing attempt completes
annealing but fails the post-placement validity check; neither reaches routing.

A one-off subsystem ablation narrows the threshold. The application pair,
Observer pair with compact server stubs, DebugServer pair with compact observer
stubs, and an application pair with only one instrumented endpoint all route.
Two complete debug endpoints still fail placement even when the application
cores are replaced with small state-producing stubs. Disabling carry-chain
inference does not change that outcome, so the carry primitive named by one
legalization error is not itself the bottleneck.

Because those stubs alter substantial logic, the ablation does not yet isolate
one construct as the cause. The leading design-side hypothesis is the wide
Observer–DebugServer boundary: each server retains an 875-bit snapshot which
includes a 512-bit committed application state. Replacing only that handoff
with operation-specific narrow transfers or a memory-backed snapshot is the
confirming experiment. A revision-matched nextpnr and database bisect is also
warranted before assuming every failure is intrinsic to the part.

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
