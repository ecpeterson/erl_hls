# Native openXC7 bitstream smoke test

This experiment checks whether the open-source Xilinx 7-series toolchain can
produce Zynq-7000 bitstreams natively on Apple Silicon. It targets both the
ZynqBerry's `xc7z010clg225-1` and an `xc7z020clg484-2`, generating any missing
exact-package chip databases before running Yosys, nextpnr-xilinx, Project
X-Ray frame generation, and bitstream assembly.

The setup below pins Apio 1.5.1, openXC7 2026.08.20, and OSS CAD Suite
2026.08.19. `run.sh` also verifies the tool-package build metadata before using
it.

## Setup

From this directory, install Apio and its tool packages into ignored,
experiment-local directories. Apio requires Python 3.11 or newer; this was
tested with Python 3.13.

```sh
python3 -m venv .venv
PIP_CACHE_DIR="$PWD/pip-cache" \
    .venv/bin/pip install apio==1.5.1
APIO_HOME="$PWD/.apio" \
APIO_REMOTE_CONFIG_URL="file://$PWD/apio-1.5.x.jsonc" \
    .venv/bin/apio packages install
```

The Python environment, toolchain, generated chip databases, and build outputs
use about 5 GiB with these versions.

## Build

```sh
./run.sh
```

Outputs and reports are written beneath `build/`. On an M2, the first build is
about 85 seconds including both chip databases; cached builds take about nine
seconds. Repeated builds report a checksum of the deterministic Project X-Ray
frames rather than of the final `.bit`, whose metadata includes the build time
and input path.

The XDC files select pins known to exist in each FPGA package solely to make
place-and-route possible. They are not board constraints. Do not program these
smoke bitstreams until the pins and I/O-bank voltages have been checked against
the corresponding board schematic.
