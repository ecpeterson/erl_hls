# Simulation shells and test assets

This directory owns handwritten testbench compositions, finite scoreboards and host/simulator adapters for the fabric libraries. The corresponding drivers in [tools](../../../../tools/hls_fabric/) supply generated hardware and retain logs in build stages. These files are not installed production RTL or board shells.

- Transport/component benches cover async FIFOs, return routes, credit links, packed framing and fault handling. `hls_device_services.sv` is the register-service test composition, while the reusable FIFO and route implementations live in [installed support](../../../hls_lowering/priv/rtl/README.md).
- Actor and scheduler benches cover initialization, outboxes, replies, admission, collections, local ownership and RAM interfaces. Template files compose the generated modules needed by those witnesses.
- Source-protocol and partition benches cover ingress/egress, activation, effects, routing, reset and inspection. `protocol_snowflake_tb.sv` is the repository's single small Snowflake source-protocol integration scoreboard; its actors and oracle belong to [hls_snowflake](../../../hls_snowflake/README.md).
- The C/C++ bridges and headers connect public simulator streams to host drivers and preserve framed FIFO behavior. DSLX fixtures and `.in` fragments supply small test components or generated harness inputs.

Phi-specific benches and VPI diagnostics live in [hls_phi/test/rtl](../../../hls_phi/test/rtl/README.md). Pins, clocks, Linux drivers and board acceptance belong to [platforms/xc7](../../../../platforms/xc7/README.md). Each driver defines its finite workload, timeout and rejecting controls; simulation results do not establish physical timing or unrestricted correctness.

The optional observer’s packaged `priv/simulator/protocol_spacetime_sim.cpp.in` records/replays bounded pre-edge public traffic and read-only taps using `hls_spacetime`'s recording header. The application owns the recording dialect and transport rejection tests; semantic interpretation belongs to the optional lowering adapter. See [capture instructions](../../../../docs/hls_fabric/spacetime-capture.md).

`framed_fifo_stream.h` links to the lowering library’s installed `priv/simulator` header. Tests and the optional observer share one transport implementation.
