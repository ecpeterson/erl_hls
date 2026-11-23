# Characterization plan

Measure the native `synth_xilinx -abc9` mapping on `xc7z030sbg485-1` in Vivado 2024.2. Preserve fabric register boundaries and mapped cells. Exclude external I/O from these microbenchmarks; retain clock, coverage, route, path and SDF reports. These are operation measurements, not a qualified board clock.

1. Fit width/operation costs using widths 4, 8, 16, 32 and 64; reserve width 24 before measurement. Compare cell-only and local routed estimates, with register overhead separate. Unknown operations must fail rather than inherit the unit model's optimistic fallback.
2. Compare pipeline schedules on held-out composed arithmetic/control circuits using identical stage counts, inputs, mapper and timing constraints. A delay estimate is useful only if it improves those decisions; report failures as well as wins. Do not infer whole-design timing from isolated gates.
3. Extract primitive arcs for the native mapping/timing flow. Check the existing RAM/registered-DSP omissions against exact-mode Vivado measurements; qualify each modeled mode explicitly. Keep unsupported modes visible in the endpoint audit.

Begin with one implementation per circuit. Add repeats only where placement variation could change the conclusion. Retain raw measurements and tool/source fingerprints so future fitting does not need another Vivado session.
