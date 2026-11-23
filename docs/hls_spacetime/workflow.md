# Capture to view

The workflow has three owners: the producer knows what generated signals mean; `hls_spacetime` validates saved execution and physical evidence; the viewer displays the resulting recording. Simulator and Vivado execution remain explicit external steps. None of the commands discovers or starts an EC2 instance, repeats implementation, or depends on a campaign archive.

## Prerequisites and outputs

Use OTP 28.0.2, rebar3 3.24.0 and Node 22 or later. Build this repository’s offline command with `rebar3 escriptize`. The XLS source-protocol adapter is the optional `hls_spacetime_observer` application in `hls_fabric`; use that repository’s `spacetime` profile and its [capture guide](https://github.com/ecpeterson/hls_fabric/blob/main/docs/spacetime-capture.md). Other backends supply the same generic bundle rather than importing this adapter.

Each stage takes explicit files and creates a fresh output directory. Keep source, emitted RTL, observation-plan and native-checkpoint identities with the result. A complete inventory is written last; a failed prefix is diagnostic material. Retain logs, tool versions and input/output hashes alongside a bounded capture, and apply the project’s seven-day artifact review policy. Never use a filename or equal signal values as evidence of correspondence.

The Erlang interchange is trusted local, uncompressed ETF. The reader limits each file to 256 MiB, rejects trailing bytes and executable terms, and creates no atoms from data. A producer should use `hls_spacetime_artifact:write_bundle/2`, which validates before writing `bundle.etf`, `bundle.json`, `summary.json` and an exact-byte manifest. JSON uses hexadecimal masks to preserve wide integers in the browser. This is a library/tool workflow; no OTP server or deployed observer process is started.

## Capture and interpret

Prepare the producer’s plan and simulator harness from the exact ordinary compiler outputs. Run the emitted simulator command under the project’s serial 6 GiB local guard and an explicit timeout, with application-owned finite stimulus. The recorder writes a bounded sample stream; the producer interprets it into events, storage versions and dependencies. Interpretation must not change the hardware or supply new causes based on matching values.

The maintained producer `prepare`, `capture` and `qualify` commands are documented in the producer capture guide. `capture` saves both the generic bundle and backend sidecars. Public completion/readout interpretation stays with the application. It can provide the optional navigation metadata described below; it does not become an execution dependency unless the producer supplies checked graph contributors.

For an immediately runnable small example, follow the [RAM witness](memory-witness.md). It exercises 17 clocks of masked writes, read-first collisions, response latency and reset retirement against explicitly supplied compiler RTL. Its memory placement remains unknown. Normal unit tests use smaller synthetic cases, with neither native implementation nor a full decoder simulation.

## Extract and qualify native evidence

Use [the native exporter](native.md) on an existing checkpoint from the exact compiled design, with separately verified fast/slow STA SDF files. An outer time/memory guard covers blocking tool calls. The exporter’s complete inventory authorizes import; an incomplete marker does not. Retain and verify all collected bytes before importing. This step reads the checkpoint and never synthesizes, places or routes it.

Create an identity file containing one trusted Erlang term, for example:

```erlang
#{build => #{source => <<"SOURCE_DIGEST">>, rtl => <<"RTL_DIGEST">>, observation => <<"PLAN_DIGEST">>},
  checkpoint => <<"CHECKPOINT_SHA256">>}.
```

Then import once:

```sh
_build/default/bin/spacetime import /path/to/native-export /path/to/identity.term /path/to/fresh-catalogue
```

Physical candidates come from the producer’s generated-register and connected-native-output evidence. The producer’s `qualify` command checks explicit candidates against a complete catalogue and identity-bound finite comparisons, including nonempty horizons, all candidate bits, mismatch/unknown counts and native output-pin/net membership. Constant-only finite observations are distinguished from exercised bits. Omitted bits stay unknown, shared cells stay shared, and unrelated semantic objects stay unmapped. The supplied comparison is a finite witness, not all-input equivalence; the caller retains the netlist/probe extraction and comparison evidence behind it.

Join the resulting claims and validate the result in a fresh process:

```sh
_build/default/bin/spacetime join /path/to/capture/bundle.etf /path/to/fresh-catalogue/catalogue.etf /path/to/claims.etf /path/to/fresh-joined
_build/default/bin/spacetime validate /path/to/fresh-joined/bundle.etf
```

Validation checks execution/storage consistency, evidence kinds, object references and claimed mapping coverage. It does not authenticate the caller’s files or establish dynamic gate sensitization. A recording without a physical catalogue remains useful; skip extraction and join when unavailable.

## Prepare, inspect and measure

```sh
node scripts/prepare-view.mjs --bundle /path/to/fresh-joined/bundle.json --output /path/to/fresh-view
node scripts/check-storage-view.mjs /path/to/fresh-view/recording.json
npm start -- --data /path/to/fresh-view
```

Preparation accepts plain or gzip JSON, bounded at 256 MiB decoded; the projection must fit the browser’s 128 MiB input limit. The independent storage audit allows at most one million word-clock comparisons and rejects contradictions; incomplete observation coverage remains unqualified. Serving is read-only on loopback. `--port` selects a different port. Later repeated scalar options take precedence.

An optional `--metadata CONTEXT.json` carries only `title`, `selection`, `annotations`, `examples`, `scope`, `coverage` and `measurement`; it cannot replace the bundle, catalogue or provenance. `selection` contains `firstCycle` inclusive and `endCycle` exclusive, within the capture. Public/boundary annotations with graph contributors must pass the same identity/incarnation checks as a normal view. Without metadata, the initial window is the capture and no application-specific navigation is invented. Without placement, resource/address lanes are explicitly logical.

For saved static timing, add `--timing-report REPORT.rpt --timing-identity VERIFIED.json`. The independent extraction identity contains `build`, `checkpoint` and `report_sha256`; all must agree with the joined catalogue and exact decoded report bytes. Retain this identity when verifying collection, rather than manufacturing it from an unrelated report during attachment. A stale report with matching cell names is insufficient. Report size is bounded at 4 MiB. For circuitry associated with the recorded writes, use the [complete computation-routing workflow](computation-routing.md). The separate selected-STA overlay remains described in [native import](native.md). Neither adds execution edges.

Metrics retain their domains: elapsed clocks, consumed word-clocks, operations per clock and installed-cell concentration are separate from static nanosecond timing. A hypothetical clock period is visibly hypothetical. The retained main example failed its 5 ns setup target, so it has no qualified physical execution period.

## Coverage and adding a workload

The present producer supports the XLS source-protocol backend’s exact emitted forms: enabled registers, accepted messages, publications, capture ownership, endpoint framing and its bounded scalar-expression subset. Unsupported expressions, unrepresented state/control histories, external scalar inputs and reencoded native storage remain explicit roots or mapping gaps. Semantic snapshot reads can have unknown consumed subsets even when the entire logical word was recorded. Only evaluated encoded expressions establish exact selected-bit masks. A read result points back to its request, rather than claiming a second physical location.

The native finite storage qualifier currently handles FDRE/FDSE/FDCE/FDPE Q outputs and explicit connected-net associations. The generic schema also represents RAM/SRL resources, but does not imply those primitives were measured. The RAM fixture supplies logical behavior only. Native route rendering uses tile membership and PIPs, not metal-centreline geometry; intra-site and ambiguous endpoint gaps remain visible.

To add a workload, keep stimulus and completion interpretation with that application, prepare its observer from its own compiler outputs, and start with a short finite capture. Add localized adapter checks for any new emitted form or primitive before claiming support. Supply exact build identities at every stage, register capture/native budgets before expensive work, and retain failures. Do not expand the default integration suite just to add a viewer example.
