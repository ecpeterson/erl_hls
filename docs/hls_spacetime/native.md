# Native catalogue import

## openXC7 placement

For a self-contained Verilog or SystemVerilog module named `top`, the target capture tool runs Yosys and nextpnr-xilinx from an Apio installation. Supply the matching little-endian Project X-Ray v1 chip database. The example uses the compile-only Z-7030 pin constraints. Run from the umbrella root with a fresh output directory and the project’s outer process guard.

```sh
python3 apps/hls_target/priv/tools/export_openxc7.py \
  --apio-home "$ERL_HLS_APIO_HOME" --chipdb "$CHIPDB" \
  --rtl apps/hls_spacetime/test/native/openxc7/placement.v \
  --xdc platforms/xc7/xc7z030sbg485.xdc \
  --source-id g4-placement-v1 --observation-id placement-only \
  --max-cells 32 --max-bytes 1048576 capture
rebar3 as spacetime escriptize
_build/spacetime/bin/spacetime import-openxc7 capture capture/identity.term catalogue
```

The raw implementation manifest identifies the exact part (device, package and speed grade), chip database, Apio builds, launcher and executable hashes, synthesis command and router arguments. It inventories the original RTL, constraints, synthesis JSON, post-route JSON and chipdb location table. The ceiling covers their **combined uncompressed bytes**. Raw and stored sizes coincide. Captures start with an incomplete manifest and retain partial files and tool logs on failure. The defaults are 100,000 packed cells and 64 MiB of sidecars. A bounded application capture can request up to 384 MiB. Console logs are diagnostics outside the evidence inventory.

The example’s `identity.term` is a receipt. When joining an independent trace, use its expected build identity. The RTL component is the SHA-256 of the Verilog input, the implementation component is the SHA-256 of the exact complete manifest, and the checkpoint is the SHA-256 of `routed.json`. The caller identifies the original source and observation. The offline importer checks the file hashes, native route-complete marker, cell count, used location inventory and unresolved count. It preserves the complete native `NEXTPNR_BEL` attribute, including nested I/O BEL names. Tile-owned BELs have a null site and a known tile. Missing BELs are unplaced; unresolved BELs retain their spelling and have unknown coordinates. Placement supplies no timing or resource bindings.

The opt-in EUnit placement witness reads `OPENXC7_PLACEMENT_FIXTURE` and `OPENXC7_TILEGRID` (absolute paths to the example capture and the device’s independent Project X-Ray `tilegrid.json`). Run `bash tools/test_umbrella_eunit.sh spacetime` with both variables set to check every packed primitive and its native BEL and grid coordinates. The normal suite exercises missing, unplaced and tile-owned BELs, digest substitution and cross-implementation joins offline.

## openXC7 routes and computation timing

Add `--route-net NAME` for each net or alias to inspect, or `--route-all` to capture every packed net under the same explicit byte and route-object limits. Both the exporter and offline reader check a whole-design selection against the net names in the routed JSON. The inventory includes nets with unresolved endpoints. Stock nextpnr exports each selected packed port, BEL pin and bound wire. The exporter joins these to directed fixed-route PIPs using their native tile and wire indices. In the viewer, select the net and sink under **openXC7 routes** to inspect its ordered switches and tile footprints. Missing endpoints and ambiguous branches have a disposition and a gap. The tile marks locate the resources at chipdb resolution.

For timed cones, build the pinned timing observer once, then add `--timing-tools "$TIMING_TOOLS"` at capture. The optional final argument to the build script is a local cache containing the verified nextpnr and Eigen source archives. For a package-overlay chipdb, supply `--chipdb-manifest PATH` to record its stamped package, reference part and database hashes.

```sh
bash platforms/xc7/timing_coverage/build_spacetime.sh "$TIMING_TOOLS" "$ARCHIVE_CACHE"
```

The observer retains original port identities through LUT fracturing and input permutation, plus nextpnr cell arcs, per-sink delays, sequential timing roles and clocks. Its model supplies one structural estimate in picoseconds. The viewer preserves routed, predicted and unavailable delay queries. Slice flip-flop setup, hold and clock-to-Q use compiled constants. Characterization of individual database entries remains unverified. A recording supplies no measured board period.

Supply repeated `--rtl FILE` options in synthesis order for a multi-file top. The generated source index binds each staged file by digest. Yosys must report exactly those application inputs outside its technology library. Use `--flatten` for a flattened top. A timing observer can take `--focus-bit NET[BIT]` and `--focus-word NET` to retain the matching FDRE roots and their combinational fan-in. The scoped maximum is 650,000 timing objects. The route graph has its own 100,000-object limit. `--sta --route-sta` captures the ordered setup checks and requests their nets. Pair a later `--route-net` request with `--route-checkpoint SHA256` to check the routed bytes before publishing. The [N2 comparison](backend-coverage.md) exercises these options and builds both prepared viewer indexes.

