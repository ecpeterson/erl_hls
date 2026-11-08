# Path neighborhoods and hypothetical register cuts

The user deferred architecture changes and requested the visualization follow-up. This adds two saved-evidence views to the existing sink inspector; it does not edit a compiler, RTL, native checkpoint or recording.

## Behavior

Path neighborhood finds all known visible sinks within a chosen timing tolerance and the selected representative path's native bounding box plus tile padding. It unions one maximizing chain per qualifying cone/sink, counts shared arc identities and shows every installed cell in the region on a separate placement reference plane. Selecting a path driver adds all represented native net consumers, including those outside the region or visible writes. These direct spokes express connectivity, not routing geometry or measured congestion. Unknown timing and locations retain explicit counts; paging never caps scene membership.

Candidate register cut computes the complete selected sink ancestry in the eligible timing scope. Combinational cells remain indivisible, and a cell enters the first stage only when its latest arrival fits the threshold and its predecessors are already there. Every eligible launch-to-sink path crosses once. Crossings occur after net drivers; existing net delays remain in stage 2, whose maximum is recomputed independently. Distinct nonconstant driver pins count bits once, even with multiple loads. Direct-source bypass storage and excluded external/constant input obligations are disclosed.

The default cut drawing retains one representative chain and every located crossing marker; an explicit checkbox draws the complete input graph. Counts and bounds always cover full eligible fan-in. Colors distinguish the two proposed sides while every position retains original native XY and saved arrival height. Nothing moves to an invented clock stage. Unknown eligible timing or unsupported graph structure prevents a numeric cut estimate.

The register count excludes valid/reset, tags, other outputs and actor state. Delay estimates reuse current routing and exclude new registers, clock-to-Q, setup, skew and changed placement/routing. No actor reissue interval, functional retiming legality or achieved period is established.

## Saved example review

The existing N2 source-protocol recording, clocks 1852–1854, has 5,394 known registered-launch sink rows and 2,805 outside scope. Its leading sink is `____state_137_reg[123]/D`, 8.8154 ns. Default neighborhood tolerance ±0.1 ns and padding 12 tiles retain 47 sinks, 286 union arcs, 145 shared arcs, 167 path cells and 7,271 other installed cells in the region. Two high-fanout path drivers have 109 and 92 represented sink pins. This population is placement/connectivity context, not a causal placement explanation.

At threshold 4.4077 ns, the complete eligible fan-in cut estimates 4.3957 ns before and 4.9916 ns after, crossing 215 bits and 468 net loads. Of those bits, 83 are direct-source bypasses. The excluded external reset feeds stage 1 only. Threshold zero instead crosses 907 launch bits and leaves the original 8.8154 ns after the cut; a threshold at the sink bound crosses one bit after 8.7664 ns, leaving 0.049 ns. These are graph diagnostics, not proposed architecture changes or speedup measurements. First uncached saved-example analyses took approximately 49–72 ms each in local Node; this is not a browser benchmark.

## Qualification

All 363 JavaScript tests pass, including exhaustive small-DAG path enumeration across 160 weight/threshold cases, full fan-in/reconvergence/bypass accounting, whole-cell closure, native fanout, unknowns, uncapped scene membership and controller/filter transitions. The 155 Erlang tests, formatting, Dialyzer and 18-file source-contract audit also pass. Serial local guards exited successfully with no guard trigger or surviving process group. The saved-example check peaked at about 1.37 GiB RSS.

Browser review checked the neighborhood, paging, full represented fanout, cut threshold updates, default/complete input-graph toggle and excluded-selection clearing. Both scenes were inspected and screenshots retained. No new native run, simulation, re-preparation or remote CI was needed. Logs, bound saved-example review and screenshots live in the external artifact directory `runs/spacetime-2026-11-08/path-neighborhood-cut-1` under `hls_artifacts`; the immutable computation/render manifest hashes are in `saved-example-review.json`.
