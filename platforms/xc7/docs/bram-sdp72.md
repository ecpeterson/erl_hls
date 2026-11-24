# 72-bit simple-dual-port block RAM

The repetition scheduler and debug trace infer 72-bit simple-dual-port `RAMB36E1` memories. All eight parity bits carry application data. The old Yosys Series-7 mapping selected `DIP[3:0]` twice, corrupting logical bits 44, 53, 62 and 71. Separately, the archived nextpnr writer omitted the A-side width markers for a 72-bit write, affecting logical bits 8, 17, 26 and 35 on silicon.

`bram/check_yosys.py` rejects either the old mapping library or a synthesized probe whose upper parity connections copy the lower connections. `bram/check_backend.py` requires the complete vendor-matched width profile in routed FASM. `gtx/build_backend.sh` applies the corresponding writer correction to the pinned archived backend.

Run the portable guards with:

```sh
python3 platforms/xc7/test_bram_backend.py
iverilog -g2012 -s bram_probe_tb -o /tmp/bram-probe \
  platforms/xc7/bram/te0715_bram_probe.v \
  platforms/xc7/bram/bram_probe_tb.sv \
  platforms/xc7/zynq_ps_probe.v
vvp /tmp/bram-probe
```

The RTL simulation is a bounded witness under ordinary inferred-memory semantics. It does not exercise synthesized primitive mapping.

The board probe writes zero, one, alternating, lane-distinct and address-dependent patterns through the inferred scheduler and trace shapes. On the TE0715-05-71C33-A, the corrected Yosys mapping and nextpnr writer produced `PASS: inferred scheduler and trace BRAM shapes preserved all test patterns`. This is a physical witness for those shapes and patterns, not general memory, timing or toolchain qualification.

Upstream has both corrections. [Yosys parity mapping](https://github.com/YosysHQ/yosys/commit/aba5b279c6ea3c7ef0867f43d2f7d8dc23d9f440) · [Maintained openXC7 width writer](https://github.com/openXC7/nextpnr/blob/main/himbaechel/uarch/xilinx/fasm.cc#L2265-L2279). The repository retains an explicit library audit because the qualified board flow uses an older isolated Yosys release for reproducible placement. A later toolchain migration should remove that local source correction only after the same netlist, routed-FASM and physical checks pass.

The four-Phi regression synthesizes a 512 × 72 memory, then uses UNISIM to write and read a one-hot word for every lane. Stock Apio first fails when writing bit 8. Readback sets both bits 8 and 44. The October board mapping and the retained upstream Yosys 0.69+154 each passed all 72 writes and reads. The four-Phi capture checks which mapping file Yosys actually opened. [Regression driver](../../../apps/hls_spacetime/test/native/four_phi/workload/sdp72.py)
