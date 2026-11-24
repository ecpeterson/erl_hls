# Umbrella applications

The product is split across seven OTP applications with explicit one-way ownership:

1. [`hls_core`](hls_core/README.md) owns process-free logical-system, implementation-plan and characterization contracts.
2. [`hls_runtime`](hls_runtime/README.md) owns live actor execution, device sessions, wire codecs and virtual-node supervision.
3. [`hls_compile`](hls_compile/README.md) owns source analysis and computation synthesis.
4. [`hls_fabric`](hls_fabric/README.md) owns communication synthesis, protocol projection and logical routing.
5. [`hls_target`](hls_target/README.md) owns physical materialization, tool support and characterization adapters.
6. [`hls_spacetime`](hls_spacetime/README.md) owns pure system-plan policy and offline execution analysis.
7. [`erl_hls`](erl_hls/README.md) is the CLI and orchestration facade over the lower applications.

Compile cannot call Fabric, target, Spacetime or the facade; Fabric cannot call target, Spacetime or the facade; target cannot call Spacetime or the facade. Runtime depends only on core and OTP. `hls_spacetime` consumes target-validated physical values, while target never calls the optimizer. The [system model](../docs/system-model.md) defines the value boundaries and complete dependency rule.

Additional packages have narrower roles:

- [`router`](router/README.md) provides rectangular multicast and ordered barriers to ERTS and managed endpoints.
- [`hls_phi`](hls_phi/README.md) and [`hls_snowflake`](hls_snowflake/README.md) are application examples and finite witnesses; generic libraries do not depend on them.
- [`hls_spacetime_observer`](hls_spacetime_observer/README.md) is the optional cross-layer capture adapter. Keeping it separate prevents its broad integration dependencies from entering lower applications.

The default profile builds the facade, core/runtime/synthesis/target applications, router and examples. `rebar3 as spacetime` adds the local Spacetime and observer applications. The `hls` release packages build tooling, `hls_examples` adds decoder tooling, and `hls_runtime` contains only the core/runtime deployment closure.
