# Spacetime S1: six-actor repetition case

2026-11-06. **S1 complete.** The first case is the smallest supported whole-device source-protocol repetition application. Fresh source emission and its independent ordinary-BEAM reference succeeded. This registers an executable case; continuous capture, compiled RTL, physical correspondence and the viewer remain unimplemented campaign tasks.

The [campaign evidence index](spacetime-visualization.md) places this completed case in context and points to the sole active task list. The [result and evidence hashes](/Users/ecpeterson/Documents/code/hls_artifacts/runs/spacetime-2026-11-06/case-1/result.json), [original preregistration](/Users/ecpeterson/Documents/code/hls_artifacts/runs/spacetime-2026-11-06/case-1/preregistration.json) and [recorded commands](/Users/ecpeterson/Documents/code/hls_artifacts/runs/spacetime-2026-11-06/case-1/attempt-2/phases.json) live in the separate artifact archive. No primary implementation files changed. No XLS, RTL simulation, native implementation or remote command ran during S1.

## Case and exact source selection

Call `phi_protocol_config:repetition(2, #{})`, then `hls_build:plan/1` with `backend => source_protocol` and `kind => application`. One `board` partition, host 1, contains two data/noise actors, two syndrome actors and two Phi actors: six actors and 14 links in the emitted plan. There is no split placement, inspection or shared arithmetic. East and west remain distinct logical channels even though N2 makes their neighbor the same actor.

| Input | Registered value |
| --- | --- |
| Fabric source | `0ae93e086e70071b1bdc1f7a650a78cc227a8ef1` |
| Compiler and runtime actually built | `38e1f9bf08046e714d5479ffd5112afa00e8ee64`, the paired dependencies pinned by fabric |
| Compiler primary, not used by this case | `d6773db686ec1c132a462cd6e343bf9796606055` |
| Application identity | `ff4a5a31278cfce439ae77f752af97a1ed89a4700d7944e2bc88612f42921cbc` |
| Noise probability cutoff | `0x80000000` for data and measurement noise; this is a half-rate threshold, not a seed |
| Diffusion rounds | 12 |
| Data seeds, X=0/1 | `0x9e3779b9`, `0x3c6ef372` |
| Syndrome seeds, X=0/1 | `0xdaa66d2b`, `0x78dde6e4` |
| Phi seeds, X=0/1 | `0x1715609d`, `0xb54cda56` |
| Frame ABI | 32-bit header plus three 32-bit payload words; 128 bits total |
| Generated schedule | One-stage sampled actor clock, two-stage gateway, XLS unit delay model; this specifies generation, not physical timing |

The [source identity manifest](/Users/ecpeterson/Documents/code/hls_artifacts/runs/spacetime-2026-11-06/case-1/source-identities.json) covers Git-archived snapshots of 1,725 fabric and 643 compiler files, including the shared actor implementation headers. Builds used paired `_checkouts/erl_hls` and `_checkouts/hls_runtime` pointing at the same pinned compiler snapshot. Rebar rewrote the disposable snapshot's `rebar.lock` to `[]` because those are checkout dependencies; the original lock is identified by the source manifest and commit. Every other archived source file remained unchanged. The [post-build check](/Users/ecpeterson/Documents/code/hls_artifacts/runs/spacetime-2026-11-06/case-1/source-postbuild-verification.json) records that sole generated change.

OTP 28.0.2 and rebar3 3.24.0 built the release. Exact release BEAM hashes and tool hashes are retained. The installed optimized Darwin XLS bundle at `/Users/ecpeterson/Documents/code/hls_toolchains/xls-optimized-2026-09-30` is identified and its four executable hashes verified for later work; it was not executed. It is distinct from the repository's Linux CI tool pin. Revalidate the selected tools before S3; record any change as a new build identity.

## Finite input and independent boundary

Reuse the existing ordinary-BEAM fixture `phi_protocol_repetition_fixture:oracle(Stage, 2)` and, later, the public broker loop `phi_protocol_repetition:run(Stream, 2, 8, 123, 60000)`:

1. Apply noise cutoff 8 before activation. The hardware path has an explicit start command; the BEAM reference connects its freshly configured actor graph.
2. Feed every public correction back to its topology-selected data actor as a Pauli update.
3. Wait for distinct statuses from both Phi coordinates at one common logical step, both with flags 2, meaning quiet and empty.
4. Read both data actors with request 123 in X basis, after the host has sent all preceding correction updates.

