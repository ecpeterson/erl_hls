# Target lowering and hardware composition

This directory contains hardware generators and the build facades that coordinate them. The module prefix is not the classification rule: an `hls_protocol_*` builder belongs here when it prepares a retained source build and composes emitted XLS artifacts. Conversely, lower-only graph and physical-layout authorities live in [planning](../planning/README.md), even when their names retain `xls_`.

- [xls](xls/README.md) owns DSLX lowering, source artifact composition, physical execution fragments and associated interface metadata.
- [sv](sv/README.md) owns SystemVerilog/Verilog adapters around compiled XLS blocks and external memories.

The public [build frontend](../toolchain/README.md) selects the execution backend and assembles its output bundle. These modules do not invoke XLS executables or Vivado; optional external drivers consume that bundle. Runtime sessions and retained wire codecs belong to the separate `hls_fabric` application. These backend subdirectories share the `hls_lowering` library and module namespace; they are not additional packages or plugins.

Shared hardware algorithms belong in the installed DSLX support under `hls_lowering`'s `priv/xls/` where possible. Erlang derives checked dimensions and heterogeneous connections, retains structured artifacts and failure codebooks, and emits source at the final boundary. `emit` returns data, while `write` is the explicit file-output convenience; individual contracts describe the bundle or fragment returned.
