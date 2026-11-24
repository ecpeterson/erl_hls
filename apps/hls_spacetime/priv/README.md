# External integration assets

Vendor extraction tools and their physical/timing validators belong to `hls_target`. This directory contains only Spacetime-owned recording support.

`include/spacetime_trace.h` owns the bounded C++ recording transport shared with the Erlang trace reader. Its eleven public fields describe the [protocol-stream dialect](../../../docs/hls_spacetime/trace-format.md), not arbitrary simulator interfaces. Producer harnesses supply taps and semantic interpretation.
