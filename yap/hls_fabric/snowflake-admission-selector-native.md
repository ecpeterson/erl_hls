# Admission selector: retain the existing implementation

The shared-selector simplification is rejected for the default scheduler. Isolated native synthesis makes it larger and slower, despite exact functional equivalence. Preserve experimental commit `d98ecbd` on `codex/snowflake-admission-selector`; do not adopt its production change on this evidence.

The preregistered hypothesis was that replacing the duplicated after/before producer fold with `arbitration::select` would shorten the selection cone without changing cycles, eligibility or metadata. The comparison uses the complete `mailbox::select_admission` helper at six actors, nineteen producers and depth 24, with identical input/output registers, arbitrary 32-bit addresses and cursors, Vivado 2024.2, ZU7EV-2, a 5 ns constraint and one synthesis thread. The reference is `070e1aa`; no placement or routing was run.

| Measurement | Existing fold | Shared selector |
|---|---:|---:|
| LUTs | 1,034 | 1,180 |
| FFs, including measurement registers | 932 | 932 |
| CARRY8 | 76 | 76 |
| Worst logic levels | 18 | 21 |
| Worst cell delay, ns | 1.638 | 1.869 |
| Worst estimated interconnect, ns | 2.895 | 3.477 |
| Setup-derived period, ns | 4.552 | 5.365 |

This is +14.1% LUTs and +17.9% estimated period. Both designs have zero unconstrained internal endpoints, clockless registers and combinational loops. Only external I/O paths are excluded; the registered helper remains timed.

The substitution leaves the serial dependency intact: producer eligibility → producer choice → destination selection → physical-row selection → lowest free index. The new optimized IR includes an after-cursor mask, a global nonempty test and mask selection, then priority encoding before indexed destination selection. Its measured worst path still crosses two carry cells but adds three logic levels. The encoded producer bit zero (`result[40]`) has fanout 160, versus one in the reference's sampled output paths. This is evidence about these mapped netlists, not a general claim that one-hot arbitration is inferior. Fewer source lines did not imply a simpler circuit here.

The input registers admit arbitrary addresses, including malformed ones; the full decoder specializes some values and has different downstream fanout. Therefore this does not establish the whole-core regression or its size. It supplies no reason to pay for a full route or retain the change merely as cleanup. The earlier 24 positive SAT cases, including full 6/19/24 admission, and three negative controls remain valid; correctness was not the failed hypothesis.

## Evidence

The local worktree's `_build/admission-native/` contains frozen DSLX/libraries, both optimized IR and generated RTL, identical register wrapper, `infer.tcl`, reproduction commands and reports. `summary.json` is SHA-256 `fc77b87e16e2610b2e93a98465ade445d4ead0b309189065b6146b8ee8b51812`. All 42 frozen inputs were verified on EC2, and downloaded report hashes match the remote files. `manifest.json` is SHA-256 `f144eff1b274f36c3efee9247b0e1eb06cc4bd900752ec5611da5de3f394b938`.

Reports remain remotely under `/home/ubuntu/snowflake-control-20260928/admission-selector-isolated/results/`; checkpoints were not downloaded. The 140 KiB local archive is `_build/admission-native-evidence.tar.gz`, SHA-256 `24ba9a568944aaa35de50ad5a2e958b219b7a9e47350ef0cc0402715f4acc546`. The native slot was released after this pair; no further measurement is queued for this variant.
