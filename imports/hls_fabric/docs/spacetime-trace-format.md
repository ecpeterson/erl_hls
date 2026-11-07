# Protocol-stream recording boundary

The [standalone recording specification](https://github.com/ecpeterson/hls_spacetime/blob/main/docs/trace-format.md) owns the bounded `spacetime_cycle_trace` format, its C++ reader/writer and the Erlang reader. It is the fixed eleven-field, 32-bit protocol-stream dialect plus declared taps, not an arbitrary simulator interface.

Fabric's `test/rtl/protocol_spacetime_sim.cpp.in` supplies that interface and passive VPI taps. Its optional `xls_protocol_spacetime` adapter binds signal roles to the exact source/IR/RTL; `xls_protocol_spacetime_capture` converts accepted controls and enabled writes into events and version histories. Samples, bit equality and transitions alone do not establish transaction identity or data dependencies.

See [capture instructions](spacetime-capture.md) for compilation, include paths, live/replay/drive modes, budgets and the boundary between generic recording and backend interpretation. Keep format changes and rejecting transport tests together in `hls_spacetime`; qualify a changed observer ABI against its backend separately.
