# Passive source-protocol capture

The source-protocol observer records one clock domain from a generated `protocol_application_top`. It adds simulator visibility, not hardware. The supported boundary is the monolithic, single-stage `protocol_boundary_core` emitted by the source-build workflow, without shared arithmetic groups. Other schedules and register update forms must be qualified separately; missing or ambiguous controls reject instead of becoming zero.

`xls_protocol_spacetime:plan/4` prepares the offline observer: it checks the source-build input hashes, resolves committed receiver callsites in retained XLS IR, and matches the resulting scalar declarations and update enables in RTL. It distinguishes preview evaluation from committed transitions. Tuple-state association uses the pinned XLS flattening convention; narrowed registers retain their actual encoded width and are not decoded with original source offsets. This is an observed generated-code correspondence, not a native equivalence proof.

`xls_protocol_spacetime_capture:capture/3` consumes that plan and the standalone `hls_spacetime` library's bounded trace reader. It records receiver acceptance/completion/directives, publication acceptance, capture-slot leases, actual enabled data-register writes and selected register reads. Equal-valued writes get distinct versions. Only a live admitted head with actual action-valid/selected/blocked controls can acquire an entry-wait event. Reset retires pending identities. Every adjacent nonreset Q/D/enable transfer is checked; the final sampled write has no following Q sample to check.

The observer covers retained data registers at least 16 bits wide plus the requested semantic control taps. Small control registers remain sampled, but are not all expanded into storage histories. Register reads are combinational observation lanes, not claims about BRAM ports. Capture interpretation first records register/semantic events, then adds endpoint-to-public transfers, qualifies publication ownership, and attaches selected scalar operands before generic graph validation. Each stage leaves unsupported or unobserved ancestry explicit. Chronological coverage is not complete step ancestry. Public stream backpressure is recorded separately from internal blocking.

## Endpoint-to-public transfer attribution

The tap plan also binds the exact retained deployment, generated application wrapper and gateway configuration. It renders those mechanical files in memory and requires byte equality with the saved source, then checks retained gateway/framing support against the installed libraries. This is a checked generated-code correspondence, not a gate-level equivalence proof. Changed support or wiring requires observer qualification. The current scope is one explicit-start application without inspection; the gateway permits up to eight payload words.

The additional `eventN_data`, `eventN_valid` and `eventN_ready` taps observe complete frames accepted between the boundary and the serialized public gateway. Each acceptance receives its own endpoint/reset-incarnation/ordinal identity, even for identical payloads. Public words advance only on accepted `valid && ready` edges. A completed public frame consumes the oldest occurrence accepted no later than its first public word for the declared route; exact frame bytes validate that already selected match. Different routes can complete in either order. Missing admissions, changed or reordered frames, unknown routes and inconsistent final-word markers reject. Unaccepted offers need not remain stable.

A separate `stream` observer adds `boundary_transfer` and `public_frame` events linked by an ordinary version dependency, preserving the register observer's IDs. This stage initially leaves source publication behind each boundary transfer as an unknown root; publication attribution can refine it using the ownership evidence below. Control/attachment output retains a separate unknown management root. A stream edge alone explains only the observed boundary-to-host transfer, not a source path or sensitized combinational path.

`Capture.stream.frames` records each completed frame's `event`, `transfer` (or `null` for management), `incarnation`, `route`, `endpoint`, `host`, zero-based per-route `ordinal`, accepted final-word `cycle`, `first_cycle` and complete `words` including route/header. Ordinals include every public frame on that route within the reset incarnation. The capture envelope keeps this backend sidecar separate from `Capture.bundle`, which contains only the generic graph vocabulary. Application annotations should join these identities first and use timestamp/payload equality only to check the join. `pending` and `partial` disclose accepted frames and serialization prefixes remaining at the capture boundary; a complete recorder footer does not imply a drained gateway. Reset clears both, preserving their previous identities in `retired` without joining them to later outputs.

## Publication ownership and scalar operands

