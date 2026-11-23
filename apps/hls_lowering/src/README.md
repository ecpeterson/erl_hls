# Build library source responsibilities

`hls_lowering` owns source preparation, checked composition and hardware generation. It depends on the `erl_hls` compiler and on retained contracts in `hls_runtime` and `hls_fabric`. It has no application callback or supervisor; its public functions do not start devices as a side effect of planning or emission.

| Directory | Owns | Does not own |
| --- | --- | --- |
| [toolchain](toolchain/README.md) | Build requests, CLI, selected policy and portable source bundles | XLS/Vivado execution |
| [planning](planning/README.md) | Checked topology, placement, source facts and physical layouts | Live sessions or final source rendering |
| [backend/xls](backend/xls/README.md) | DSLX lowering and hardware composition facades | Host queues or packet decoding |
| [backend/sv](backend/sv/README.md) | Verilog adapters for compiled blocks and external memories | Erlang source semantics |
| [examples](examples/README.md) | The tiny counter build walkthrough | Generic compiler or transport policy |

Start with `hls_build:plan/1` or the `hls-fabric` CLI. Keep retained compiler artifacts and checked plans through composition; `emit` returns data and `write` publishes files. Optional external tools consume the emitted bundle. Planning is deliberately not backend-neutral: retained facts may include XLS source, graph lowering and physical RAM layouts.

Planning and XLS generation group the channel scheduler, source protocol and legacy partition paths into matching subdirectories. [Shared execution support](backend/xls/execution/README.md) serves both public backends. These groups organize one `hls_lowering` application and module namespace; they do not enforce package boundaries or change which helpers callers may reuse.

Runtime clients receive descriptors and prepared inspection bindings, then attach them through [hls_fabric](../../hls_fabric/src/README.md). Source-dependent conveniences such as `hls_shared_debug_catalog:hardware/4` and `hls_node_topology:bind_debug/4` remain in this build library. Runtime attachment uses their retained results without loading these modules.

The application resource is `hls_lowering.app.src`; installed target support belongs to `../priv/`. See the [build walkthrough](../../../docs/hls_fabric/building.md) for development commands and artifact boundaries.
