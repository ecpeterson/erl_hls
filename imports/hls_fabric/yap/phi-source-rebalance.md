# Phi numerical split in application source

- [x] Move line numerators into diffusion completion and rounding/injection/saturation into state entry using the existing owner boundary.
- [x] Keep compiler/lowering unchanged, preserve grid layout and public messages, and reuse the shared signed-vector codec.
- [x] Match the retained N2 finite public schedule across 2,369 clocks: 70 input words, 153 output words, 24 canonical events, six corrections and two readouts. Only the eight attachment identity words change for the new source build; their replacement is checked independently of application words and clocks.
- [x] Match the fresh six-cell BEAM correction/readout witness against retained per-sender results.
- [x] Inspect the optimized register cut and state cost.
- [x] Pass 169 EUnit tests, three generated-owner DSLX witnesses, 46 finite BEAM/DSLX arithmetic cases, source contracts (289 inherited gaps, none new), application boundaries, Dialyzer and formatting.

The source owner registers two signed 36-bit numerators and one pending bit between callbacks. Entry finalizes both ordinary diffusion and the last round before comparison; initial entry bypasses arithmetic. Backpressure retries pure entry evaluation against the same private transition. The grid keeps its existing direct recurrence. Geometry-owned state headers are included at the original declaration position to preserve tag order.

Optimized N2 boundary state is 9,090 bits, versus 8,798 in the retained baseline and 8,944 in the generated-owner experiment. The source version retains 73 staging bits in both private and committed machine slots per Phi actor; ordinary XLS optimization has not proved the committed copies constant. This meets the preregistered 146-bit-per-actor logical bound. These are IR state bits, not mapped flip-flops. No physical timing or area measurement has been run for this source implementation; previous routed results motivate the change but do not qualify its new layout.

Evidence and preserved failed setup attempts: `/Users/ecpeterson/Documents/code/hls_artifacts/runs/spacetime-2026-11-09/phi-source-rebalance-1/`. Local builds and witnesses are serialized under a 6 GiB descendant guard. The old native runs and successful witnesses remain untouched.

## Source geometry cleanup

- [x] Put Phi interface, state selection and numerical/tie policies in the concrete wrappers; keep the common callback body free of geometry conditionals.
- [x] Replace all five Phi/noise direction-selection macros with source comprehensions over fixed direction lists/tables.
- [x] Qualify compiler expansion, unchanged actor interfaces/layouts, line/grid behavior and a fresh N2 RTL schedule witness.
- [x] Pin compiler revision `8d42c0724b1609f787b0f57d50670563e4123dff` from erl_hls #35; this application consumer remains in #161.

Retain the shared geometry choice and the genuinely different numerical policies. General cross-module callback compilation, parameterized state and actor-wide specialization remain separate work. This refactor adds no actor state, phases or scheduling edges; physical timing is not remeasured.

Cleanup validation: all six line/grid actor interface maps match the preceding source revision after removing source-location diagnostics; 219 focused application tests, 78 compiler EUnit tests and 60 finite generated-owner cases pass. The fresh N2 RTL replay again matches all 2,369 public clocks and accepted words; attachment identity is rebound in the scoreboard only. Optimized boundary storage remains 206 state elements / 9,090 logical bits. Source contracts, Dialyzer, formatting and package/application boundaries pass. Evidence and preserved setup failures are in `/Users/ecpeterson/Documents/code/hls_artifacts/runs/spacetime-2026-11-09/phi-static-actions-1/`.
