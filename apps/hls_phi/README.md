# Phi decoder example

`hls_phi` owns the complete Phi/noise application: actors and shared headers, logical topologies, source-protocol and scheduler configurations, finite CPU/runtime drivers, provider DSLX and application-specific RTL templates. It consumes computation, communication, target and runtime APIs through the facade; none of those product applications depends on this example. Its host loops do not run unless explicitly invoked.

Build the optional examples release for the repetition CLI:

```sh
rebar3 release -n hls_examples
_build/default/rel/hls_examples/bin/hls-repetition --width 6 --split 3 --output _build/repetition-pair
```

This emits source for two three-cell roles. External XLS compilation and actual board deployment are separate steps. The generic `hls` build release and the `hls_fabric` runtime release do not include the decoders.

| Directory | Responsibility |
| --- | --- |
| [src](src/README.md) | Actor behavior, geometry, finite closeout and application build composition |
| [include](include/README.md) | Wire records and shared actor bodies with selected geometry |
| [priv/rtl](priv/rtl/README.md) | Application shell templates resolved through `code:priv_dir(hls_phi)` |
| [tools](tools/README.md) | Checkout-only external compilation, simulation and profile drivers |
| [test](test/README.md) | Application semantics, compiler application witnesses and RTL integration fixtures |

The ordinary host entry is `phi_memory_runner`, which feeds events through the pure `phi_memory_experiment` reducer and sends ordered commands through the runtime transport or `phi_memory_cpu_fabric`. `phi_protocol_repetition` performs finite source-protocol correction feedback and readout. These examples motivate toolchain development; their witnesses are not general decoder convergence or live-device qualification.

Board shells and installation belong to [XC7 platforms](../../platforms/xc7/README.md).
