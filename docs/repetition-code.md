# Repetition-code application

The full repetition-code application, phenomenological noise actors, host closeout and hardware configurations are maintained in [hls_fabric/apps/hls_phi](https://github.com/ecpeterson/hls_fabric/tree/main/apps/hls_phi). Follow its [Phi walkthrough](https://github.com/ecpeterson/hls_fabric/blob/main/docs/execution/phi-walkthrough.md) for the maintained application and its execution paths.

This compiler repository retains small actor, family-routing and codec fixtures; it does not depend on the decoder package. The [connected telemetry project](../src/examples/telemetry/README.md) teaches the compiler-only path from typed actors and a logical graph through CPU execution, source packaging and a finite RTL witness.