Use `--storage-word RESOURCE=RTL_NET` to nominate an LSB-first synthesis net for a semantic word in the trace. Qualification checks the original FDRE configuration and its packed D, Q, rising clock, enable, synchronous reset, initial value and actual BEL-pin connectivity. Other configurations or incomplete origins retain unknown bits. To join the resulting evidence, use the trace’s expected implementation and the saved checkpoint digest.

```sh
_build/spacetime/bin/spacetime join-openxc7 trace/bundle.etf capture "$ROUTED_SHA256" joined
node apps/hls_spacetime/scripts/prepare-view.mjs --bundle joined/bundle.json --openxc7 capture --output view
npm --prefix apps/hls_spacetime start -- --data "$PWD/view"
```

Run the three serial, compile-only witnesses from the umbrella root under the local process guard. `TILEGRID` is the device’s Project X-Ray `tilegrid.json`. Set `OPENXC7_CHIPDB_MANIFEST` to include the package-overlay check. The script uses fresh output directories and requires Icarus Verilog from the Apio suite.

```sh
bash apps/hls_spacetime/test/native/openxc7/run_witness.sh \
  "$ERL_HLS_APIO_HOME" "$CHIPDB" "$TILEGRID" "$TIMING_TOOLS" fresh-witness
```

The fixtures check native placements, both branches of an aliased net including site PIPs, and two fractured LUT outputs feeding enabled/reset registers. An eight-edge finite replay checks both stored bits against independent expectations. The timing check compares the observer with nextpnr’s own SDF writer on the same routed result, allowing 1 ps for writer rounding. The viewer consumes the native estimates directly. Removing a PIP endpoint, a storage binding or a cell arc exercises the corresponding gap.

## Vivado checkpoint and SDF

The target-owned `apps/hls_target/priv/tools/export_spacetime.tcl` reads an existing checkpoint and copies previously verified whole-design STA SDF files from that exact checkpoint. It does not synthesize, place or route. Use a fresh output directory and an outer process/memory guard; the exporter enforces its 600-second, two-million-table-row and 256-MiB decoded ceilings where control returns to Tcl. Completed stages retain closed tables and progress metadata, but only the final complete manifest authorizes import. A failed prefix is diagnostic evidence, not a physical catalogue.

The call is `::hls_spacetime_export::run CHECKPOINT OUTPUT BUILD LIMITS TIMING_INPUTS`. `BUILD` contains `source`, `rtl`, `observation` and realized-`implementation` digests; `LIMITS` may tighten the ceilings. `TIMING_INPUTS` contains `checkpoint_sha`, `mode sta`, up to nine `sample_nets`, and `fast`/`slow` dictionaries with `path` and `sha256`. Each SDF input and its copied output must match the supplied digest.

An optional sixth argument, `LOCATION_INPUTS`, reuses a completed `cells.tsv` without repeating placement queries. It contains `checkpoint_sha`, `build`, table `path`/`sha256`/`rows`/`bytes`, and `phase_path`/`phase_sha256` for the completed location-phase marker. The exporter checks the checkpoint/build identities, both file hashes, the phase's table counts, the decoded rows and the copied table's hash. Its required scalar property scan still checks every current native cell's identity, primitive type and placed LOC/BEL, or explicit unplaced disposition. The caller must bind the retained table and phase to that checkpoint in the verified input closure; an unrelated table cannot establish correspondence merely by naming the same build.

A successful export writes twelve tables, two timing reports and two whole-design STA SDF sidecars. The final `manifest.json` binds the source/RTL/observation/implementation identities, exact checkpoint digest, tool/part, table counts and bytes, and each SDF file's hash, corner and mode. `hls_spacetime_import:read/3` checks the expected identities and the complete inventory before accepting a catalogue. Cell and sampled delay-object properties use one lossless JSON string map per object inside the TSV; duplicate keys/objects, non-string values and inconsistent counters reject. The reader permits at most two million serialized table rows and 256 MiB across tables, reports and SDF files. It never invokes Vivado. The caller verifies the remote collection and the checkpoint's input closure.

Full timing uses Vivado's STA SDF export for both fast and slow process corners. The exporter accepts previously verified files from the same checkpoint and copies their exact bytes; it does not rerun implementation or silently generate replacement timing. `hls_target_sdf:read/2` checks a supplied hash, parses bounded S-expressions without interning names, and preserves headers, primitive instances, conditions, transition lists and timing-check forms. It keeps numeric spellings, omitted min/typ/max fields and SDF escape spelling intact. The reader bounds a tree at eight million nodes, depth 128 and one MiB per token. Fast/slow process corners are distinct from the min/typ/max entries within a corner. Parsing does not establish that SDF names equal native names, or that an arc was exercised during this recording.

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

