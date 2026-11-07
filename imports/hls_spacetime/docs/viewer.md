# Inspecting a saved capture

The viewer reads `spacetime-view` JSON projections. A projection retains the complete event/version graph and unique placed-cell/binding tables, plus independently recorded public annotations, optional ordered static timing paths, evidence scope and content identities. It omits the large native property/net/SDF tables from browser memory; those remain in the source archive. A projection is a browsing index, not a replacement evidence archive or a new measurement.

## Prepare and open

Use Node 22 or later. No npm installation or external service is required:

```sh
node scripts/prepare-example.mjs \
  --physical-archive /path/to/spacetime-2026-11-06/physical-1 \
  --capture-archive /path/to/spacetime-2026-11-06/capture-1 \
  --output web/data
npm start
```

The preparation command checks requested file bytes against the retained manifests, checks the decoded JSON identities, and verifies the saved timing-report bytes before parsing their ordered data pins. It binds the physical archive, catalogue and timing attachment to the same build and checkpoint, then writes the two projections and a byte/hash index into a fresh output directory. It never invokes simulation, Vivado, or Erlang. Original manifests are trusted inventories, not cryptographic attestations of a measurement. Other evidence files are not revalidated merely because their names appear in provenance.

The loopback server serves only `web/`, accepts no uploads, and uses port 4173 by default (`PORT` overrides it). Open the printed URL. The browser verifies example bytes against the local index; “Open file” instead accepts a user-supplied projection and labels its provenance as not freshly verified. File content is handled locally. Use Ctrl-C to stop the server.

## Extend a saved view

A qualified observation extension can add transfer, publication and selected scalar-operand ancestry while reusing the original physical view:

```sh
node scripts/prepare-example.mjs \
  --capture-extension EXTENSION_DIR \
  --base-projection BASE_PROJECTION_JSON \
  --output web/data
```

Replace the two uppercase placeholders with the retained extension directory and qualified base JSON file. Keep the base in a separate directory with its original `index.json` and sibling example files. The extension directory must contain a manifest, `review.json`, `public.json`, and exactly one of `bundle.json` or `bundle.json.gz`.

This mode verifies the base projection's exact digest and the extension files' manifest lengths and digests. It requires a review of complete original-tap and public-field equality, unchanged source/RTL and simulator identities, matching capture bounds/reset incarnations, and the original physical checkpoint. It independently checks unchanged graph records and any narrowly permitted ancestry refinements against an exact review inventory; old relations remain present. The review is a trusted local evidence inventory; the command does not rerun the comparison or simulation. Original physical correspondence and timing retain explicit provenance, added resources remain unmapped, and old event-coverage counts are not reused for the enlarged graph. Verified sibling examples are copied unchanged and the output index is refreshed. No native tool or original report reader runs.

A new interpretation may include `review.graph_refinements`, an array of `{table, id, before_sha256, after_sha256}` entries. `table` is `events`, `versions` or `resources`; digests cover that entire record before and after the change. Use exported `graphRecordSha256(record)` from `scripts/prepare-example.mjs`: it hashes UTF-8 JSON with recursively sorted object keys and preserved array order. Every changed old record needs exactly one matching entry. Duplicate, unlisted, unused or mismatched entries reject the extension. Omitting the inventory retains the additive-only contract.

The permitted changes are deliberately narrow:

- An event may add `inputs` or `outputs` and update nonempty `evidence`. Existing input/output identities remain present; event identity, clocks, observer sequence, actor context, operation, access and resources remain unchanged.
- A version whose original `producer` is `root`, `origin` is `unknown` and `storage` is `null` may acquire an event producer and nonempty evidence in the same incarnation. Its identity and all other fields stay fixed, including `storage: null`. Stored words and initial/reset origins cannot be refined this way. Normal graph validation still rejects backward dependencies, cycles and inconsistent producers.
- A resource may add logical ports classified as `read`, recording newly observed operand lanes. Existing ports, width, depth, reset/collision policy, evidence and every other resource field stay fixed. This describes extra observations, not additional physical RAM ports or circuitry.

These changes exist only in the new interpretation bundle. The original archived graph, native measurement and physical correspondence remain frozen. Successive extensions check the preceding trace/simulator identities, replace the completion shortcut and retain the preceding correspondence origin and extension review, so original scopes, coverage and refinement inventories stay reachable. The projection retains the refinement inventory and original physical provenance; resolving an unknown operand is evidence for that recorded execution, not a new measurement or an all-input equivalence claim.

## Read the picture

