# Register-service server

`regsvc.erl` provides client helpers plus `hls_gs` callbacks for register reads, masked writes and bounded bulk replies. `hls_pack` adds the record codecs; `hls_gs` runs the callbacks on CPU or provides a fabric proxy for generated hardware.

`regsvc.erl.x` is generated DSLX. `regsvc_core_adapter.v` and `regsvc_debug_top.v` connect the generated service in the example RTL fixture. The simulation scripts and tests own execution; this directory does not implement a general deployment shell.

Use this example to trace an ordinary call/cast compilation path. Shared codec operations belong to `api/`, compiler passes to `backend/`, and device/session handling to `runtime/`.
