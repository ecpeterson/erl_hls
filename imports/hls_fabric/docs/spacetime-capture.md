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

The adapter is an OTP library application under `apps/hls_spacetime_protocol`, selected by the root `spacetime` rebar3 profile. Ordinary builds and releases exclude it and its private dependency. From the repository root, use OTP 28.0.2 and rebar3; access to the private `ecpeterson/hls_spacetime` repository is required only for this profile:

```sh
rebar3 as spacetime compile
rebar3 as spacetime eunit --dir=apps/hls_spacetime_protocol/test
```

When converting a capture, add `_build/spacetime/lib/hls_spacetime_protocol/ebin` and `_build/spacetime/lib/hls_spacetime/ebin` to the Erlang code path. The application-specific live stimulus still uses the ordinary fabric build. Generic artifact validation, physical import and visualization live in [hls_spacetime](https://github.com/ecpeterson/hls_spacetime), without a compiler dependency.

## Prepare and capture

Retain the source build, raw and optimized boundary IR, exact generated RTL and external tool identities. Do not regenerate them merely to inspect a saved execution. In a compiler/lowering Erlang environment:

```erlang
Plan = xls_protocol_spacetime:plan(SourceDirectory, RawIR, OptimizedIR, BoundaryRTL),
ok = file:write_file(TapFile, xls_protocol_spacetime:tsv(Plan)),
ok = file:write_file(PlanFile, term_to_binary(Plan, [deterministic])).
```

Use `xls_protocol_spacetime:observation_digest/1` for the semantic observation identity. It uses deterministic external-term encoding on the pinned OTP toolchain, so an equal plan has the same digest after decoding or map reconstruction. Retain the exact file hash separately; do not rebind an archived capture to a newly computed digest. Plan files are trusted local Erlang terms; do not accept arbitrary uploaded terms as configuration. `tsv/1` returns data and the caller owns writes. Source and RTL hashes in `Plan.inputs` describe the exact observation scope. Retain the whole application's RTL closure and simulator build command alongside it, including the gateway.

Use `test/rtl/protocol_spacetime_sim.cpp.in` with the source build's ordinary Verilator file list. Replace `@@SOURCE_FAULTS@@` with the OR of the emitted ingress, actor failure and actor fault pins, as in the ordinary application harness. Include both fabric's `test/rtl` and the standalone library's `priv/include` directories, enable `--vpi`, and use `--public-flat-rw` for tap visibility. The public interface and host framed FIFO adapter are unchanged. No VPI writes or synthesis preservation attributes are used.

The executable accepts:

```text
simulation live FRESH_DIRECTORY TAPS
simulation replay CAPTURE FRESH_DIRECTORY TAPS
simulation drive INPUT_CAPTURE FRESH_DIRECTORY TAPS
```

Create each output directory first. `live` exposes `app_tx`/`app_rx` FIFOs for the ordinary host session; the application owns the finite stimulus and oracle. `replay` drives every recorded input/ready offer and compares every public field and selected tap on every clock, including inactive data. `drive` deliberately applies inputs without comparing outputs, so altered-stimulus experiments must qualify the new output and then replay it. All modes write fresh `capture.tsv` files. `TAPS=-` records public fields only; an ordinary build without `--public-flat-rw` can replay against these fields to check observation noninterference.

The fixed protocol-stream recording dialect is owned by [hls_spacetime](https://github.com/ecpeterson/hls_spacetime); see [spacetime-trace-format.md](spacetime-trace-format.md) for its capture-side boundary. The runner caps time at 120 seconds; the transport caps four million cycles, one million records and 256 MiB decoded bytes. Apply a process-group memory limit and retain compressed results under an explicit archive budget. A missing or incomplete footer never establishes a complete capture.

## Convert a saved capture

```erlang
Trace = hls_spacetime_trace:read(CaptureFile),
#{inputs := #{source_build := SourceHash, rtl := RtlHash}} = Plan,
Build = #{source => SourceHash, rtl => RtlHash,
          observation => xls_protocol_spacetime:observation_digest(Plan)},
Capture = #{bundle := Bundle, stream := Stream,
            publication := Publication, ancestry := Ancestry} =
    xls_protocol_spacetime_capture:capture(Plan, Trace, Build),
ok = file:write_file(OutputFile, hls_spacetime:encode(Bundle)),
ok = file:write_file(StreamFile, json:encode(Stream)),
ok = file:write_file(PublicationFile, json:encode(Publication)),
ok = file:write_file(AncestryFile, json:encode(Ancestry)).
```

`bundle/3` is a convenience wrapper returning only the generic graph. Use `capture/3` when retaining stream identities, publication joins, scalar operand evidence or binding application annotations with `phi_spacetime_fixture:bind_summary/2`. The graph includes the supported dependencies in either case; backend interpretation metadata stays in the separate sidecars. The example uses a current `plan/4` result. For a trusted historical plan without publication/dependency sections, the corresponding `publication`/`ancestry` keys are absent; plans without stream taps produce an empty stream sidecar with an explicit unobserved scope. Preserve historical identities rather than substituting a new plan silently.

Physical correspondence is absent until a separately qualified exact-checkpoint catalogue is attached. Logical resources, simulated cycles and tuple names imply neither placement nor a clock period. Phi's finite step/readout interpretation is in `apps/hls_phi/test/phi_spacetime_fixture.erl`; it is not part of this lowering adapter.

Run `rebar3 as spacetime eunit --dir=apps/hls_spacetime_protocol/test` from the repository root for localized binding, register-transfer, publication ownership, selected scalar operands, same-edge/reset attribution and fresh-process plan-identity checks. The standalone library owns the C++ transport rejection tests, generic artifact/reader tests and memory recording conversion. The compiler owns the actual RAM primitive and its RTL witness. A full decoder run is needed to qualify a new observer ABI, not for each parser change.

## Inspect the retained S3/S4 case

The retained example is the external `spacetime-2026-11-06` archive, not a build directory. `capture-1/manifest.json` binds the live/reset traces, already interpreted JSON graphs, public-frame summaries, memory fixture and reproduction inputs. `physical-1/manifest.json` binds the joined graphs and native sidecars. To reopen the saved example, run from the `hls_spacetime` checkout:

```sh
node scripts/prepare-example.mjs \
  --physical-archive /path/to/spacetime-2026-11-06/physical-1 \
  --capture-archive /path/to/spacetime-2026-11-06/capture-1 \
  --output web/data
npm start
```

This reads saved evidence; it does not repeat simulation or native implementation. The original complete graphs and their hashes stay unchanged. The selected application interval is 99 clocks, and its failed 5 ns setup target supplies no validated execution period.

For source-level reproduction, the S3 archive retains `observer-sources.tar.gz`, `source-emission.tar.gz`, `compiled-inputs.tar.gz` and `qualification.tar.gz` together with its input manifests. Their internal paths describe the historical source layout. Extract into a fresh directory and use those recorded sources/tool identities if reproducing the historical producer; do not substitute the current repository layout or reinterpret an old identity silently. In particular, the original observation identity hashes the exact retained ETF bytes, while new captures use `observation_digest/1`. Preserve the original hashes and existing JSON for the frozen case. A new capture is a new evidence bundle even when its logical workload is unchanged.