`xls_protocol_spacetime_publication` checks retained transport/network source against the installed emitters and binds publication pending/busy state, capture-slot ownership and endpoint arbitration to existing register taps. Its supported scope is a whole single-stage network without crossing links or inspection. Admission, pending-bit retirement and capture leases identify publication occurrences; payload equality does not choose a producer. Supported arrivals, capture writes and endpoint transfers can acquire those producers by refining their existing unknown nonstorage versions. Original event identities, clocks, storage accesses and stored versions remain intact. Unsupported control encodings and carry-in work without an observed admission stay unresolved. Reset retires pending publications; an unfinished capture tail does not imply completion.

`Capture.publication` retains the `refinements`, observed `publications`, capture-end `pending`, reset `retired`, and `unresolved`/`unsupported` records, with checked `source_files` identities. This sidecar explains the backend ownership join; the generic bundle carries the resulting version dependencies. It establishes recorded control/ownership correspondence, not decoded numerical payload semantics, native equivalence or sensitized paths.

`xls_protocol_spacetime_dependencies` prepares a scalar expression plan from the exact optimized XLS IR and RTL. It checks emitted state/register bindings and direct scalar receive-field bindings; selector operands retain control dependencies while only runtime-selected data alternatives are followed. Supported literal-table reads retain their index dependencies. Unsupported expressions, unknown selectors and missing observations remain explicit unknowns. The parser bounds input size, scalar width, nodes, table contents and each operand walk; it is a restricted observer interpreter, not an alternative XLS compiler.

`xls_protocol_spacetime_ancestry` evaluates that plan once per sampled write edge and compares every known result with the independently observed enabled D value. A mismatch rejects, including on the final edge where no next-Q sample exists. It can refine a still-unknown D version through computation and read-result events. All computations at the same edge read the same pre-edge stored versions; writes become current only after that edge's reads are attributed. Publication-resolved roots keep their producer. Unrepresented small state, external inputs and unsupported expressions remain unknown operands rather than acquiring a guessed storage history.

A read's optional `read_mask` identifies selected operational bits of the retained encoded register, including selector controls where required. It is neither a source-layout mask nor a measurement of electrically influential bits. The request and zero-latency result use the same mask/version and separate observation lanes; these are not extra physical read ports. `Capture.ancestry` reports `writes`, `values_checked`, `values_unknown`, `refined`, `reads` and per-write `operands`. Each operand row names its computation `event` and target `write`, separate `data_masks` and `control_masks`, unresolved descriptors and `value_checked`. Sidecar masks are hexadecimal strings; `hls_spacetime:encode/1` likewise preserves graph read/write masks as hexadecimal text. Added events, versions and operand rows share a finite record budget. Value agreement is a finite check of this interpretation, not an all-input equivalence proof.

Publication and scalar attribution produce a new interpretation bundle. They do not edit archived captures or upgrade retained placement/timing evidence. Selected operational dependencies are distinct from dynamically sensitized gates, native timing paths and routed wire geometry; none of those is established by this adapter.

## Build the optional adapter

The adapter and `hls_spacetime` are local OTP library applications selected by the root `spacetime` rebar3 profile. Ordinary builds and releases exclude both. From the repository root, use OTP 28.0.2 and rebar3:

```sh
rebar3 as spacetime compile
rebar3 as spacetime eunit --dir=apps/hls_spacetime_observer/test
```

When converting a capture, add `_build/spacetime/lib/hls_spacetime_observer/ebin` and `_build/spacetime/lib/hls_spacetime/ebin` to the Erlang code path. The application-specific live stimulus still uses the ordinary fabric build. Generic artifact validation and visualization live in [`hls_spacetime`](../../apps/hls_spacetime/README.md); native physical import and timing adapters live in `hls_target`.

## Prepare, record and interpret

Compile the optional profile once, then use `bin/hls-spacetime-observer`. This command publishes or interprets files; it never runs the compiler, simulator or application host. Supply the ordinary source build, its raw/optimized boundary IR, exact boundary RTL and compiled `files.f` directory in one trusted Erlang configuration:

```erlang
#{source => "/absolute/source-build",
  raw_ir => "/absolute/raw.ir",
  optimized_ir => "/absolute/optimized.ir",
  boundary_rtl => "/absolute/compiled/boundary/core.v",
  compiled => "/absolute/compiled"}.
```