- The **clock stack** shows distributed storage accesses at their associated native tile positions by default. Multiple cells at one tile share a glyph. Filled write glyphs select the logical write-mask bits for which cell identities are known; reads with a producer-qualified `read_mask` use the selected operational bits, while hollow reads show whole-word context when that subset is unknown. Both remain hollow context where a cell binding lacks bit identities. Neither is a map of native switching. Turning off **Distributed accesses** restores aggregate symbols, whose centres are not computation locations. Time runs downward. Drag to rotate; arrow keys rotate the focused canvas; adjust layer spacing and move the clock window. Unresolved bits and operations stay on the labelled unknown rail; a delayed read response does not borrow its source register’s location. The memory fixture uses logical resource/address lanes throughout.
- **Actor, activation, operation and task** filters use recorded fields. Operation is the available phase/action vocabulary, not a newly inferred computation stage. Activation choices come from the current actor/window. Clears and window navigation never discard the underlying graph.
- **Inputs** and **Consumers** traverse only recorded value, read-request and required-control dependencies. A public annotation can name several independently bound graph endpoints; selecting it follows all of them, visiting shared contributors once. Unbound annotations stay context. Root versions stop traversal, the traversal cap is explicit, and the inspector identifies the result as partial recorded ancestry. Same-clock chronology, placement, equal payloads and wire connectivity create no extra causal edges. Resource-order relations remain distinct and are not included in the default causal traversal. Semantic filters clear an operation or anchored annotation when none of its endpoints match anywhere in the recording; moving the clock window preserves off-window ancestry.
- **Storage links** default to versions with recorded uses, even with no selection. Residence ends at the last recorded use, including reads on the replacement clock and explicit old-value inputs to masked writes. Holds and delayed responses do not extend the source word’s use. Off-window consumers still preserve the preceding storage. Enable **Full storage history** to restore all matching words and their entire residence; the inspector always retains that history. No recorded use is not proof of dead state: the recording may omit consumers. Solid links join a write at C to its new Q at C+1; a square marks that next sample. Dashed spans retain the same version between samples. An equal-valued write is still a new version. Replacement, reset and capture boundaries stop the span; a final write without a following Q sample gets no invented cross-cycle link. Residence is not an attributed wait. Incomplete captures remain visibly uncertain.
- The **flat chip** draws installed primitives once and highlights the selected resource’s associated native cells. A wide encoded register can occupy many scattered FFs; this highlight is storage placement, not its combinational fan-in/fan-out or routed wiring. The unknown rail beside the stack is a layout convention, not external circuitry. Expand cell details or select a highlighted cell for native identity, kind, site, BEL and tile coordinates. The storage resource shows supported and unknown bits separately. Partial word correspondence does not establish the complete circuit footprint of an actor operation.
- **Native timing path** adds an optional pink overlay of ordered placed cells from the saved static setup report. It appears on a comparison clock layer and on the flat chip, independently of the selected execution trace. The pin list and delay summary describe that static path; connecting segments are not actual wire trajectories, and the recording does not establish that the path was sensitized on the displayed clock.
- The **timeline** retains the whole recording while the stack shows a movable window. Public completion boundaries and reset incarnations are separate markers. “Selected step” opens the recorded step interval; “Completion record” selects its public annotation and any explicitly bound contributing endpoints. The annotation itself creates no graph event or edge.
- **Window metrics** count elapsed clocks as the exact half-open window length. Load and hold word-clocks sum the visible adjacent-clock links of logical storage words, following the semantic filters and recorded-use/full-history setting. Concurrent words add; these counts are neither elapsed time nor a critical-path duration. A one-clock view has no storage link to count. Installed native cells come from the unique catalogue once, independently of filters and repeated layers; absent placement remains unknown. Wait counts require explicit `metric_hints.wait_operations` in the projection or bundle, naming producer-qualified per-clock observations. The display separates wait-event samples from distinct observed clocks, never treating arbitrary gaps or storage residence as waits. All counts retain the capture’s declared observer scope and incomplete status.

The operation list provides keyboard-selectable alternatives to overlapping canvas dots. The inspector identifies producer/consumer versions, activation, storage history and source evidence. Context dots are reused from one physical table; appearances across time do not multiply installed area. Colors identify recorded semantic actors/resources, not exclusive physical ownership or gate switching. Dependency connections and the static path overlay are schematic; neither supplies routed wire geometry. Distributed access locations do not supply missing combinational ancestry or bit-to-bit dependency pairing. Aggregate word dependencies remain labelled when that pairing is unknown.

Select a storage link or use **Resource → Storage versions in view** to inspect its version, producer and consumers. Selecting a resource emphasizes all its visible versions. **Expand selected word into cells** is enabled by default and draws the selected word’s qualified cells at their device tile positions; shared/folded cell identities draw once per word version. Partial, candidate and unplaced portions remain on the unknown rail. Cell expansion associates simulated storage with qualified native value locations; it does not establish native write-enable activity, electrical switching or exclusive task ownership.

Unselected storage words remain grouped to keep the background legible. The selected word expands into cells by default; turn off **Expand selected word into cells** to group it too. Actor/activation/operation/task filters select storage through explicit associated events, including consumers outside the clock window, without assigning those actors to every stored bit. Background storage stays neutral. Drawing bounds are 20,000 storage strokes, 20,000 access glyphs and 4,000 dependency strokes; omissions are counted beneath the stack. The complete graph stays in memory. Narrow the window or select a resource for detail. Clipping marks preserve off-window boundaries, and a one-clock view has no pair of samples to connect.

