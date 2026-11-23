# Native catalogue import

`priv/tools/export_spacetime.tcl` reads an existing checkpoint and copies previously verified whole-design STA SDF files from that exact checkpoint. It does not synthesize, place or route. Use a fresh output directory and an outer process/memory guard; the exporter enforces its 600-second, two-million-table-row and 256-MiB decoded ceilings where control returns to Tcl. Completed stages retain closed tables and progress metadata, but only the final complete manifest authorizes import. A failed prefix is diagnostic evidence, not a physical catalogue.

The call is `::hls_spacetime_export::run CHECKPOINT OUTPUT BUILD LIMITS TIMING_INPUTS`. `BUILD` contains `source`, `rtl` and `observation` digests; `LIMITS` may tighten the ceilings. `TIMING_INPUTS` contains `checkpoint_sha`, `mode sta`, up to nine `sample_nets`, and `fast`/`slow` dictionaries with `path` and `sha256`. Each SDF input and its copied output must match the supplied digest.

An optional sixth argument, `LOCATION_INPUTS`, reuses a completed `cells.tsv` without repeating placement queries. It contains `checkpoint_sha`, `build`, table `path`/`sha256`/`rows`/`bytes`, and `phase_path`/`phase_sha256` for the completed location-phase marker. The exporter checks the checkpoint/build identities, both file hashes, the phase's table counts, the decoded rows and the copied table's hash. Its required scalar property scan still checks every current native cell's identity, primitive type and placed LOC/BEL, or explicit unplaced disposition. The caller must bind the retained table and phase to that checkpoint in the verified input closure; an unrelated table cannot establish correspondence merely by naming the same build.

A successful export writes twelve tables, two timing reports and two whole-design STA SDF sidecars. The final `manifest.json` binds the source/RTL/observation identities, exact checkpoint digest, tool/part, table counts and bytes, and each SDF file's hash, corner and mode. `hls_spacetime_import:read/3` checks the expected identities and the complete inventory before accepting a catalogue. Cell and sampled delay-object properties use one lossless JSON string map per object inside the TSV; duplicate keys/objects, non-string values and inconsistent counters reject. The reader permits at most two million serialized table rows and 256 MiB across tables, reports and SDF files. It never invokes Vivado. The caller verifies the remote collection and the checkpoint's input closure.

Full timing uses Vivado's STA SDF export for both fast and slow process corners. The exporter accepts previously verified files from the same checkpoint and copies their exact bytes; it does not rerun implementation or silently generate replacement timing. `hls_spacetime_sdf:read/2` checks a supplied hash, parses bounded S-expressions without interning names, and preserves headers, primitive instances, conditions, transition lists and timing-check forms. It keeps numeric spellings, omitted min/typ/max fields and SDF escape spelling intact. The reader bounds a tree at eight million nodes, depth 128 and one MiB per token. Fast/slow process corners are distinct from the min/typ/max entries within a corner. Parsing does not establish that SDF names equal native names, or that an arc was exercised during this recording.

The two SDF files travel beside the execution bundle. Its `native.sdf` attachment retains compact file descriptions, timescale, corner/mode, counts and an instance-population digest; it does not duplicate the full timing tree in every trace. Consumers load the sidecars when needed and verify their hashes. An omitted SDF arc is unavailable evidence, never a zero-delay connection. STA timing checks, cell IOPATHs and INTERCONNECT records retain their distinct meanings.

The optional typed `native` attachment also retains canonical aliases, top-level ports, every net's query disposition, sampled native delay objects and maximum/minimum static paths. `sampled_nets` identifies exactly which nets were queried through the scalar timing API; all others say `not_queried`. This sampling is separate from the complete SDF files. Scalar delay corners use picoseconds and declare `net_delay_basis` as `interconnect_only` or `including_intrasite`; site-inclusive values cannot be called pure routing delay. Path slack, data delay and requirement use nanoseconds. Empty, failed and unattempted queries remain distinct; missing numbers remain `null`. Path endpoints and members must reference supplied catalogue objects. Complete path reports remain sidecars. Static timings and path membership add no execution dependencies and establish no dynamic sensitization.

Import and binding qualification are separate:

```erlang
Catalogue = hls_spacetime_import:read(ExportDirectory, Build, CheckpointSha256),
Claims = #{generated => [], bindings => []},
Joined = hls_spacetime_import:attach(Bundle, Catalogue, Claims).
```

`attach/3` validates the result and preserves the execution events, versions and dependency graph. It adds explicit `unmapped` dispositions for every resource omitted from `Claims`; this empty example therefore asserts no physical correspondence. A caller supplies reviewed generated-object descriptions and bindings only after independent qualification. Structural output-pin checks constrain a per-bit claim but do not prove it. Keep names-only candidates ambiguous, retain unknown execution roots and identify the evidence supporting any promoted association. `native.whole_rtl` remains `null` when the exporter has no separate input-closure identity; that missing field must not be treated as verification of the synthesis inputs.

## Selected routed topology

