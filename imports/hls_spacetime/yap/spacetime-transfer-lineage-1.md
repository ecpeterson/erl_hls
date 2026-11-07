# Boundary transfers, completion anchors and cycle metrics

2026-11-06. This increment extends S6 and starts the cycle-only part of S7. It does not close the completion-through-computation milestone: boundary transfers still have explicit unknown source-publication roots, and numerical D/read-bit attribution remains open.

## New finite evidence

The unchanged retained simulator and exact five-file RTL closure were driven once with each original live/reset input schedule, with six additional passive gateway taps. Each new recording was replayed once. All 581 original internal taps and eleven public fields agree on every clock; original events, versions, resources and relations are preserved exactly. No compiler generation, XLS execution, Vivado, synthesis, placement, routing or EC2 work was needed.

The live capture contains 2,369 clocks, 16,379 events, 23,644 versions and 84 resources. Twenty-eight accepted boundary transfers feed twenty-eight completed application frames; two management frames have separate unknown origins. Ten independently decoded all-coordinate step completions each reference two status-frame events. Selected step 4 still spans 99 clocks, ending at C1873; its status frames complete at C1860 and C1873. Both are retained as contributors, rather than selecting the last frame alone.

The reset capture contains 3,717 clocks and 19,231 events. It retains the same twenty-eight application transfers and ten completions after reset at C1348, plus three management frames. Neither real recording has an unfinished frame or queued transfer at its end; the reset point also has no queued or partial stream traffic. Synthetic fixtures exercise queued/prefix retirement, capture tails, stalls, equal payloads, route order, premature serialization, missing admissions and malformed outputs. These are finite witnesses and parser checks, not unrestricted FIFO or native-equivalence proofs.

Transfer identity comes from declared endpoint/host, reset incarnation and per-route FIFO ordinal. Byte equality and first/final-word cycles validate an already selected occurrence. The planner checks retained deployment, complete generated wrapper/gateway wiring and framing libraries byte-for-byte against the installed mechanical emitters. Different gateway support or framing rejects. The generic graph contains only ordinary events, versions and dependencies; transport metadata is a separate observer record.

## Rendering and metrics

Completion selection follows both bound status endpoints. The annotation creates no synthetic completion node or guessed edge. Traversal ends at explicit source-publication roots; new stream resources remain unmapped. Previous register-residence and RAM examples stay available. Semantic filters clear an annotation when none of its endpoint events match anywhere in the capture.

Window length is elapsed clocks. Load/hold word-clocks sum visible adjacent-clock logical storage links, so simultaneous words add and the sum is not execution duration. Used-only follows recorded uses; full history includes otherwise hidden residence. Installed cells are unique catalogue identities regardless of time layers or filters. Wait samples require the producer's explicit per-clock `entry_wait` classification; missing classification is unknown, and unobserved waits are not a global absence claim. No physical period or speedup is inferred.

The maintained projection-extension command checks a hash-bound base projection and capture review, unchanged source/RTL/simulator, full original-tap equality, preserved graph records and matching capture/reset bounds. Placement and static timing retain the original build/checkpoint as explicit correspondence provenance; old event-coverage counts do not get relabelled as measurements of new events. A companion `stream.json` retains frame/pending/reset details outside the generic graph.

## Reproduction and retention

New inputs, recordings, replays, interpretation revisions, checks and projection review are under `hls_artifacts/runs/spacetime-2026-11-06/capture-lineage-1`. Original S3/S4 evidence is unchanged. The seven-day review is 2026-11-13; hashes do not exempt raw captures, browser projections, build products or PLTs from retention. Preserve compact source/control snapshots, compressed new captures and metadata; raw duplicates and caches are disposable.

Local qualification and browser inspection are recorded in the external review. The first interpreter revision is retained: type analysis exposed backend metadata in the generic graph's closed type; the corrected interpretation separates the companion record and reuses the exact same recordings. No hardware witness is repeated for this API correction.

Local checks passed: 37 focused Erlang tests, optional-profile Dialyzer, ordinary-profile compilation, 271 library modules with zero example dependencies, and 70 runtime modules with zero package violations. The source-contract audit found 289 inherited gaps and zero new or changed gaps. The 83-test JavaScript suite passed, followed by all six projection-extension tests after the final navigation fixture was added. Formatting and whitespace checks passed. No remote CI was requested.

Browser inspection verified both completion contributors, Inputs/Consumers navigation, selection clearing under an unrelated actor filter, and the unchanged RAM example with unknown placement and unclassified waits. The full selected step reports 99 clocks and 636 logical word-clocks (167 load + 469 hold), with 21,756 unique installed cells. Narrowing to C1850–1873 gives 24 clocks and 162 word-clocks (44 load + 118 hold), without multiplying installed cells. These sums describe logical storage residence within the observed scope.