The target-owned `apps/hls_target/priv/tools/export_routes.tcl` exports only the physical nets named by selected arcs in an already retained timing report. Call `::hls_spacetime_routes::run CHECKPOINT OUTPUT SELECTION LIMITS` in a fresh guarded Vivado process. `SELECTION` contains `build`, `checkpoint_sha256`, `report_sha256`, `selection_sha256`, and a flat `paths` list of dictionaries with `path_id`, `arc_index`, `report_net`, `canonical_net`, `source_pin` and `target_pin`. The caller verifies the report and selection bytes; the exporter verifies the checkpoint hash before and after extraction, exact native names, canonical aliases and pin-to-net membership. It does not query new timing paths or search for alternative routing.

Limits may tighten the ceilings of 600 seconds, two million records, 256 MiB, 1,000 unique nets, 50 saved paths and 10,000 selected net arcs. The outer guard covers blocking native queries. Report-net lookup, physical-net extraction and selected endpoint mapping are deduplicated. Only `routes.json` accompanied by a matching `complete.json` hash is complete evidence; `incomplete.json` and any partial JSON are diagnostic prefixes.

The JSON sidecar contains the selected path arcs and per-net nodes, PIPs, wire-to-tile memberships and exact logical-pin/BEL-pin/site-pin/node attachments. Positions use native `GRID_POINT_X`/`GRID_POINT_Y` in `tile_grid` units. A [NODE](https://docs.amd.com/r/2024.2-English/ug912-vivado-properties/NODE?contentId=BWKRuaRu~A4KLc4lmqsj8A) can span many tiles, so its wires are an unordered membership set, never a guessed polyline. [TILE properties](https://docs.amd.com/r/2024.2-English/ug912-vivado-properties/TILE?contentId=iYtqnVe31pL5pda0wJwp7w) provide grid positions; these are not metal centreline coordinates or physical distances.

Used PIPs come from `get_pips -of_objects NET`; their [uphill/downhill nodes](https://docs.amd.com/r/2024.2-English/ug835-vivado-tcl-commands/get_nodes?contentId=rno4Qbk33fsLHGp9kfCaUg) must belong to that net's native node population. `IS_DIRECTIONAL` distinguishes directional from bidirectional resources; a bidirectional resource does not establish its chosen flow direction. [Logical pins map to site pins](https://docs.amd.com/r/2024.2-English/ug835-vivado-tcl-commands/get_site_pins?contentId=2liE0c7WY0h_xBydVjnziA) through native objects, including any mapped BEL pins. Missing or ambiguous mappings remain explicit. Site-internal switches and geometry are not reconstructed: `intrasite` is a gap, not a zero-length connection. These static routes do not establish switching activity, dynamic sensitization or an execution dependency.

From the umbrella root, the small orchestration fixture runs with `tclsh apps/hls_target/test/native/export_routes_tests.tcl FRESH_OUTPUT_DIRECTORY`. It mocks native queries and checks fanout retention, multi-tile node membership, unresolved attachments, identity rejection and completion markers. Passing it does not qualify the Vivado APIs; a real export must separately inspect resolved, ambiguous and missing populations.

## Maintained route-selection workflow

Start with a fresh generic projection that includes a digest-bound timing report, and retain its full joined bundle (the compact view intentionally omits canonical nets and pins):

```sh
node apps/hls_spacetime/scripts/select-routes.mjs --view /path/to/view/recording.json --bundle /path/to/joined/bundle.json --output /path/to/fresh-selection
```

The command checks build/checkpoint identities, selected cell positions, report provenance, exact canonical aliases and both endpoint pin memberships. It emits bounded `selection.json`, escaped `selection.tcl`, a portable `run.tcl`, and a complete hash manifest. It selects the existing saved paths; it never searches for new timing paths. The full bundle and projection must refer to the same observation build. Historical observation-plan extensions need their explicit separately reviewed rebinding; this command does not infer it.

Run the emitted driver with explicit checkpoint/exporter/output arguments under the established serial native process guard:

```sh
vivado -mode batch -source /path/to/fresh-selection/run.tcl -tclargs /path/to/routed.dcp /path/to/erl_xls/apps/hls_target/priv/tools/export_routes.tcl /path/to/fresh-route-export
```

Verify terminal status, owned process-group termination and every collected hash once. Require `complete.json` and its matching route JSON hash; preserve failures without relaunching implementation. Attach the completed, verified sidecar to the exact selected projection:

```sh
node apps/hls_spacetime/scripts/attach-routes.mjs --view /path/to/view/recording.json --selection /path/to/fresh-selection/selection.json --routes /path/to/fresh-route-export/routes.json --out /path/to/new-routed-view.json
```

Use the viewer’s **Open file** on that result. Selection, report, checkpoint and route identities are checked again; unrelated fanout stays out of a selected source-to-sink branch. The route attachment does not reinterpret the execution graph. The exporter fixture and route-selection tests qualify orchestration locally; they do not substitute for native evidence.

## Complete recorded-computation routing

The [complete computation-routing workflow](computation-routing.md) retains the native graph and routes for recorded write associations, independently of the sampled STA reports above. Its exporter accepts the complete canonical-net/endpoint demand, reuses closed native records, and requires a final whole-population manifest. The original selected-route exporter remains available for bounded static-report comparisons.
