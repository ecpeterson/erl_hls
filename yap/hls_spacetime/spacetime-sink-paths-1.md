# Per-sink timing inspection — qualified 2026-11-08

This extends the [offline timing explanation](spacetime-timing-report-1.md) in PR #7 using the same retained native/SDF evidence. It does not rerun extraction, simulation, synthesis or routing. [Viewer usage](../../docs/hls_spacetime/viewer.md#inspect-paths-to-a-sink) is the maintained interface documentation.

## Completed behavior

The sink list is complete and paged, grouped by role and exact native pin, with write/clock/resource associations. Each known sink has a deterministic maximizing chain, logic/net totals, disclosed predecessor ties and a severity gap relative to the slowest known visible sink. Unknown competing contributions prevent a complete bound; unknown siblings at other roots do not erase a finite local arrival. The scene can show all circuitry, one chain per sink, the selected chain, or a selected near-longest arc union. A merged unknown sink's near view retains its eligible closure without a numeric margin cutoff. No parallel paths are added or enumerated exponentially.

The ordered strip highlights exact native arc identities before geometry merging. Its local logic/net costs reconcile with the path total, including zero-delay arcs in the ordered list. The 3D logic/net palette retains capture-wide urgency brightness, while storage remains neutral in timing modes. Focused sinks hide unrelated overlays and clear when semantic/window filters remove the selected endpoint. Pin heights retain the full structural latest arrivals; path selection does not pretend other inputs disappeared.

## Evidence

Compact evidence lives under `/Users/ecpeterson/Documents/code/hls_artifacts/runs/spacetime-2026-11-08/sink-path-view-1/`: `quality-1`, `javascript-final-1`, `controller-1`, `publication-review-1.json`, `real-data-review-1.json` and `browser-review-1.json`. Local qualification passes 322 JavaScript tests, 155 Erlang tests, formatting, Dialyzer and the 18-file source audit with zero findings. New graph tests compare against exhaustive small-DAG path enumeration; they are algorithm fixtures, not native hardware proofs. Controller/geometry regressions cover invalid input, disabled views, unknown competitors, selection caches and highlighted direction/readiness handling.

Algorithm 4 adds 115,974 unique exact native pin names to the rendering derivative. All previous geometry coordinates, timing and other tables are byte-identical. The 61,764 events, 7,637 writes, 153 cones and 174,960 arcs remain intact. The new manifest SHA-256 is `4f21ce67376a3617b7a12c3fe031333ebed9aab5cfeb48fdbfc0959318d03932`; recording and complete-source manifest identities are unchanged. Preparation took 22.59 s at 2.98 GB peak guarded group RSS. No source evidence was replaced.

For clocks 1852–1854, the list has 5,394 known sinks and 2,805 outside registered scope. The leading chain is `____state_136_reg[341]/Q` to `____state_137_reg[123]/D`: 8.8154 ns = 4.0330 ns logic + 4.7824 ns net over 83 arcs. The all-sink union selects 12,305 cone/arc references; the selected chain selects 83, and its 0.5 ns near-longest union selects 5,044. The latter is a union, not a claim that every recombination is near-longest. In the guarded Node measurement, listing took 35.5 ms; all-sink selection/geometry took 99.0/392.7 ms, selected-path selection/geometry 0.2/5.8 ms, and near-path selection/geometry 18.4/90.6 ms. These timings exclude loading, browser DOM work and GPU drawing.

Browser review exercised all path modes, exact-name selection, strip highlighting, semantic-filter clearing, leaving arrival view, side view and fit controls. No browser errors were logged. The initial screenshot linked a 0.348 ns net contribution to its displayed geometry; the continuity follow-up below replaces its disconnected presentation.

## Interpretation and remaining work

These are independent per-arc SDF envelopes over the represented structural graph, not jointly sensitized execution, STA slack, congestion measurements or an achieved clock period. The local strip separates logic from transmission on one representative chain; it does not sum parallel alternatives. Unknown mapping outside the qualified target population remains a correspondence limitation. Neutral overlay collisions and further label/axis-density tuning remain in the campaign's display follow-up.

## Continuity follow-up — 2026-11-08

Known propagation is now solid. For incomplete routing with both native endpoint locations and known source/local/target timing, the arrival view supplies a direct schematic endpoint connection: thin continuous core plus a wider dashed sleeve. Propagation ends at source arrival plus local delay; a distinct readiness annotation still reaches the target's latest bound. Unknown timing or location never acquires a bridge. The inspector labels schematic connections, while original routing coverage, flat-view geometry and complete source evidence remain unchanged.

The same 83-arc chain has connected XY/arrival endpoints throughout, with 22 explicitly schematic net connections and no geometry sent to the unknown shelf. Its 8.8154 ns total is unchanged. All 22 original incomplete branches remain counted, including the seven unavailable under the original mapped-only display. Evidence is in `/Users/ecpeterson/Documents/code/hls_artifacts/runs/spacetime-2026-11-08/sink-path-continuity-1/`. Local checks pass 328 JavaScript and 155 Erlang tests, formatting, Dialyzer and the 18-file audit with no findings. Browser review covers continuity, geometry warnings and filter clearing. No native job, simulation or data preparation ran.
