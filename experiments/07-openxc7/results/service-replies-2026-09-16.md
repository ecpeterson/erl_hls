# Service reply contracts: mapped area

The prediction registered before synthesis was that XLS would fold away reply membership checks for `regsvc`'s fixed record constructors, leaving its area unchanged.

| Native `regsvc` build | LUTs | Flip-flops |
| --- | ---: | ---: |
| Main after PR #117 | 2,419 | 1,226 |
| Per-request reply contracts | 2,419 | 1,226 |

Both builds have identical counts of each mapped cell kind, including 24 CARRY4, 66 MUXF7, and 33 MUXF8 cells. Neither uses RAM or DSP primitives. Generated RTL names differ. A flattened Yosys `equiv_make` / `equiv_simple` check also proved all 5,772 equivalence obligations with none left unproven, covering the generated service and its stream handshakes under matched state. These counts measure the complete generated `regsvc` service with its word receiver/transmitter and internal FIFOs, excluding the local router, debug instrumentation, and physical I/O.

The comparison uses one matched native XLS installation and Yosys `synth_xilinx -flatten -abc9 -arch xc7 -noiopad -noclkbuf`, with one pipeline stage, unit delay model, no input flops, and registered outputs. [Machine-readable results](service-replies-2026-09-16.json) identify the baseline commit, tool hashes, generated DSLX/RTL hashes, and all cell counts. This is a deterministic synthesis comparison, not a placed-and-routed timing result or a D3 area measurement. The unchanged mapped counts support the prediction for this service; they do not establish zero cost for every possible callback implementation.

To reproduce, place each revision's generated `regsvc.erl.x` in its own flat DSLX stage as `regsvc.x`, together with `priv/xls/lib/*.x`. Compile each using `python3 tools/compile_xls.py STAGE/regsvc.x XLS_ROOT --output OUTPUT --name regsvc`. Read `OUTPUT/regsvc.v` with Yosys in SystemVerilog mode, select `__regsvc__Top_0_next`, and use the mapping command above. The native artifacts and logs for this run are under `_build/service-contracts/area`.
