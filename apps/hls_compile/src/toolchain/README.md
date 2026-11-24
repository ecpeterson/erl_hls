# Compiler support boundary

`hls_build_sources` compiles declared Erlang sources in memory under their explicit source contexts. `hls_compile_support` locates the installed computation DSLX library and prepares compiler-only support layouts. Neither module selects communication policy, adds target resources or publishes an artifact bundle.

User-facing commands and cross-application orchestration live in [`erl_hls`](../../../erl_hls/src/toolchain/README.md). Target support aggregation, publication and external-tool drivers live in [`hls_target`](../../../hls_target/src/toolchain/README.md).
