# Publication and selected scalar ancestry

2026-11-06. Extends the same open PRs with S5/S6 contributor attribution and read-bit evidence. The first inspectable contributor chain is now present; complete causal attribution, routed wire geometry and a readable overview of the enlarged graph remain separate work.

## Evidence and interpretation

The unchanged simulator ran one drive and one exact replay per original live/reset schedule, adding five passive input taps. Every previous tap and public field agrees at every clock. The original source, five-file RTL closure, storage events/times/versions, native checkpoint and physical correspondence remain unchanged. The new observation has 592 taps. The compiled hardware and simulator were reused; no XLS, Vivado or EC2 job ran.

Publication identity comes from accepted publisher occurrences, per-output pending-bit retirement, capture leases and declared endpoint arbitration. The live witness joins 357 publications to 708 arrivals, 708 actual payload writes and all 28 boundary transfers; no ownership join is unresolved, and one publication remains pending at the finite boundary. It does not decode encoded payloads with source offsets.

Selected scalar IR operands and selector controls produce read requests on pre-edge versions, paired read results and computation events. Known values must match observed enabled D exactly, including the final captured edge. Unsupported expressions and unrepresented controls remain explicit roots. The bounded evaluator supports scalar operations and flat constant-table lookups; it is not a full XLS verifier or a sensitized gate interpreter. Generated-code binding and the pinned toolchain are trust boundaries.

The live result has 61,764 events and 151,134 versions: 19,228 new read requests, 6,929 resolved numerical roots, 3,974 checked D values and 3,663 unknown values. Reset has 83,479 events and 218,609 versions: 27,288 reads, 9,672 refined roots, 5,329 checked values and 5,057 unknown values. Complete public observations and all original storage chronology are preserved. An explicit inventory permits 1,800 old event-output refinements, 8,373 nonstorage-root refinements and sixteen additive read-port declarations; no old access or stored version changes.

Completion C1873 reaches 21,949 recorded operations, including 77 publications, 145 arrivals, 2,426 writes and 2,281 scalar computations; 2,130 of those computations have checked numerical values. Unknown control/state/input roots remain, so this is not a complete computation graph or critical-path result. The browser discloses its 1,000-operation traversal cap. A selected 61-bit read resolves to 49 native cells spread across X289–331/Y110–147, with twelve bits unresolved. Native switching, wire trajectories and bit-to-bit combinational connections are not inferred.

## Qualification and runtime

The first offline interpretation exceeded its 170-second subprocess limit; its failure and original interpreter snapshot are retained. A bounded stack sample located repeated scalar evaluation/walking. The revised planner normalizes literals/selector lists/widths once; each target walk tracks the union of visited bits without sharing state between targets or clocks. The same recordings then interpreted in 37.91 seconds live and 58.38 seconds reset, within the original 180-second/6 GiB bounds. No simulation was repeated for that correction.

Local checks passed: 62 focused producer/application tests, then all eighteen dependency/ancestry tests after the performance correction; optional-profile Dialyzer; source contracts across 512 files with 289 inherited gaps and zero new/changed gaps. The standalone library passed 140 EUnit tests, Dialyzer and zero contract gaps across thirteen files. The JavaScript suite passed 93 tests, followed by fourteen extension tests including successive provenance preservation. All nine storage-audit regressions passed after matching the input cap to the viewer’s existing 128 MiB limit. Actual storage replay reconciles all 120,768 logical links with 21,035 requests/results. Browser inspection confirms completion anchors, selected bit masks, unrelated-filter selection clearing and no console errors. No Actions were dispatched.

The default selected window now exposes 1,280 used word-clocks (448 load + 832 hold); elapsed time stays 99 clocks and installed population stays 21,756 cells. The display layout was deliberately retained to expose its true density before redesign.

## Reproduction and retention

Evidence is under `hls_artifacts/runs/spacetime-2026-11-06/capture-ancestry-1`: preregistration, exact input/interpreter snapshots, original and optimized interpretation identities, capture/replay guards, compressed traces/graphs, publication/operand sidecars, graph-refinement review and browser images. The compact capture/base evidence totals 7,945,771 bytes; raw JSON, browser projections, caches and PLTs remain disposable. Retention review is 2026-11-13.

Reopen the prepared view without any producer/native run:

```sh
node scripts/prepare-example.mjs \
  --capture-extension /path/to/capture-ancestry-1/live-2 \
  --base-projection /path/to/capture-ancestry-1/base-projection/live-1.json \
  --output web/data
npm start
```

The base retains its sibling `index.json` and memory example. The current local `web/data` is already refreshed. The unchanged memory projection remains byte-identical. Exact result identities are in `capture-review.json`, `view-review.json` and the generated view index; the original S3/S4 and transfer-extension archives remain untouched.
