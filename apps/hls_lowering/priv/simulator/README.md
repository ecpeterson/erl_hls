# External simulator support

`framed_fifo_stream.h` supplies bounded host FIFO traffic for source-protocol simulators. It belongs to the lowering toolchain's external simulation boundary and starts no Erlang services. Existing RTL tests and the optional spacetime observer use the same header; application stimulus stays with each test or application.
