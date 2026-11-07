# Recorded computations and native routing

This workflow associates recorded storage writes with the native timing/connectivity circuitry feeding their qualified FF inputs. It retains the complete native net/pin population, both SDF corners and every event disposition. It does not select a worst-path subset, enumerate exponentially many paths, infer missing bit mappings, or establish electrical activity. The older [selected STA overlay](native.md#selected-routed-topology) remains an independent comparison.

Start with a prepared recording from [capture to view](workflow.md), the complete native export from the exact checkpoint, and its already verified fast/slow STA SDF files. Native collection must have verified exit/guards, process termination and all input/output hashes. The native manifest's row/byte counts alone do not authenticate a measurement.

## Project saved timing and connectivity

The projection preserves both corners’ DELAY arcs. Timing checks and other SDF forms remain in the authoritative original sidecars. Uninterpreted delay forms remain available in the projection’s issue list, but computation-graph preparation rejects any such issues: a partially understood delay population cannot supply a finite cone bound. Build the offline escript with `rebar3 escriptize`, then project each saved corner once:

```sh
_build/default/bin/spacetime sdf-arcs /path/to/timing-fast.sdf FAST_SHA256 fast /path/to/fast-arcs.json
_build/default/bin/spacetime sdf-arcs /path/to/timing-slow.sdf SLOW_SHA256 slow /path/to/slow-arcs.json
node scripts/prepare-computations.mjs \
  --view /path/to/view/recording.json \
  --native /path/to/native-export \
  --fast /path/to/fast-arcs.json --slow /path/to/slow-arcs.json \
  --out /path/to/fresh-computation-graph
```

The source-protocol observer's optional `--ancestry /path/to/ancestry.json` preserves exact selected operand/control masks. Without it, generic recorded producer/write relationships remain available and source-bit subsets stay explicitly unknown. The union of represented data/control masks must match the computation’s linked recorded operand reads; their data-versus-control classification remains producer metadata. These masks annotate sources; they do not prune native mux alternatives from a structural cone. A retained hash-indexed compressed native archive is also accepted. Raw legacy exports are checked against their declared row/byte counts, with any declared table hashes checked too; computed receipts are recorded separately from independently supplied expected hashes.

The preparation output contains shared table parts, a complete manifest and inspectable `demand.json`/`demand.tcl`. Native connectivity contributes every directed net edge; SDF IOPATHs contribute primitive timing dependencies. This is not an independent Boolean-function reconstruction. Sequential outputs terminate traversal. Unsupported primitives, undriven nets, missing timing, unknown target bits and semantic events without write endpoints remain explicit. All writes are classified, including publication-owned writes without a `register_compute` event.

## Extract missing routing geometry

Use a fresh, bounded Vivado process on the same saved checkpoint. Freeze the checkpoint digest, complete demand, exporter code, optional reused records and execution bounds first. An example driver is:

```tcl
source /path/to/hls_spacetime/priv/tools/export_route_graph.tcl
set demand [source /path/to/fresh-computation-graph/demand.tcl]
set reuse [dict create nets {}]
::hls_spacetime_route_graph::run /path/to/routed.dcp \
    /path/to/fresh-route-export $demand $reuse \
    [dict create seconds 3000 records 8000000 bytes 503316480 file_bytes 16777216]
```

The exporter opens the checkpoint read-only. It never synthesizes, places, routes, queries new STA paths or runs a simulation. Its outer process-group guard must also cover validation and blocking native calls. Ceiling bounds are 3,600 seconds, eight million output rows, 512 MiB new output, 16 MiB per file, 100,000 nets and one million endpoints; callers may tighten them. A ceiling rejects incomplete work rather than selecting an arbitrary successful subset.

Large inventories may use the optional `route_hash_worker.tcl` / `route_hash_worker.py` transport to avoid starting a checksum process for every shard. Source the Tcl helper after the exporters, call `::hls_spacetime_routes::start_hash_worker` with an argument list invoking isolated system Python (`/usr/bin/python3 -I`) and the helper with `--plan JOB/plan.json --output-root JOB/result/routes`, and call `stop_hash_worker` before the driver reports completion. The frozen plan must include both helpers. The worker reads only named inputs and that output subtree, streams fresh hashes without caching, and belongs to the same guarded process group; a worker failure fails the export and its stderr is retained. Isolation prevents Vivado’s bundled Python settings from changing the system interpreter. Without this optional transport, the existing per-file `sha256sum` implementation remains available.

Existing completed native net geometry and endpoint records can be supplied through the reuse contract documented beside `export_route_graph.tcl`. Each exact file has a byte count and digest, plus checked node/pin indexes. Reusing geometry does not requery its nodes, PIPs or wires; only missing endpoints are queried. Closed geometry, attachment batches and per-net indexes are immutable, with bounded append-only ledgers. Only the final complete manifest authorizes whole-population attachment. A failure retains closed shards for a separately registered continuation; an unfinished shard or ledger line is not reusable evidence.

Verify the terminal job once and collect its output once, preserving all hashes and the native absolute path for each retained file. Keep unresolved geometry instead of repairing it by guessing physical positions. Top-level ports retain exact net membership and an explicit unavailable site-geometry disposition.

## Publish the complete attachment

Create a JSON object mapping each native absolute file path named by the route manifest to its verified local file. Include reused inputs as well as newly collected files. Then:

```sh
node scripts/attach-computations.mjs \
  --view /path/to/view/recording.json \
  --computations /path/to/fresh-computation-graph/manifest.json \
  --routes /path/to/fresh-route-export/manifest.json \
  --route-files /path/to/native-to-local-files.json \
  --output /path/to/fresh-computation-view
npm start -- --data /path/to/fresh-computation-view
```

Assembly verifies every descriptor, canonical net and endpoint against the complete graph. It copies the exact recording and writes a manifest/index last. Shared JSON array parts are at most 32 MiB each and 512 MiB total. This complete source publication remains the evidence authority; the time window and filters never trim its retained population.

## Prepare rendering indexes

Compile the complete publication into a fresh rendering directory before opening a large capture:

```sh
node scripts/prepare-render.mjs \
  --input /path/to/fresh-computation-view \
  --output /path/to/fresh-render-view
npm start -- --data /path/to/fresh-render-view
```

If the input index contains several computation captures, add `--capture RECORDING_FILE`, using that entry's relative `file` value. The command requires one selected capture, verifies its recording and complete source graph, and derives reusable cone, event and spatial-geometry indexes. It does not rerun capture, native extraction or timing. It retains the exact recording, native manifest and every source part, using hard links where possible and exclusive copies across filesystems; treat both directories as immutable evidence. It writes the new index last and refuses to overwrite an existing output directory.

The derivative is bounded to 32 MiB per part and 256 MiB total. Its manifest binds the exact recording and complete source descriptor, with lengths, hashes and table counts. Precompressed siblings reduce transfer size; verification still covers the decoded original bytes. No geometry is sampled to satisfy a bound. An oversized or incomplete input fails explicitly.

The browser parses and indexes the recording in a worker, makes that recording interactive, then loads and validates the prepared circuit parts in a worker. It does not fetch the full retained source tables in this mode. A publication without a derivative still uses the complete-graph loader. **Loading details** separates recording transfer/verification, parsing, indexing and first-frame timings from circuit loading; these browser measurements are distinct from offline preparation time. Camera motion reuses uploaded geometry rather than traversing the source graph again.

See [the viewer guide](viewer.md#complete-computation-circuits) for circuit colors, functionality and static-delay filters, and the distinction between measured routing locations, schematic spans, timing dependencies and dynamic sensitization. No routed delay in this workflow establishes a physical execution period.
