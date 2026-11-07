# Inspecting a saved capture

The viewer reads `spacetime-view` JSON projections. A projection retains the complete event/version graph and unique placed-cell/binding tables, plus independently recorded public annotations, evidence scope and content identities. It omits the large native property/net/SDF tables from browser memory; those remain in the source archive. A projection is a browsing index, not a replacement evidence archive or a new measurement.

## Prepare and open

Use Node 22 or later. No npm installation or external service is required:

```sh
node scripts/prepare-example.mjs \
  --physical-archive /path/to/spacetime-2026-11-06/physical-1 \
  --capture-archive /path/to/spacetime-2026-11-06/capture-1 \
  --output web/data
npm start
```

The preparation command checks the requested files against the retained manifests and raw JSON hashes, then writes the two projections and a byte/hash index into a fresh output directory. It never invokes simulation, Vivado, or Erlang. Original manifests are trusted inventories, not cryptographic attestations of a measurement. Other evidence files are not revalidated merely because their names appear in provenance.

The loopback server serves only `web/`, accepts no uploads, and uses port 4173 by default (`PORT` overrides it). Open the printed URL. The browser verifies example bytes against the local index; “Open file” instead accepts a user-supplied projection and labels its provenance as not freshly verified. File content is handled locally. Use Ctrl-C to stop the server.

## Read the picture

- The **clock stack** places operations at the centre of their explicitly associated placed cells. Time runs downward. Drag to rotate; arrow keys rotate the focused canvas; adjust layer spacing and move the clock window. A resource without established placement appears on the labelled unknown rail. The memory fixture uses logical resource/address lanes throughout.
- **Actor, activation, operation and task** filters use recorded fields. Operation is the available phase/action vocabulary, not a newly inferred computation stage. Activation choices come from the current actor/window. Clears and window navigation never discard the underlying graph.
- **Inputs** and **Consumers** traverse only recorded value, read-request and required-control dependencies. Root versions stop traversal. The traversal cap is explicit. Same-clock chronology, public completion, placement, equal payloads and wire connectivity create no extra causal edges. Resource-order relations remain distinct and are not included in the default causal traversal.
- **Storage links** default to versions with recorded uses, even with no selection. Residence ends at the last recorded use, including reads on the replacement clock and explicit old-value inputs to masked writes. Holds and delayed responses do not extend the source word’s use. Off-window consumers still preserve the preceding storage. Enable **Full storage history** to restore all matching words and their entire residence; the inspector always retains that history. No recorded use is not proof of dead state: the recording may omit consumers. Solid links join a write at C to its new Q at C+1; a square marks that next sample. Dashed spans retain the same version between samples. An equal-valued write is still a new version. Replacement, reset and capture boundaries stop the span; a final write without a following Q sample gets no invented cross-cycle link. Residence is not an attributed wait. Incomplete captures remain visibly uncertain.
- The **flat chip** draws installed primitives once and highlights the selected resource’s associated native cells. A wide encoded register can occupy many scattered FFs; this highlight is storage placement, not its combinational fan-in/fan-out or routed wiring. The unknown rail beside the stack is a layout convention, not external circuitry. Expand cell details or select a highlighted cell for native identity, kind, site, BEL and tile coordinates. The storage resource shows supported and unknown bits separately. Partial word correspondence does not establish the complete circuit footprint of an actor operation.
- The **timeline** retains the whole recording while the stack shows a movable window. Public completion boundaries and reset incarnations are separate markers. “Selected step” opens all 99 clocks of the saved live example; “Completion record” selects its public annotation without creating a graph endpoint.

The operation list provides keyboard-selectable alternatives to overlapping canvas dots. The inspector identifies producer/consumer versions, activation, storage history and source evidence. Context dots are reused from one physical table; appearances across time do not multiply installed area. Colors identify recorded semantic actors/resources, not exclusive physical ownership or gate switching. Connections are schematic until S7 supplies actual routing geometry.

Select a storage link or use **Resource → Storage versions in view** to inspect its version, producer and consumers. Selecting a resource emphasizes all its visible versions. **Expand selected word into cells** draws its qualified cells at their device tile positions; shared/folded cell identities draw once per word version. Partial, candidate and unplaced portions remain on the unknown rail. Cell expansion associates simulated storage with qualified native value locations; it does not establish native write-enable activity, electrical switching or exclusive task ownership.

The stack groups words by default to stay legible. Actor/activation/operation/task filters select storage through explicit associated events, including consumers outside the clock window, without assigning those actors to every stored bit. Background storage stays neutral. At most 20,000 storage strokes are drawn; any omission is counted beneath the stack. The complete graph stays in memory. Narrow the window or select a resource for detail. Clipping marks preserve off-window boundaries, and a one-clock view has no pair of samples to connect.

## What the first example supports

The N2 step occupies `(1774, 1873]`, displayed as C1775–C1873: 99 clocks and 1,289 operations. The full live graph retains 16,321 operations and 23,556 versions, so earlier contributors remain inspectable.

Start with **Register residence: C1852 → C1866**. A committed write creates `v/25067`, the encoded word resides across C1853–C1866, a read selects it and its returned transient version feeds actor/3 acceptance. The associated word has 409 supported bits and 128 unknown bits. Its numerical D input is an explicit unknown root. The accepted actor operation itself has no qualified logic placement; the viewer does not borrow the register's placement for it.

**Earlier producer** demonstrates off-window ancestry. **Completion context** shows recorded control actions on the completion clock, but does not connect the public completion to them. The original S5 criterion of following public completion through numerical computation cannot yet be met from the saved evidence. S6 must establish that attribution or record its remaining limit; the viewer must not fabricate it.

Switch to **RTL memory witness** for masked/equal writes, read-first collision, delayed response and reset retirement. This is a finite witness of the supplied RAM primitive and fixture; it has no native BRAM placement.

The native measurement failed its 5 ns target. No alternate execution clock period has been established. The viewer reports cycles and does not turn the 8.997 ns static constraint-equivalent value into a measured frequency or step time.

## Check storage against the recording

```sh
node scripts/check-storage-view.mjs web/data/live-1.json
node scripts/check-storage-view.mjs web/data/memory.json
```

This independently advances each recorded word through every clock, then compares that replay with the viewer's compressed load/hold intervals. It checks pre-edge reads, full and masked writes, delayed responses, reset roots and final writes. The JSON report binds the exact input SHA-256 and reports qualified logical edge counts only for complete declared write coverage. Missing coverage remains unqualified; contradictory transfers reject. This is a check of the saved access history and its visualization, not another simulation, a native write-enable proof or a recovery of missing numerical ancestry.

Inputs are bounded to 64 MiB and one million adjacent-clock/word comparisons. `--max-comparisons COUNT` may lower the comparison budget; repeated limits use the last value. Exceeding the limit rejects rather than silently sampling. Normal unit tests use small synthetic histories; these optional saved-case checks require only the prepared files.

## Local checks

`npm test` runs small graph, history, coverage and projection-integrity tests. `node --check web/app.js` checks the browser controller syntax. Format browser code with `npx prettier@3.6.2 --write web/*.js web/*.css web/*.html scripts/*.mjs test-js/*.js`; this optional development command downloads the pinned formatter, while serving and testing need no dependencies. The Erlang/native checks are described separately in [source quality](source-quality.md).
