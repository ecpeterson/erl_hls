# External integration assets

`tools/export_spacetime.tcl` is the read-only Vivado export boundary. It accepts an existing checkpoint and previously verified STA SDF files; it does not synthesize or implement a design.

`include/spacetime_trace.h` owns the bounded C++ recording transport shared with the Erlang trace reader. Its eleven public fields describe the [protocol-stream dialect](../docs/trace-format.md), not arbitrary simulator interfaces. Producer harnesses supply taps and semantic interpretation.
