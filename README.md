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
XLS IR conversion, optimization, and Verilog generation there. It then runs
two Icarus checks: a deterministic SystemVerilog scenario (including the
independent debug AXIS endpoint), followed by the same EUnit application
scenario used for the CPU reference process. The latter reaches the simulated
RTL through a VPI bridge. Independent application and debug FIFO pairs carry
the two AXI Stream paths. The runner does not use or modify the VM's existing
`~/erl_xls` checkout.

The remote host and paths can be overridden with `ERL_XLS_REMOTE_HOST`,
`ERL_XLS_REMOTE_ROOT`, and `ERL_XLS_REMOTE_XLS`.

GitHub Actions runs the same generated-RTL and bridged-EUnit regressions on
Ubuntu using a checksum-pinned XLS release. `tools/prepare_xls_sim.sh` creates
the portable simulation staging directory; `tools/remote_xls_sim.sh` executes
that directory on any Linux host with XLS, Erlang, and Icarus installed.

The shared EUnit scenario uses the application stream and queries debug
counters and committed process state from Erlang. The SystemVerilog scenario
additionally proves that both kinds of debug query complete while application
output is backpressured. See the [debug protocol](docs/debug-protocol.md) for
that interface.

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
