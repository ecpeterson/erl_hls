# Logical values: data-cell mapped area

The prediction registered before synthesis was a modest reduction in registers and selection logic for the affected actors, with unchanged external message formats and step behavior. Existing optimization could already remove some upper bits.

For dense packing, the further prediction was no material standalone area change because the logical fields were already narrow and the endian permutation should optimize to wires. The final two mapped samples below are identical to the earlier padded version. A separate combinational permutation/padding probe synthesizes to zero logic cells.

The complete standalone `phenom_data_cell` service was mapped before and after converting its two noise-control flags from `u32` values to Booleans. The comparison includes its word receiver/transmitters and internal mailboxes. It excludes topology scheduler RAMs, routing, debug instrumentation, and physical I/O; these are not whole-D3 area figures.

| Revision | Seed 1 LUTs | Seed 2 LUTs | Best | Mean | Population variance | Worst | FFs, both seeds |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Main after #118 | 4,016 | 3,937 | 3,937 | 3,976.5 | 1,560.25 | 4,016 | 2,617 |
| Logical values | 3,843 | 4,024 | 3,843 | 3,933.5 | 8,190.25 | 4,024 | 2,617 |

Mean LUT count decreases by 43 (1.08%), but the matched seed deltas have opposite signs: −173 and +87. This sample does not establish an area improvement. The unchanged register count indicates that narrowing these flags does not save additional registers in this standalone mapping; the compiler already eliminates their unused upper bits. Neither version maps to BRAM or DSP primitives. No timing, power, or placed-and-routed comparison was performed.

The value/wire distinction is nevertheless explicit in the generated types: each affected actor's data record has 354 logical and serialized bits, compared with 416 for both before the change. The serialized state layout changes; application message layouts remain unchanged. Physical savings in a particular scheduler RAM configuration require a separate measurement.

[Machine-readable results](logical-values-2026-09-16.json) retain both samples, complete cell counts, source/RTL hashes, tool hashes, schedule, and the exact baseline revision. The flow uses native XLS with one pipeline stage, a unit delay model, no input flops, and registered outputs; Yosys maps with `synth_xilinx -flatten -abc9 -arch xc7 -noiopad -noclkbuf` after `proc; flatten; opt; memory_collect; rename -scramble-name -seed SEED`. Both mappings pass structural checks and combinational-loop rejection.

To reproduce, capture each revision's `phenom_data_cell.erl.x` as `phenom_data_cell.x` alongside its `priv/xls/lib/*.x` and `phi_field.x`. Compile with `python3 tools/compile_xls.py STAGE/phenom_data_cell.x XLS_ROOT --output OUTPUT --name phenom_data_cell`. Read the generated Verilog, select `__phenom_data_cell__Top_0_next`, and run the flow above for seeds 1 and 2. Native inputs, scripts, and logs are retained under `_build/logical-widths/area`.
