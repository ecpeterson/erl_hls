# Passive spacetime observation

`hls_spacetime_observer` is an optional OTP library application for the XLS source-protocol backend. It reconstructs semantic events from a bounded simulator recording and the exact emitted source/IR/RTL; it does not lower an application or run in a deployed fabric node. Planning uses installed compiler, communication and target renderers for exact source checks and writes no hardware. The adapter has no application callback, supervisor or registered processes. Its `xls_protocol_spacetime_*` module names identify the supported backend; the application name identifies its observation role.

`xls_protocol_spacetime` creates the tap plan. `xls_protocol_spacetime_capture` records register/semantic events, applies the following interpretation stages, and validates the resulting standalone `hls_spacetime` graph:

- `xls_protocol_spacetime_stream` checks retained gateway composition and joins accepted endpoint frames to public output by route and occurrence.
- `xls_protocol_spacetime_publication` checks transport ownership, pending retirement and capture leases to connect observed source publications to arrivals, capture writes and endpoint transfers. Unsupported or unobserved ownership stays unresolved.
- `xls_protocol_spacetime_dependencies` prepares and evaluates the bounded scalar XLS expression plan. `xls_protocol_spacetime_ancestry` compares known results with observed enabled D values and adds selected operand reads from pre-edge register versions. Same-edge writes do not replace those read versions early.

`capture/3` returns the generic `bundle` plus backend `stream`, `publication` and `ancestry` sidecars when their plan sections are present; `bundle/3` returns only the graph. Read masks and separate data/control masks describe selected operational encoded bits, not source-layout offsets, sensitized gates or native paths. Sidecar masks use hexadecimal text. Unrepresented small state, external inputs and unsupported expressions remain explicit unknown roots. These are finite recorded dependencies and value checks; physical placement/timing and all-input equivalence remain separate evidence.

A semantic `operand_read` records the current word supplied to receiver admission or publication; its absent `read_mask` means the consumed bit subset is unknown. Even a complete source payload copy can lose unused bits during XLS optimization. A `selected_operand_read` instead carries the exact mask obtained from the evaluated encoded expression, including selector controls. Do not fill semantic snapshots with all-one masks or borrow a nearby numerical read’s mask: their consumers need not match. A `read_result` retains the version selected by its request and does not establish another physical access location.

The root `spacetime` rebar3 profile adds this application and the local `hls_spacetime` application. Ordinary compilation, tests and releases exclude both. From the repository root with OTP 28.0.2:

```sh
rebar3 as spacetime compile
rebar3 as spacetime eunit --dir=apps/hls_spacetime_observer/test
rebar3 as spacetime dialyzer
rebar3 fmt --check
```

`xls_protocol_spacetime_workflow` packages exact simulator inputs, interprets saved recordings and writes qualified physical claims through `bin/hls-spacetime-observer`. Application stimulus and external compiler/simulator execution stay with the caller.

See [capture instructions](../../docs/hls_fabric/spacetime-capture.md) for supported boundaries and recording limits. The packaged simulator harness belongs to [observer support](priv/simulator/README.md); finite Phi stimulus and completion/readout interpretation belong to [Phi tests](../hls_phi/test/README.md). Generic trace readers, artifact validation and viewing belong to the local `hls_spacetime` application; native physical import and timing adapters belong to `hls_target`.
