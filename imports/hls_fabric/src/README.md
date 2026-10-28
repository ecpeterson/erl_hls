# Source responsibilities

Start at [toolchain](toolchain/README.md) for a build request, [planning](planning/README.md) for checked application and placement data, or [runtime](runtime/README.md) for an attached device. These are ownership directories inside one `hls_fabric` application, not independent packages. `erl_hls` supplies source semantics, actor/service lowering, typed value codecs and the common broker interfaces.

| Directory | Owns | Does not own |
| --- | --- | --- |
| [app](app/README.md) | OTP application startup and node supervision | Compilation or physical device setup |
| [toolchain](toolchain/README.md) | Configuration loading, build selection, source bundles and CLI | XLS/Vivado execution |
| [planning](planning/README.md) | Checked topology, placement, retained source facts and layout decisions | Live sessions or final source rendering |
| [backend/xls](backend/xls/README.md) | DSLX lowering and hardware composition facades | Host queues or packet decoding |
| [backend/sv](backend/sv/README.md) | Verilog adapters for compiled blocks and external memories | Erlang source semantics |
| [wire](wire/README.md) | Packed message schemas and pure encoding/decoding | I/O, leases or queue ownership |
| [runtime](runtime/README.md) | Device sessions, routing, feedback, observation and virtual nodes | Hardware source generation |
| [examples](examples/README.md) | Concrete applications and their build/profiling adapters | Generic compiler or transport policy |

The usual build path is `hls_fabric_cli → hls_build → hls_source_build / hls_scheduler_build → planning → backend → source bundle`. A host later binds the bundle's descriptors through a runtime session; wire codecs translate complete messages while brokers own transport I/O. The [build walkthrough](../docs/building.md) describes the commands and artifact boundary.

Names do not substitute for ownership: some `hls_*` modules coordinate XLS composition, while `xls_*` layout authorities consume lowered facts without rendering DSLX. Each module's documentation identifies its callers and next stage. This map exposes current boundaries; compiler-dependent inspection helpers and plan-derived runtime bindings still share the same dependency graph until package extraction.

## Files outside this tree

`priv/xls/` contains installed DSLX support and small templates; `priv/rtl/` contains installed RTL inputs used by source bundles. Top-level `rtl/` contains simulation/device shells and other repository-level harnesses. `test/` owns focused witnesses and fixtures; `tools/` owns checks and external-tool drivers. `experiments/` still contains application and board investigations awaiting a separate promotion/retirement review. None of those directories is an alternate home for generic Erlang lowering. The application resource `hls_fabric.app.src` stays here so rebar3 discovers and packages the application normally.

Production Erlang in `src/` and `include/` is formatted with the pinned `rebar3 fmt` command. See [source-quality checks](../docs/source-quality.md).
