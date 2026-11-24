# Target source responsibilities

`hls_target` interprets checked compiler, communication and implementation-plan values at a physical target boundary. It retains exact target choices and emits source or tool inputs; it does not own source semantics, logical routing, optimizer policy or live device sessions.

| Directory | Owns | Does not own |
| --- | --- | --- |
| [toolchain](toolchain/README.md) | Target profiles, installed support layouts, generated-file publication and artifact bundles | Cross-application CLI policy or implicit tool execution |
| [planning](planning/README.md) | Target bindings, source-protocol physical models, partition expansion, scheduler RAM/layout requests and inspection bindings | System-level optimization or runtime sessions |
| [backend/xls](backend/xls/README.md) | DSLX target composition and generated hardware-source metadata | Erlang source analysis or logical communication policy |
| [backend/sv](backend/sv/README.md) | Verilog adapters for compiled blocks, protocol ports and external memories | Actor semantics or deployed queue ownership |
| `characterization/` | Native physical catalogue and SDF validation adapters | Measurement execution, evidence authenticity or optimization decisions |
| [examples](examples/README.md) | Small target-build inputs used by the facade walkthrough | Generic compiler or transport policy |

Build orchestration starts in [`erl_hls`](../../erl_hls/src/README.md), which combines `hls_compile` artifacts, `hls_fabric` plans and target functions. `emit` returns retained source data; `write` is the explicit publication convenience. External XLS, simulation and implementation tools consume the published bundle through explicit drivers.

Runtime clients receive deployment descriptors and prepared inspection bindings, then attach them through [`hls_runtime`](../../hls_runtime/README.md). The runtime never loads this application. A system optimizer supplies a checked core `hls_implementation_plan`; target materialization cannot call `hls_spacetime` or reinterpret characterization as policy.

The application resource is `hls_target.app.src`; installed target support belongs to `../priv/`. See the [build walkthrough](../../../docs/hls_fabric/building.md) for commands and artifact boundaries.
