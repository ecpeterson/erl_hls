# Passive source-protocol observation

`hls_spacetime_protocol` is an optional OTP library application for the XLS source-protocol backend. It reconstructs semantic events from a bounded simulator recording and the exact emitted source/IR/RTL; it does not lower an application or run in a deployed fabric node. Planning uses installed lowering/compiler renderers for exact source checks and writes no hardware. The adapter has no application callback, supervisor or registered processes.

`xls_protocol_spacetime` creates the tap plan. `xls_protocol_spacetime_capture` records register/semantic events, applies the following interpretation stages, and validates the resulting standalone `hls_spacetime` graph:

- `xls_protocol_spacetime_stream` checks retained gateway composition and joins accepted endpoint frames to public output by route and occurrence.
- `xls_protocol_spacetime_publication` checks transport ownership, pending retirement and capture leases to connect observed source publications to arrivals, capture writes and endpoint transfers. Unsupported or unobserved ownership stays unresolved.
- `xls_protocol_spacetime_dependencies` prepares and evaluates the bounded scalar XLS expression plan. `xls_protocol_spacetime_ancestry` compares known results with observed enabled D values and adds selected operand reads from pre-edge register versions. Same-edge writes do not replace those read versions early.

`capture/3` returns the generic `bundle` plus backend `stream`, `publication` and `ancestry` sidecars when their plan sections are present; `bundle/3` returns only the graph. Read masks and separate data/control masks describe selected operational encoded bits, not source-layout offsets, sensitized gates or native paths. Sidecar masks use hexadecimal text. Unrepresented small state, external inputs and unsupported expressions remain explicit unknown roots. These are finite recorded dependencies and value checks; physical placement/timing and all-input equivalence remain separate evidence.

The root `spacetime` rebar3 profile adds this application and its pinned private `hls_spacetime` dependency. Ordinary compilation, tests and releases exclude both. From the repository root, with OTP 28.0.2 and access to `ecpeterson/hls_spacetime`:

```sh
rebar3 as spacetime compile
rebar3 as spacetime eunit --dir=apps/hls_spacetime_protocol/test
rebar3 as spacetime dialyzer
rebar3 fmt --check
```

See [capture instructions](../../docs/spacetime-capture.md) for supported boundaries and recording limits. The simulator harness belongs to [test assets](../../test/rtl/README.md); finite Phi stimulus and completion/readout interpretation belong to [Phi tests](../hls_phi/test/README.md). Generic trace readers, artifact validation, native physical import and viewing belong to the standalone `hls_spacetime` repository.
