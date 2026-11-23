# Passive simulator harness

`protocol_spacetime_sim.cpp.in` is the source-protocol recorder/replay boundary, packaged with the optional observer. `xls_protocol_spacetime_workflow` derives its fault expression from the verified actor population and writes the complete simulator closure. It is simulator-only support, not deployed RTL or application stimulus. Generic recording transport belongs to `hls_spacetime`; the framed host FIFO helper belongs to `hls_lowering`.