The default scope is `full`: missing semantic controls reject. Add `scope => storage` explicitly when requesting only enabled register writes and Q/D/enable checks. This scope removes actor, ownership, publication, scalar-ancestry and stream attribution; the preparation and capture manifests retain the original unsupported-control diagnostics. It is useful when XLS has erased semantic aliases in a small workload. No missing control is replaced with zero, and every D producer remains unknown.

Paths resolve from the invoking directory. Source preparation and XLS compilation use the ordinary build toolchain; the observer does not choose its backend or schedule. Keep those original build artifacts and tool identities. Run from the umbrella checkout with OTP 28.0.2 and rebar3 on `PATH`:

```sh
rebar3 as spacetime compile
bin/hls-spacetime-observer prepare observer.config /absolute/fresh-observer
sh /absolute/fresh-observer/build-simulator.sh /absolute/path/to/verilator
```

Apply the project's serial 6 GiB process-group guard to external compilation and recording. Preparation derives fault aggregation from the checked application actor population, renders the packaged harness and copies its RTL/header closure. Mechanical RTL files whose names occur in the source manifest must match those emitted bytes. XLS-generated RTL is retained with exact file hashes; the external compiler and its input closure remain the trust boundary, not an all-input equivalence claim. It emits deterministic `observation.etf`, `taps.tsv`, raw/optimized IR, `source-build.json`, `build-simulator.sh` and a final `manifest.json` with exact file sizes and SHA256 digests. The script compiles one worker with `--vpi --public-flat-rw`; it refuses an existing `obj_dir`. Preparation accepts at most 512 RTL paths and 256 MiB total copied inputs. No old `_build/spacetime-*` directory is required.

`xls_protocol_spacetime_workflow:prepare/1` and `write/2` expose the same stages as library calls. `prepare/1` accepts this config map or a filename containing one map; `write/2` writes a fresh directory. Retained paths are diagnostic provenance; the prepared simulator inputs and plan are self-contained. The optional observer's `priv/simulator` owns its harness; `hls_target` owns the shared framed FIFO helper; `hls_spacetime` owns the trace header.

The executable accepts these modes. Create each fresh output directory first:

```text
simulation live FRESH_DIRECTORY TAPS
simulation replay CAPTURE FRESH_DIRECTORY TAPS
simulation drive INPUT_CAPTURE FRESH_DIRECTORY TAPS
```

For example:

```sh
mkdir /absolute/fresh-recording
/absolute/fresh-observer/obj_dir/simulation live \
  /absolute/fresh-recording /absolute/fresh-observer/taps.tsv
```

While `live` is running, invoke the application's ordinary host session against that directory's `app_tx`/`app_rx` FIFOs. The application owns finite stimulus, completion interpretation and any numerical oracle. The observer has no Phi/Snowflake selection. `replay` drives every recorded input/ready offer and compares every public field and selected tap on every clock, including inactive data. `drive` applies offered inputs without comparing outputs; qualify its new outputs before using them as a witness. `TAPS=-` records public fields only. No VPI writes or synthesized preservation attributes are added.

The fixed [recording dialect](spacetime-trace-format.md) uses pre-edge samples and cycle indices, not nanoseconds. The simulator caps elapsed time at 120 seconds; the transport caps four million cycles, one million sample records and 256 MiB decoded data. Missing handles, width mismatches, malformed records and unknown VPI values reject. Missing/incomplete footers never establish complete capture. The external runner and application host must finish and close their resources before archiving; process cleanup and tool identity recording remain the caller's responsibility.

Convert the saved recording without reopening the compiler sources:

```sh
bin/hls-spacetime-observer capture /absolute/fresh-observer \
  /absolute/fresh-recording/capture.tsv /absolute/fresh-capture
```

The library equivalent is `xls_protocol_spacetime_workflow:write_capture(PreparedDirectory, TraceFile, OutputDirectory)`. It verifies the preparation's exact plan hash and build identity, reads the bounded trace, runs `xls_protocol_spacetime_capture:capture/3`, and validates the graph. The fresh output contains `bundle.json`, deterministic uncompressed `bundle.etf`, `summary.json`, available `stream.json`/`publication.json`/`ancestry.json` sidecars, and a final manifest binding all outputs and inputs. Total output is capped at 256 MiB; the plan is capped at 16 MiB. Failed writes leave an incomplete directory without a final manifest. Existing directories are never replaced. Explicitly incomplete traces remain labelled incomplete even when conversion itself succeeds.

