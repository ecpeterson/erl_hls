# Runtime source responsibilities

This is the source tree of the supervised `hls_fabric` runtime application. It depends on the shared `hls_runtime` library, not on `erl_hls` compiler implementations or `hls_lowering`. Runtime startup consumes retained service schemas, deployment bindings and inspection metadata; it does not recompile actors or normalize source topologies.

| Directory | Owns | Does not own |
| --- | --- | --- |
| [app](app/README.md) | OTP application startup and explicit node supervision | Compilation or physical device setup |
| [runtime](runtime/README.md) | Device sessions, routing, feedback, observation and virtual nodes | Hardware source generation |
| [wire](wire/README.md) | Retained message schemas, structural validation and encoding/decoding | Source discovery, I/O or queue ownership |

The separate [hls_lowering source tree](../../hls_lowering/src/README.md) owns build configuration, planning, target generators and example build inputs. Its usual path is `hls_fabric_cli → hls_build → hls_source_build / hls_scheduler_build → planning → backend → source bundle`. It depends on the runtime's retained contracts; the runtime has no reverse dependency. The umbrella supplies `erl_hls` for source semantics and `hls_runtime` for value codecs, actor adapters and brokers.

`rebar3 release -n hls` produces the build CLI closure. `rebar3 release -n hls_fabric` produces the runtime closure without compiler/lowering applications. These are package boundaries, not separate scheduling policies or plugin protocols.

## Repository support

Reusable DSLX templates and RTL inputs belong to `apps/hls_lowering/priv/`; test-only shells belong to `apps/hls_fabric/test/rtl/`. Maintained decoder sources, configurations, drivers and application tests belong to [hls_phi](../../hls_phi/README.md) and [hls_snowflake](../../hls_snowflake/README.md). [Platform assets](../../../platforms/README.md) own board shells, constraints, drivers and image packaging.

The application resource `hls_fabric.app.src` stays here. Production Erlang in both application source trees and `include/` uses the pinned `rebar3 fmt` configuration; see [source-quality checks](../../../docs/source-quality.md).
