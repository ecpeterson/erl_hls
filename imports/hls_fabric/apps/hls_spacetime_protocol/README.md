# Passive source-protocol observation

`hls_spacetime_protocol` is an optional OTP library application for the XLS source-protocol backend. It reconstructs semantic events from a bounded simulator recording and the exact emitted source/IR/RTL; it does not lower an application or run in a deployed fabric node. `xls_protocol_spacetime` creates the tap plan, and `xls_protocol_spacetime_capture` interprets a recording through the standalone `hls_spacetime` contract. It has no application callback, supervisor or registered processes.

The root `spacetime` rebar3 profile adds this application and its pinned private `hls_spacetime` dependency. Ordinary compilation, tests and releases exclude both. From the repository root, with OTP 28.0.2 and access to `ecpeterson/hls_spacetime`:

```sh
rebar3 as spacetime compile
rebar3 as spacetime eunit --dir=apps/hls_spacetime_protocol/test
rebar3 as spacetime dialyzer
rebar3 fmt --check
```

See [capture instructions](../../docs/spacetime-capture.md) for supported boundaries and recording limits. The simulator harness belongs to [test assets](../../test/rtl/README.md); finite Phi stimulus and completion/readout interpretation belong to [Phi tests](../hls_phi/test/README.md). Generic trace readers, artifact validation, native physical import and viewing belong to the standalone `hls_spacetime` repository.
