# Platform support

[`xc7/`](xc7/README.md) owns Xilinx 7-series board integration and physical-tool qualification: shells, constraints, drivers, boot/runtime packaging and bounded probes. These checkout assets consume generated application RTL and the installed compiler/fabric support libraries. They are not shipped as part of the runtime or HLS tool release.

Reusable board-independent hardware belongs in `apps/hls_target/priv/rtl`; simulation-only shells belong in `test/rtl`. Application sources and their private generated adapters belong to the corresponding application package. Keep board-specific acceptance conditions in the platform guide rather than treating a compile-only probe as a deployable image.
