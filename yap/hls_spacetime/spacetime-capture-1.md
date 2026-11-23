# S3 — Continuous source-protocol capture

2026-11-06. Finite simulation witness for the registered S1 N2 case. The retained evidence destination is `/Users/ecpeterson/Documents/code/hls_artifacts/runs/spacetime-2026-11-06/capture-1/`; 25 files total 3,209,776 packed bytes, verified against `manifest.json`. `review/review.json` carries the measured scope. No EC2 contact, synthesis, placement, routing, commit or PR was performed.

## Implementation and trust boundary

The actual source-build compiles a monolithic `protocol_boundary_core`, not the separately emitted actor/fabric wrappers. `hls_lowering` now owns `xls_protocol_spacetime` and `xls_protocol_spacetime_capture`: source-input hashes, retained XLS source callsites, exact RTL declarations, register enables and semantic controls bind passive VPI taps to this build. Preview calls are excluded. The simulator recorder/replay shell and C++ transport tests live in fabric's existing simulation-assets directory. Phi's public decoding remains in its test package; the generic bounded sample reader and storage fixture belong to the compiler.

The current supported observation ABI is one source-protocol board clock, single-stage monolithic boundary, no shared arithmetic groups. There are 581 taps, including update expressions for 201 registers; 51 data registers at least 16 bits wide become storage histories. Six actor resources and 24 capture-slot control resources give 81 logical resources total. All requested actor controls resolved without unsupported entries. Reads use physical encoded widths, not the original offsets of narrowed source structs. Tuple associations depend on the pinned XLS flattening convention; this is not a source/native equivalence proof.

Sampling is pre-edge and read-only. No synthesized observer, preservation attributes or RTL changes were introduced. `--public-flat-rw` supplies simulator visibility; a second ordinary build omits that setting. Runs retain offered public inputs/readiness and every selected internal value, with complete counters and bounded run-length encoding. RLE preserves every repeated active edge. No raw file is treated as complete from EOF alone.

## Observations

The live run spans 2,369 clocks. Its 24 public decoder events through fence 8, six corrections and two readouts match the saved ordinary-BEAM witness per logical sender. Independent decoding of accepted public words gives C(3)=1774 and C(4)=1873: the selected public completion spacing is 99 clocks. The step-4 correction is accepted publicly at clock 1852. Two later step-9 status events are retained as tail evidence outside the finite oracle fence. This is not an unstalled throughput estimate or a physical period.

The interpreted capture contains 16,321 events and 23,556 versions: 728 accepted/completed actor heads, 726 takes, two postponements, 357 publication acceptances, and 708 complete capture-slot leases. There are 7,637 actual enabled data-register writes; 4,749 repeat Q's value. Public output backpressure occupies 120 clocks; no input stall or qualified internal entry-wait occurred. Public stalls must not be relabelled as internal actor waits.

Exact replay reproduces every public value and internal tap on every clock. Public-only replay against the ordinary simulator build also agrees, both for the live case and for reset stimulus. The reset case cuts after four accepted heads remain pending at clock 1348, then replays the original offers after reset. It spans 3,717 clocks, retires those four identities, and its post-reset samples/public events match the original suffix at the shifted clocks. No second live host run or oracle run was needed.

The separate 17-clock RTL RAM fixture uses two actual nibble-wide `hls_1r1w_ram` instances plus a response register. Its 40 events/15 versions cover six writes, two equal writes, two masked writes, two read-first collisions, seven reads, five responses and two reset-retired requests. Reset preserves memory words. Logical memory is not evidence of inferred/placed BRAM.

## Qualification and limits

The focused coverage consists of 46 generic artifact tests, 30 sample-reader tests, ten backend binding/transfer/reset tests, 14 deliberate RAM corruptions and 12 C++ transport rejection cases. Changed declarations pass strict source-contract checks; compiler formatting, compiler Dialyzer, adapter Dialyzer and compiler runtime-boundary checks pass. The whole-tree audits still report inherited gaps (compiler 3,334; fabric 289), with zero new/changed gaps. Test/runner failures are retained, including a missing fresh output directory, wrong fixture footer budget, CRLF fixture expectation and the first adapter type-check command omitting the newly compiled reader. They were corrected with focused checks; successful hardware runs were not repeated. Final guards reject unsupported owner encodings and mismatched observation-plan digests.

The final guards preserve both interpreted recordings structurally. An initial byte comparison failed on JSON object ordering across the different conversion environments; decoding and comparing the complete JSON structures passes. This does not weaken cycle-exact replay, whose original raw sample files are byte-identical. The retained original artifact hashes remain authoritative for storage integrity.

One execution-control limitation is retained: the initial XLS build's aggregate RSS monitor failed during setup because `ps` was denied. All six tools exited zero under their individual deadlines; their recorded maximum RSS stayed below 452 MB, and the owned group was verified gone. Aggregate RSS for that build is unknown. Subsequent simulator builds, captures, translations and checks used the serial 6 GiB process-group guard. This is not a claim that the first build was successfully RSS-guarded.

Numerical D ancestry and publication-to-arrival attribution remain explicit unknown roots. Every adjacent nonreset observed register transfer is checked, but the final enabled edge has no following Q sample. Capture completeness refers to its declared sampled scope, not every combinational gate or the complete ancestry of a decoder step. Physical mapping is absent (`physical: null`), not measured zero area. Further attribution and physical joins remain required in S4/S6; source names or a structural cone alone cannot fill those gaps.

## Reproduction and next boundary

The retained package includes compressed live/reset recordings and interpreted bundles, public timestamps, the source emission, exact boundary IR and application RTL closure, observer sources, executed binary hashes, commands, tool identities, guard records and qualification logs. Fabric's `docs/spacetime-capture.md` gives the maintained API/template recipe; compiler `docs/spacetime.md` documents the sample reader and small RAM witness. Full workflow command integration remains S8. Retain compact reproduction inputs/results; completed bulky simulator objects/caches follow the seven-day policy.

This is a meaningful commit milestone across the compiler and fabric repositories, left uncommitted for the user. Propose `hls_spacetime` when S5 starts the standalone saved-file reader/viewer; the backend-specific tap producer stays in `hls_lowering`. S4's matching native physical measurement requires Vivado on the existing EC2 instance, which remains stopped.
