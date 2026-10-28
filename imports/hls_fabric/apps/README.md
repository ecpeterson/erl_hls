# Library and example packages

- [hls_lowering](hls_lowering/README.md) owns generic build planning, target lowering and installed hardware support.
- [hls_phi](hls_phi/README.md) owns the complete Phi/noise application and its build/runtime witnesses.
- [hls_snowflake](hls_snowflake/README.md) owns the ordinary actor decoder, reference model and finite source-protocol example.

The root `hls_fabric` application owns transport and virtual-node runtime. Examples may call compiler, lowering and runtime APIs; generic libraries must not call the examples. Rebar compiles local applications together for development. Select `hls` for generic build tooling, `hls_examples` for optional decoder tooling, or `hls_fabric` for the deployed runtime closure.
