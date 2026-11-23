# Execution extraction validation

Public base: `17f00f3` (aggregate-ready boundary). Private base: `e5fd331`. Public dependency: `be530d2e08cab2d7e925156c40a1f06fe04116f3`.

The public compiler now owns callback lowering and dedicated communicating actors. This repository owns physical sharing and all experiments. The extraction intentionally preserves execution latency, effect order and placement policy; it makes no timing-improvement claim.

Local witnesses use OTP 28.0.2 and native macOS XLS tools available on this machine. Interpreter and codegen builds are not one release bundle; CI uses the pinned Linux release independently. The UTM address did not answer SSH during this run.

- Public EUnit: 1,023 tests, zero failures. Private EUnit: 289 tests, zero failures.
- Dialyzer clean in both applications. Source-contract checks introduce no gaps; existing omissions remain visible.
- Public generated DSLX check, 156 entry RTL vectors and 6,400 branching transitions; reduction DSLX/JIT; dedicated closed/ingress graphs at two pipeline depths.
- Private reduction DSLX/JIT and source-fragment conversion, shared initialization/reset, retained calls and failure draining, dense codecs across dedicated/shared topologies, and 256 type-shape vectors.
- Mixed graphs: two groups, coalesced groups, ingress and separate weak components, each at two pipeline depths; CPU output agreement, original/instrumented cycle agreement, FIFO accounting and live actor/debug wait queries under sink stalls and recovery.
- Common VPI bridge: 104 transport fault checks. Private observer include compiles against that bridge. Its older internal-name summary probes do not resolve all metadata in the current native optimized build; the same required projection names are absent from the retained pre-extraction four-phi RTL; no summary from that probe was used as evidence. The separate cycle trace, validated below, remains the profiling path.
- Shared actor failure snapshots, dedicated/shared/mixed mailboxes, and ordinary/dedicated/offloaded reductions pass live debug queries at the tested pipeline depths, including exact source locations and cycle-by-cycle observation noninterference. Startup backpressure also passes.
- Mailbox SAT checks pass selection and metadata induction at the four recorded actor/depth configurations; the reversed-priority negative control produces a counterexample. These checks exclude RAM payloads, in-flight scheduling and liveness.
- Relocated Zynq bring-up suite passes locally through mapped DMA/PS/GTX/SFP/Ethernet models, clock crossings and recovery. Physical-build manifests now resolve private experiment inputs separately from compiler inputs.
- Public routed services pass 960 concurrent pings, isolated state and public stall/recovery queries; trace resynchronization and passive sampling checks also pass.
- The old raw/BRAM launchers now locate public compiler sources through the shared path helper; their 18 source inputs preprocess locally. Their remote runs were not repeated.
- Compiler cache, profile accounting, DSLX/Erlang source-contract and timing-report tooling regressions pass. Imported unchanged vendor bundles and raw logs preserve whitespace and hashes.

The complete four-phi profile additionally passes comparisons of both output-readiness patterns against BEAM and generates its SVG/Perfetto trace: 1,848 aggregate sends/receives and visits, with zero payload mismatches or trailing aggregate receptions/visits. Its validation summary is retained locally under `_build/decoder-extraction/board-sized/validation.json`.

This is regression evidence, not a formal equivalence proof of the extraction. Routing and synthesis were not repeated: the purpose is repository ownership, with behavioral and instrumentation checks at the generated RTL boundary.
