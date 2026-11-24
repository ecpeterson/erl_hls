# Live Fabric runtime

This directory is the supervised transport portion of `hls_runtime`. It consumes retained service schemas, deployment bindings and inspection metadata; it does not recompile actors, derive logical routes or normalize source topologies.

| Directory | Owns | Does not own |
| --- | --- | --- |
| [app](app/README.md) | `hls_runtime` application startup and explicit node supervision | Compilation or physical device setup |
| [runtime](runtime/README.md) | Device sessions, live routing, feedback, observation and virtual nodes | Hardware source generation or route planning |
| [wire](wire/README.md) | Retained message schemas, structural validation and encoding/decoding | Source discovery, I/O or queue ownership |

The [`hls_target` source tree](../../../hls_target/src/README.md) owns physical build configuration, materialization and target generators. The `hls_fabric` application owns process-free communication synthesis. Neither is loaded by this runtime. The umbrella supplies `hls_core` for shared values and contracts; deployed code supplies already-retained descriptors to the explicit runtime APIs.

`rebar3 release -n hls_fabric` produces the core/runtime closure without synthesis or optimizer applications. This legacy release name identifies the virtual-node product, not application ownership.

Reusable target DSLX and RTL belong to `apps/hls_target/priv/`; runtime tests contain only the shells and fixtures needed to exercise live boundaries. The application resource is [`hls_runtime.app.src`](../hls_runtime.app.src). Production formatting and source contracts are described in [source-quality](../../../../docs/source-quality.md).
