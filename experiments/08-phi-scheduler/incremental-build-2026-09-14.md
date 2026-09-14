# D3 incremental compilation, 2026-09-14

A native D3 build took **573.60 seconds cold** and **0.663 seconds on average for three cached repeats**. The generated Verilog, wrapper, and RAM implementation are byte-identical to the [preceding arbitration/RAM-ordering measurement](../07-openxc7/results/d3-arbitration-2026-09-14.md). No synthesis or routing was repeated.

The workload is decoder-only D3 with three scheduler shards per plane, two pipeline stages, and II=1, on Apple Silicon with 16 GiB RAM. Sources, compiler binaries, standard library, profile, RAM configuration, and all three RTL hashes match the preceding build. The [machine-readable report](incremental-build-2026-09-14.json) contains those identities, stage metrics, individual repeat times, and comparison hashes.

| Compiler stage | Cold elapsed seconds | CPU seconds | Peak RSS MiB |
| --- | ---: | ---: | ---: |
| ir | 130.06 | 129.80 | 471.88 |
| opt | 275.20 | 274.26 | 422.03 |
| codegen | 167.35 | 167.33 | 356.22 |

The single cold sample includes all three compiler stages and snapshot/cache/publication work. Recorded build elapsed time starts at snapshot creation, after CLI startup and executable preflight. A cached repeat still snapshots sources, hashes dependencies and artifacts, and checks the published release; it invokes none of the three compiler programs.

| Cached repeats | Best seconds | Mean seconds | Population variance seconds² | Worst seconds |
| ---: | ---: | ---: | ---: | ---: |
| 3 | 0.652722 | 0.662635 | 0.00005179 | 0.669587 |

These are repeated invocations with a warm filesystem cache, not independent compiler or placement seeds. There is only one cold sample; no cold variance or general speedup distribution is established. A source change can still require a full compile. Pipeline/II/RAM-codegen changes can reuse conversion and optimization; the real `regsvc` test verifies that changing pipeline stages invokes codegen alone.

Unoptimized IR is also byte-identical. Optimized IR differs in two `after_all` token-node IDs and their references; final RTL is identical. Cache publication therefore pins the first completed result for a recipe, even if concurrent identical compiler invocations produce different internal numbering. Downstream stages consume the selected bytes and record their hashes.

The public variable-readiness timing harness passes at **175.958333 cycles/step**, with 103 X-plane and 124 Z-plane stalls and 63/64 corrections, matching the previous measurement. The updated request-paced profile script also passes at **174 cycles/step**. These are different stimuli. The recorded clocks are simulation cycles; this build change introduces no new claim about physical clock frequency.

Run the [incremental compiler](../../docs/incremental-xls-builds.md) on a prepared profile stage, then run it again without changing inputs. Pin `stage/compiled` before simulation or measurement. The routine cache/failure tests and native `regsvc` comparison run in CI; the full D3 cold compile remains an explicit experiment.
