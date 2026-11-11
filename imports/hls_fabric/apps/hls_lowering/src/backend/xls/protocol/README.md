# Source-protocol generation

`hls_protocol_transport` prepares source programs and receiver ownership through [protocol planning](../../../planning/protocol/README.md). `hls_local_actor` composes `xls_activation_codegen` with `xls_local_owner`; activation reuses [shared machine execution](../execution/README.md), while the local owner supplies receipt/action and clock ownership. `xls_protocol_inbox` installs the checked receiver layout.

Network, boundary, application, bridge, deployment and mixed builders compose larger bundles from the retained transport plan. Their `xls_protocol_*` helpers render compact codecs, links, ingress, arithmetic groups and wrappers; associated pins use the [Verilog adapters](../../sv/README.md). These are related composition stages within one backend, not separate packages or interchangeable execution modes.

Preserve emitted failure codebooks when composing actors. Planning and emission do not attach host sessions; runtime clients consume the resulting descriptors separately.

The optional [observation application](../../../../../hls_spacetime_observer/README.md) binds passive simulator taps to an exact emitted build; its capture adapter produces cycle events for offline consumers. See [passive capture](../../../../../../docs/spacetime-capture.md). These diagnostic observers generate no synthesized trace hardware and make no physical timing claim.

`hls_protocol_domain` composes one complete network with the compiled runtime lifecycle kernel, incarnation gates and actual reset/initialization completion. See [closed-domain recovery](../../../../../../docs/domain-recovery.md). The runtime kernel supplies its own compilable service entry, so hardware and ERTS share the same lifecycle decisions.
