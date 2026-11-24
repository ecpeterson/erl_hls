# Verilog boundaries around XLS

These adapters connect separately generated XLS hardware to the surrounding RTL. They render named pins, RAM declarations and wrapper instances; actor and protocol algorithms remain in compiler-generated or shared DSLX. This is not an alternative behavioral backend.

- `sv_protocol_ports` renders the sampled-clock pin adapter used by [protocol](../xls/protocol/README.md) transport, network, boundary and bridge generators.
- `sv_protocol_application` connects the application gateway, activation bridge and emitted boundary. `sv_protocol_inspection` contributes the existing inspection-service connections.
- `sv_domain_supervisor` connects the compiled static supervisor to child domains. `sv_domain_channels` connects separately resettable partitions to their incarnation-bound crossing channels; both leave lifecycle and transport decisions in compiled Erlang/DSLX.
- `xls_scheduler_ram_v` derives scheduler RAM bindings and renders their wires, application ports and 1R1W instances. Its historical `xls_` name describes the ports being adapted; the output language is Verilog. [xls_scheduler_ram_dslx](../xls/scheduler/xls_scheduler_ram_dslx.erl) owns the matching ordered DSLX endpoint signatures.

These mechanical adapters remain together; their corresponding XLS owners supply the behavioral grouping.

Public scheduler builds expose RAM bindings and support fragments for an enclosing shell; they do not automatically emit a complete board design. Keep board-specific pin assignment, synthesis constraints and device tooling outside these generic wrappers. RTL support modules live under `priv/rtl/`; reusable ownership and widths come from [planning](../../planning/README.md) or the corresponding [XLS generator](../xls/README.md), not copied constants.