Prepared ETF files are trusted local producer artifacts; do not pass arbitrary downloaded terms to this command. The file hash and deterministic `observation_digest/1` have separate roles. New plans use deterministic external-term identity on the pinned OTP toolchain. Historical captures retain their original identities; never rebind them silently to a new plan.

The graph is application independent. Phi's finite completion/readout adapter remains `phi_spacetime_fixture:summary/2` and `bind_summary/2` under `apps/hls_phi/test`; it joins actual public route/incarnation/occurrence identities. Other workloads supply their own optional annotations rather than modifying the observer. Unrepresented controls and unsupported expressions remain unknown roots; complete file coverage does not imply complete causal ancestry.

Physical correspondence is absent until an independently qualified exact-checkpoint catalogue and claims are attached through the standalone library. The optional producer command qualifies explicit register candidates against independently reviewed finite replay summaries:

```sh
bin/hls-spacetime-observer qualify CATALOGUE.etf BUNDLE.etf \
  CANDIDATES.etf WITNESS.etf /absolute/fresh-claims
```

`xls_protocol_spacetime_physical` documents the candidate and witness types. Inputs are trusted uncompressed local terms; native catalogue and bundle schemas are checked first. The command checks exact build/checkpoint/declared netlist and probe identities, every nonempty comparison case, masks, zero mismatches/unknown samples, and actual output-pin/canonical-parent-net membership. It writes `claims.etf`, qualification detail and a byte/hash manifest; the standalone `spacetime join` command consumes those claims. Candidate discovery, native replay and authenticity of the supplied comparison summary remain independent producer responsibilities. Names-only candidates never become supported, and missing bits remain unknown.

Use its maintained validate/join/view workflow on `bundle.etf`/`bundle.json`; there is no requirement for the historical S3/S4 archive layout. Logical cycles and register names imply neither placement nor an execution period. The optional [RAM witness](../hls_spacetime/memory-witness.md) supplies its own small recording with explicit RTL paths and no native placement.

Run `rebar3 as spacetime eunit --dir=apps/hls_spacetime_observer/test` for localized plan/binding/transfer/reset, file-integrity, publication and operand checks. Synthetic producer tests check serialization and fresh output behavior; they do not establish simulator noninterference or a generated observer ABI. A localized generated source-protocol fixture can qualify a new packaging path without repeating a full decoder run. Qualify changed observer semantics separately, preserving prior identities and evidence.

## Inspect the retained S3/S4 case

The retained example is the external `spacetime-2026-11-06` archive, not a build directory. `capture-1/manifest.json` binds the live/reset traces, already interpreted JSON graphs, public-frame summaries, memory fixture and reproduction inputs. `physical-1/manifest.json` binds the joined graphs and native sidecars. To reopen the saved example, enter the umbrella's `apps/hls_spacetime` directory:

```sh
cd apps/hls_spacetime
node scripts/prepare-example.mjs \
  --physical-archive /path/to/spacetime-2026-11-06/physical-1 \
  --capture-archive /path/to/spacetime-2026-11-06/capture-1 \
  --output web/data
npm start
```

This reads saved evidence; it does not repeat simulation or native implementation. The original complete graphs and their hashes stay unchanged. The selected application interval is 99 clocks, and its failed 5 ns setup target supplies no validated execution period.

For source-level reproduction, the S3 archive retains `observer-sources.tar.gz`, `source-emission.tar.gz`, `compiled-inputs.tar.gz` and `qualification.tar.gz` together with its input manifests. Their internal paths describe the historical source layout. Extract into a fresh directory and use those recorded sources/tool identities if reproducing the historical producer; do not substitute the current repository layout or reinterpret an old identity silently. In particular, the original observation identity hashes the exact retained ETF bytes, while new captures use `observation_digest/1`. Preserve the original hashes and existing JSON for the frozen case. A new capture is a new evidence bundle even when its logical workload is unchanged.