`priv/tools/export_routes.tcl` exports only the physical nets named by selected arcs in an already retained timing report. Call `::hls_spacetime_routes::run CHECKPOINT OUTPUT SELECTION LIMITS` in a fresh guarded Vivado process. `SELECTION` contains `build`, `checkpoint_sha256`, `report_sha256`, `selection_sha256`, and a flat `paths` list of dictionaries with `path_id`, `arc_index`, `report_net`, `canonical_net`, `source_pin` and `target_pin`. The caller verifies the report and selection bytes; the exporter verifies the checkpoint hash before and after extraction, exact native names, canonical aliases and pin-to-net membership. It does not query new timing paths or search for alternative routing.

Limits may tighten the ceilings of 600 seconds, two million records, 256 MiB, 1,000 unique nets, 50 saved paths and 10,000 selected net arcs. The outer guard covers blocking native queries. Report-net lookup, physical-net extraction and selected endpoint mapping are deduplicated. Only `routes.json` accompanied by a matching `complete.json` hash is complete evidence; `incomplete.json` and any partial JSON are diagnostic prefixes.

The JSON sidecar contains the selected path arcs and per-net nodes, PIPs, wire-to-tile memberships and exact logical-pin/BEL-pin/site-pin/node attachments. Positions use native `GRID_POINT_X`/`GRID_POINT_Y` in `tile_grid` units. A [NODE](https://docs.amd.com/r/2024.2-English/ug912-vivado-properties/NODE?contentId=BWKRuaRu~A4KLc4lmqsj8A) can span many tiles, so its wires are an unordered membership set, never a guessed polyline. [TILE properties](https://docs.amd.com/r/2024.2-English/ug912-vivado-properties/TILE?contentId=iYtqnVe31pL5pda0wJwp7w) provide grid positions; these are not metal centreline coordinates or physical distances.

Used PIPs come from `get_pips -of_objects NET`; their [uphill/downhill nodes](https://docs.amd.com/r/2024.2-English/ug835-vivado-tcl-commands/get_nodes?contentId=rno4Qbk33fsLHGp9kfCaUg) must belong to that net's native node population. `IS_DIRECTIONAL` distinguishes directional from bidirectional resources; a bidirectional resource does not establish its chosen flow direction. [Logical pins map to site pins](https://docs.amd.com/r/2024.2-English/ug835-vivado-tcl-commands/get_site_pins?contentId=2liE0c7WY0h_xBydVjnziA) through native objects, including any mapped BEL pins. Missing or ambiguous mappings remain explicit. Site-internal switches and geometry are not reconstructed: `intrasite` is a gap, not a zero-length connection. These static routes do not establish switching activity, dynamic sensitization or an execution dependency.

The small orchestration fixture runs with `tclsh test/native/export_routes_tests.tcl FRESH_OUTPUT_DIRECTORY`. It mocks native queries and checks fanout retention, multi-tile node membership, unresolved attachments, identity rejection and completion markers. Passing it does not qualify the Vivado APIs; a real export must separately inspect resolved, ambiguous and missing populations.

## Maintained route-selection workflow

Start with a fresh generic projection that includes a digest-bound timing report, and retain its full joined bundle (the compact view intentionally omits canonical nets and pins):

```sh
node scripts/select-routes.mjs --view /path/to/view/recording.json --bundle /path/to/joined/bundle.json --output /path/to/fresh-selection
```

The command checks build/checkpoint identities, selected cell positions, report provenance, exact canonical aliases and both endpoint pin memberships. It emits bounded `selection.json`, escaped `selection.tcl`, a portable `run.tcl`, and a complete hash manifest. It selects the existing saved paths; it never searches for new timing paths. The full bundle and projection must refer to the same observation build. Historical observation-plan extensions need their explicit separately reviewed rebinding; this command does not infer it.

Run the emitted driver with explicit checkpoint/exporter/output arguments under the established serial native process guard:

```sh
vivado -mode batch -source /path/to/fresh-selection/run.tcl -tclargs /path/to/routed.dcp /path/to/hls_spacetime/priv/tools/export_routes.tcl /path/to/fresh-route-export
```

Verify terminal status, owned process-group termination and every collected hash once. Require `complete.json` and its matching route JSON hash; preserve failures without relaunching implementation. Attach the completed, verified sidecar to the exact selected projection:

```sh
node scripts/attach-routes.mjs --view /path/to/view/recording.json --selection /path/to/fresh-selection/selection.json --routes /path/to/fresh-route-export/routes.json --out /path/to/new-routed-view.json
```

Use the viewer’s **Open file** on that result. Selection, report, checkpoint and route identities are checked again; unrelated fanout stays out of a selected source-to-sink branch. The route attachment does not reinterpret the execution graph. The exporter fixture and route-selection tests qualify orchestration locally; they do not substitute for native evidence.

## Complete recorded-computation routing

The [complete computation-routing workflow](computation-routing.md) retains the native graph and routes for recorded write associations, independently of the sampled STA reports above. Its exporter accepts the complete canonical-net/endpoint demand, reuses closed native records, and requires a final whole-population manifest. The original selected-route exporter remains available for bounded static-report comparisons.