The fresh [oracle](/Users/ecpeterson/Documents/code/hls_artifacts/runs/spacetime-2026-11-06/case-1/oracle/oracle.json) reached common fence **8**, with **24 public events**, **six corrections**, and readouts **X=0 → 0, X=1 → 0**. Its global list is one BEAM interleaving. The normalized [per-sender reference](/Users/ecpeterson/Documents/code/hls_artifacts/runs/spacetime-2026-11-06/case-1/oracle-by-sender.json) preserves the order that the RTL witness must match, without imposing an accidental cross-sender chronology. This is a finite semantic witness, not a convergence, QEC-validity or hardware-equivalence proof.

Define `C(k)` as the acceptance cycle of the final word of the last required public `phi_status(k, X, 0, Flags)` frame, for X in `{0,1}`. Both coordinate statuses are required. The status follows its actor's movement completion and precedes its next-step request. Thus `C(k) − C(k−1)` is **observed all-coordinate step spacing**, not the latency of an activation and not global quiescence. Host stalls and output arbitration can affect it.

Display **`C(3)..C(4)`**, with logical step 4 selected. The [selection amendment](/Users/ecpeterson/Documents/code/hls_artifacts/runs/spacetime-2026-11-06/case-1/selection-amendment.json) preserves the original step-3 preregistration: inspecting the oracle showed that step 3 has no correction, whereas step 4 sends a correction from Phi coordinate 0 to data coordinate 1. This selects a more informative picture, not a favorable performance result; no inputs changed and no run was repeated. Step-4 statuses are flags 0 at coordinate 0 and flags 1 at coordinate 1.

Capture reset through the quiet fence and completed readout, then select the middle interval for display. Retain earlier ancestry and later consumers. In particular, `C(4)` does not guarantee that its correction feedback has already been consumed; follow that update through host ingress and the destination's eventual consumption, even when this lies below the displayed stack.

## Clock convention and remaining determinism work

The existing Verilator harness has one integer cycle counter, active-high reset at cycles 0–7, ready/valid sampling before the rising edge, then the rising-edge state update. Application output readiness includes `cycle % 19 >= 7` as well as FIFO capacity. It has a four-million-cycle horizon and a 120-second wall limit. It does not specify a meaningful nanosecond period. Cycle counts remain authoritative; measured period is unresolved until an exact native implementation exists. A 5 ns implementation target is not evidence of a 5 ns clock.

The host process delivers FIFO commands according to wall scheduling. Fixed seeds and semantic inputs therefore do **not** fix clock-by-clock delivery. S3 must retain offered-input and output-ready schedules, accepted handshakes, reset boundaries and termination, then demonstrate deterministic replay. The current accepted-word FIFO log alone does not supply all of that. No cycle timestamps, event lineage or replay claim is made by the BEAM oracle.

## Physical inventory and execution bounds

The [inventory](/Users/ecpeterson/Documents/code/hls_artifacts/runs/spacetime-2026-11-06/case-1/physical-inventory.json) found historical N2 RTL under `pr-wave-16/qualification-2`, but no associated usable checkpoint and no established equivalence to this source bundle. Recorded Phi D3/shared checkpoints cover different 54-actor designs; the source-selection design has 43 actors; the N6 multiboard package is a different simulation witness. Local placement mocks and old Zynqberry demo DCPs are also unsuitable. None may supply this case's placement. Recorded remote checkpoints were not contacted or reverified.

The earlier `physical_census.tcl` is a useful exporter starting point: it reads an exact DCP and exports common tile coordinates for every primitive, but net/pin connectivity only for selected near-critical/high-fanout nets. It does not export actual routed geometry, and its old raw all-cell TSV is not retained locally; remote raw availability is unverified. S4 must generalize that coverage and bind it to the exact new implementation; an old aggregate report cannot substitute for a physical catalogue.

The preregistration fixes these ceilings before the corresponding work starts:

