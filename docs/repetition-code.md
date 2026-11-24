# Repetition-code application

The full repetition-code application, phenomenological noise actors, host closeout and hardware configurations are maintained in [`apps/hls_phi`](../apps/hls_phi/README.md). Follow the [Phi walkthrough](hls_fabric/execution/phi-walkthrough.md) for the maintained application and its execution paths.

`hls_compile` retains small actor, family-routing and codec fixtures without depending on the decoder package. The [connected telemetry project](../apps/erl_hls/src/examples/telemetry/README.md) teaches the compiler-only path from typed actors and a logical graph through CPU execution, source packaging and a finite RTL witness.
