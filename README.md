# `erl_xls`

Translate (certain) Erlang processes into XLS processes.  Interoperate them through simulation or through FPGA with native Erlang processes.

## Tests

Run the Erlang-side unit and CPU-reference tests locally:

```sh
rebar3 eunit
```

The generated-RTL regression uses the Linux UTM instance because XLS is not
available on macOS:

```sh
tools/xls_sim.sh
```

This regenerates `regsvc.x` from the Erlang source, copies only the required
inputs into `/home/ecpeterson/erl_xls-build/regsvc` on `192.168.64.7`, and runs
XLS IR conversion, optimization, and Verilog generation there. It then runs a
cycle-controlled two-process SystemVerilog routing scenario and the EUnit
application scenario through a VPI bridge. Independent application and debug
FIFO pairs carry the two physical AXI Stream paths. The runner does not use or
modify the VM's existing `~/erl_xls` checkout.

The remote host and paths can be overridden with `ERL_XLS_REMOTE_HOST`,
`ERL_XLS_REMOTE_ROOT`, and `ERL_XLS_REMOTE_XLS`.

GitHub Actions runs the same generated-RTL and bridged-EUnit regressions on
Ubuntu using a checksum-pinned XLS release. `tools/prepare_xls_sim.sh` creates
the portable simulation staging directory; `tools/remote_xls_sim.sh` executes
that directory on any Linux host with XLS, Erlang, and Icarus installed.

## OpenXC7 bitstream smoke test

An Apple-Silicon-native smoke test exercises the open-source Xilinx 7-series
flow against both the ZynqBerry's `xc7z010clg225-1` and an
`xc7z020clg484-2`. It generates the exact-package chip databases and then runs
Yosys, nextpnr-xilinx, Project X-Ray frame generation, and bitstream assembly.
The commands below pin Apio 1.5.1, openXC7 2026.08.20, and OSS CAD Suite
2026.08.19. The smoke script also verifies the tool-package build metadata
before using it.

Install Apio and its tool packages under the ignored `_build` directory using
Python 3.11 or newer (tested with Python 3.13):

```sh
python3 -m venv _build/openxc7/apio-venv
PIP_CACHE_DIR="$PWD/_build/openxc7/pip-cache" \
    _build/openxc7/apio-venv/bin/pip install apio==1.5.1
ERL_XLS_APIO_HOME="$PWD/_build/openxc7/apio-home"
export ERL_XLS_APIO_HOME
APIO_HOME="$ERL_XLS_APIO_HOME" \
APIO_REMOTE_CONFIG_URL="file://$PWD/test/openxc7/apio-1.5.x.jsonc" \
    _build/openxc7/apio-venv/bin/apio packages install
```

Then build both smoke bitstreams:

```sh
tools/openxc7_smoke.sh
```

Outputs and reports are written beneath `_build/openxc7/smoke`. The fixture's
constraints select pins known to exist in each FPGA package, but they are not
board constraints. Do not program these smoke bitstreams onto hardware. The
toolchain, Python environment, generated chip databases, and build outputs use
about 5 GiB in `_build` with the versions above. On an M2, the first build is
about 85 seconds including both chip databases; cached builds take about nine
seconds.

The debug monitor itself is written in XLS and lowered beside the application;
a small passive RTL tap keeps instrumentation ready signals out of the
application datapath. The shared EUnit scenario queries counters, committed
process state, and a bounded frame trace from Erlang, including trace overflow
and drain behavior. The SystemVerilog scenario additionally proves that routed
debug access remains available while application output is backpressured. See
the [debug protocol](docs/debug-protocol.md) for that interface.

The routed simulation hosts two independent `regsvc` instances behind each
shared stream. A 32-bit source/destination envelope precedes the existing
application or debug frame, and arbitration retains a selected endpoint through
`TLAST`. On the Erlang side, one `xls_fabric` process owns each physical stream
while distinct `xls_gs` proxy PIDs retain the ordinary `gen_server`-style API.
The regression checks isolated process state, concurrent calls, complete-frame
arbitration under backpressure, and debug access while application output is
blocked. Fabric endpoint addresses are transport identifiers, not Erlang PIDs.
The topology-specific Verilog composition used by Icarus is kept under
`test/rtl`; a production Vivado design can package the router and endpoint
boundaries independently and connect them in its block design.

## Translated record defaults

Every field in a private-state or wire record must have a type-directed zero
default:

```erlang
-record(state, {
    registers = xls_type:zero() :: xls_lists:list(xls_nums:u32(), 16)
}).
```

The `xls_pack` parse transform expands this marker into the corresponding
Erlang value using the field's type annotation. The XLS compiler uses the same
annotation to generate `zero!`, avoiding a duplicated type descriptor and
ensuring that CPU and hardware instances begin with the same record values.