| Work | Limit |
| --- | --- |
| S1 source release, emission and oracle | 900 s; serial; 6 GiB aggregate RSS; oracle 20 s; 512 MiB artifacts |
| Future local RTL build | 1,800 s total; 300 s per stage; serial; 6 GiB aggregate RSS |
| Future capture | 4,000,000 cycles; 120 s; 1,000,000 records; 32 MiB packed / 256 MiB decoded |
| Necessary new native implementation | One 10,800 s attempt; Vivado 2024.2; `xczu7ev-ffvc1156-2-e`; OOC BUFG; 5 ns target; Default strategy; rebuilt flattening; two threads; 16 GiB process-group RSS ceiling; stop below 4 GiB host available memory |
| Future read-only physical export | 600 s; two threads; 16 GiB RSS; 2,000,000 records; 64 MiB packed / 256 MiB decoded |

Overflows stop and label evidence incomplete; they must not silently discard interior records. Future guards must enforce these ceilings rather than merely print them. Native launch additionally requires qualified exact RTL, an input manifest, reviewed constraints/report coverage, a fresh host/resource check and a deadline fixed from its own start. No settings sweep, restart or reroute is included. Save available checkpoints and diagnostics on failure. The user reports **EC2 is stopped**; leave it stopped and notify the user when Vivado is needed. These are planning bounds, not a native job started by S1.

S1's successful guarded group exited 0 with no guard and no remaining process. It took **21.56 s**, peaking at **498,040,832 bytes (475 MiB)**. Phase times were release 14.10 s, emission 1.71 s, fixture compilation 0.20 s and oracle 0.16 s; tool/plugin setup was 4.32 s. A prior version query loaded unrelated user-global rebar plugins; it was stopped after 21.59 s before release/emission, its remaining group was subsequently verified gone, and its logs are preserved. The successful attempt used isolated `REBAR_GLOBAL_CONFIG_DIR` and `REBAR_CACHE_DIR`, with the rebar version pinned. Neither primary checkout's global configuration changed.

All 122 files named by `source-build.json` passed their stored hashes; the emitted manifest remains `eligible=false`, `native_measured=false`. Source wrappers exist, but the XLS-generated core is not yet compiled or qualified. The case occupies about 97 MiB including disposable snapshots, release and tool caches. Retain compact manifests, source identities, oracle and reproduction instructions; completed bulky output remains subject to the seven-day policy.

## Entry points and handoff

The archived `run-2.py` and `attempt-2/phases.json` record exact external commands and code paths. Source configuration, lowering and semantic reference execution remain Erlang-owned. To reproduce in a **new** case directory, use the recorded source revisions, paired compiler/runtime checkout dependencies and isolated rebar configuration, then:

```sh
rebar3 release -n hls_examples
_build/default/rel/hls_examples/bin/hls-repetition --width 2 --output FRESH_SOURCE
```

Compile `apps/hls_phi/test/phi_protocol_repetition_fixture.erl` with the resulting release's `lib/*/ebin` directories, then call `phi_protocol_repetition_fixture:oracle(FRESH_ORACLE_DIRECTORY, 2)` in the same release code closure. The stage must exist and its `oracle.json` must not. The exact `erlc`/`erl` argument vectors are in the phase record; do not use an unrelated `_build` profile. Existing artifacts are single-use evidence, not overwrite targets.

The existing full hardware witness entry is `apps/hls_phi/tools/test_protocol_repetition.py XLS_ROOT FRESH_RUN --width 2`, using the pinned Python, matching built profile and a serial guard. It is **not yet a spacetime capture command**. S3 should extend its simulator-source/qualification path to capture events and reuse this registered source bundle/oracle while their identities remain valid, rather than repeating the full successful S1 setup. Bind the actual Verilator executable and compiler when adding capture; no simulator executable was selected or run in S1.

The old read-only export entry is `vivado -mode batch -source physical_census.tcl -tclargs EXACT_DCP FRESH_OUTPUT BAND_NS ENDPOINT_LIMIT`; its sibling Python helper is required. S4 must promote/generalize this entry, enforce the registered output caps and add complete relevant connectivity/timing evidence. Do not execute the old script against an unrelated checkpoint and label its output N2.

**Next: S2.** Define a small saved execution/physical correspondence example and rejecting cases, using this case's actors, feedback boundary and build identities. Continuous observation bindings, cycle-exact replay, exact RTL qualification, a matching DCP, physical mapping and routed period remain explicit gaps. No broader regression suite or native run is needed to close S1.
