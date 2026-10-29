# Source-protocol generation

`hls_protocol_transport` prepares source programs and receiver ownership through [protocol planning](../../../planning/protocol/README.md). `hls_local_actor` composes `xls_activation_codegen` with `xls_local_owner`; activation reuses [shared machine execution](../execution/README.md), while the local owner supplies receipt/action and clock ownership. `xls_protocol_inbox` installs the checked receiver layout.

Network, boundary, application, bridge, deployment and mixed builders compose larger bundles from the retained transport plan. Their `xls_protocol_*` helpers render compact codecs, links, ingress, arithmetic groups and wrappers; associated pins use the [Verilog adapters](../../sv/README.md). These are related composition stages within one backend, not separate packages or interchangeable execution modes.

Preserve emitted failure codebooks when composing actors. Planning and emission do not attach host sessions; runtime clients consume the resulting descriptors separately.