## What the first example supports

The N2 step occupies `(1774, 1873]`, displayed as C1775–C1873: 99 clocks. The current expanded live graph contains 61,764 events, 151,134 versions and 84 resources. Five added input taps preserve all 587 preceding taps and eleven public fields at every one of the 2,369 clocks; both the live and reset recordings replay exactly. The graph retains every original event time/access and stored-word identity. Reviewed refinements resolve unknown transient roots and add observation read lanes; the prior archived graphs remain unchanged.

**Completion C1873: accepted-transfer ancestry** selects both coordinate status frames. Their ancestry now reaches accepted source publications, capture-slot arrivals, payload writes and selected scalar register computations. Across the full live recording, 357 publications account for 708 arrivals/payload writes and all 28 boundary transfers; one publication remains pending at the finite end. The numerical adapter adds 19,228 selected-operand reads, resolves 6,929 write-input roots and checks 3,974 of 7,637 enabled D values exactly. The remaining 3,663 values are unknown, not mismatches.

The selected completion has 21,949 reachable recorded operations, including 2,281 scalar computations, of which 2,130 have checked values. The interactive traversal retains its explicit 1,000-operation cap. Unknown roots remain extensive: omitted small control-register histories, an unbound transformed XLS state bit, external inputs and publication-layout controls prevent complete causal attribution. Computation events have no inferred native logic location. This is selected operational ancestry, not electrical sensitization or a complete critical path.

Start with **Register residence: C1852 → C1866** to inspect `v/25067` in the 537-bit encoded word. Its stored value occupies C1853–C1866, and a read feeds actor/3 acceptance. The word has 409 supported native FDRE bits and 128 unknown bits. The original semantic read still shows whole-word context. New `selected_operand_read` events instead carry exact operational masks: for example, `dependency/read/e/22593/____state_154` selects 61 bits, places 49 associated cells across X289–331/Y110–147, and leaves twelve bits unresolved. The inspector displays the mask without rounding wide integers. No bit-to-bit combinational path is implied.

The additional recorded uses change the selected window's used-only storage total to 1,280 logical word-clocks: 448 load plus 832 hold. The elapsed interval remains 99 clocks, and unique installed cells remain 21,756. The independent storage check still reconciles the same 120,768 adjacent-clock links; extra observations expose uses of existing stored words rather than creating circuitry.

Select **Native timing path → max/0** for a separate static example: 42 distinct native cells across 40 logic levels, with 8.808 ns data delay = 4.075 ns logic + 4.733 ns routing. Its ordered pins are bound to the original checkpoint; this is neither actual wire geometry nor evidence that the path was active on the selected clock. The previous physical correspondence and timing are reused with their original provenance; no native job was run for this extension.

The separate 3,717-clock reset witness contains 83,479 events and 218,609 versions. It adds 27,288 operand reads and checks 5,329 D values, preserving public completions after reset at C1348. Reset incarnations remain separate. Synthetic fixtures additionally exercise queued/prefix retirement, capture tails, selector choice, overlapping slices and simultaneous old-value reads. These are finite witnesses and localized checks.

The current layout deliberately retains the denser evidence before the next readability pass. Drawing and traversal caps disclose omissions; filtering or a narrow clock window remains useful for inspecting individual accesses.

Switch to **RTL memory witness** for masked/equal writes, read-first collision, delayed response and reset retirement. This is a finite witness of the supplied RAM primitive and fixture; it has no native BRAM placement.

The native measurement failed its 5 ns target. No alternate execution clock period has been established. The viewer reports cycles and does not turn the 8.997 ns static constraint-equivalent value into a measured frequency or step time.

## Check storage against the recording

```sh
node scripts/check-storage-view.mjs web/data/live-1.json
node scripts/check-storage-view.mjs web/data/memory.json
```

This independently advances each recorded word through every clock, then compares that replay with the viewer's compressed load/hold intervals. It checks pre-edge reads, full and masked writes, delayed responses, reset roots and final writes. The JSON report binds the exact input SHA-256 and reports qualified logical edge counts only for complete declared write coverage. Missing coverage remains unqualified; contradictory transfers reject. This is a check of the saved access history and its visualization, not another simulation, a native write-enable proof or a recovery of missing numerical ancestry.

Inputs are bounded to 128 MiB and one million adjacent-clock/word comparisons. `--max-comparisons COUNT` may lower the comparison budget; repeated limits use the last value. Exceeding the limit rejects rather than silently sampling. Normal unit tests use small synthetic histories; these optional saved-case checks require only the prepared files.

## Local checks

`npm test` runs small graph, history, coverage, access-footprint, static-path parser/attachment and projection-integrity tests. `node --check web/app.js` checks the browser controller syntax. Format browser code with `npx prettier@3.6.2 --write web/*.js web/*.css web/*.html scripts/*.mjs test-js/*.js`; this optional development command downloads the pinned formatter, while serving and testing need no dependencies. The Erlang/native checks are described separately in [source quality](source-quality.md).
