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
inputs into `/home/ecpeterson/erl_xls-build/regsvc` on `192.168.64.7`, runs XLS
IR conversion, optimization, and Verilog generation there, and executes the
result with Icarus. It does not use or modify the VM's existing `~/erl_xls`
checkout.

The remote host and paths can be overridden with `ERL_XLS_REMOTE_HOST`,
`ERL_XLS_REMOTE_ROOT`, and `ERL_XLS_REMOTE_XLS`.

The RTL regression exercises application behavior and a separate debug AXIS
endpoint. See the [debug protocol](docs/debug-protocol.md) for that interface.
