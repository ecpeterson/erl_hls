# Conditional latency scenarios

The **What-if: added actor latency** panel tests a proposed extra result stage against a saved execution. It joins two questions: how much the recorded completion would move under stated scheduling assumptions, and which mapped physical paths the proposed change does not target. It does not run a simulator, compiler or implementation tool.

Load the optional source profile, choose an intervention, set extra clocks per action and the two assumed implementation periods, then press **Run conditional scenario**. The calculation uses the saved step's previous-completion boundary and every accepted public output in that interval. Camera, actor, function and window filters do not change its scope. Changing an input invalidates the displayed prediction. Loading another recording clears the profile and results.

## What the model computes

Each recorded event keeps its original clock as a release floor. For event `v`, the solver computes `T(v) = max(recorded(v), max(T(u) + lag(u,v))) + added_latency(v)`. Only explicitly supplied semantic constraints provide a minimum lag. A long residence or unexplained gap is not automatically service time or spare capacity.

Related output writes are collapsed into one simultaneous completion group. Adding one clock to an action delays the group once, including its source-qualified commit/retirement obligations; it does not charge every output independently. Repeated invocations incur repeated latency and propagate through feedback. Interventions apply in `(previousCompletion, completion]`; carry-in work retains its recorded timing.

The adapter preserves stored version availability, old-value reads before replacement, accepted port order, and exact declared request-to-response latency. Same-edge broadcast reads remain parallel. Passive holds create no work. Explicit source obligations account for lifecycle relationships missing from scalar operand ancestry, such as a pending result enabling the next commit and retirement enabling the next dispatch. Numerical values and branches remain fixed to the recording.

Two policies expose sensitivity to unexplained time:

- **Gap absorption:** release floors allow a delay to fit in an existing interval, subject to the declared dependencies and order constraints.
- **Gap preservation:** every recorded dependency gap is retained as an additional modelling constraint, so those intervals move with their prerequisites.

These are scenarios, not rigorous best/worst bounds on a changed implementation. In particular, new contention, different branch decisions, unobserved dependencies or a different ordering can invalidate either. Unknown-origin and carry-in version roots are counted in the selected completion ancestry. A graph cycle, contradictory latency or reset crossing prevents a usable score; capture-tail crossing censors it.

The period comparison multiplies clock count by the explicitly assumed period once. Break-even candidate period is `baseline_clocks × baseline_period / candidate_clocks`. A static path delay is not an extra term in that calculation. The default periods are illustrative hypotheses, not measured frequencies of the supplied recording.

## Physical constraints

The physical comparison enumerates all recorded mapped D/control targets in the prepared attachment, independently of display filters. It separates resources targeted by the intervention from the remaining targets, shows the largest known envelopes and counts bounds above the assumed candidate period. Unknown and unmapped write bits remain visible in coverage; no global clock forecast is produced.

A target outside the declared change can still move when the design is placed again. Conversely, targeting a resource does not prove every path to it has been shortened. Independent SDF envelopes omit clock-to-Q, setup, clock constraints and the costs of new registers/routing. A selected register cut remains a single-sink, retained-routing estimate; it is not automatically a cut for all coupled outputs or a prediction of the next implementation.

This makes the tool useful for rejecting a narrow proposal which leaves another comparable bottleneck untouched, and for setting a quantitative period-improvement requirement before implementing a candidate. Actual cycle count, output behavior, device fit and routed timing must subsequently be checked on the modified design.

## Source profile boundary

Profiles are data, never executable modules. A profile binds the exact recording byte count/SHA-256 and source/RTL/observation build identities. It contains:

- `evidence`: reviewed source/observation paths, hashes and descriptions;
- `groups`: unique simultaneous event members, a trigger and source-based classification;
- `edges`: extra source/target lifecycle obligations with minimum clock separation and a reason;
- `choices`: named sets of groups to delay;
- `unknowns`: unresolved aspects of the interpretation.

The profile author must justify completeness of the coupled outputs and lifecycle edges. Matching hashes establishes identity, not correctness of that interpretation. A functionally different application needs its own source analysis; event names and physical proximity do not establish ownership. The supplied Phi case keeps source classifications and missing control-event coverage explicit rather than silently generalizing to other actor encodings.

The optional `latencyProfile` entry in `web/data/index.json` has the same `{file,bytes,sha256}` descriptor shape as other prepared attachments. Profiles are loaded only on request, limited to 4 MiB and rejected if their hash, recording binding, groups or edges disagree. Bulk case artifacts remain outside Git.

For offline use, `scripts/predict-latency.mjs` accepts `--recording FILE --profile FILE --output NEWFILE --choice ID --extra-latency N --baseline-period NS --candidate-period NS --saved-step`. Alternatively supply `--start-cycle N --targets ID,ID`. Repeated scalar options use the last value. Output creation is exclusive. The pure modules are `latency-scenario.js` (constraint solver), `recorded-scenario.js` (recording/profile adapter) and `scenario-physical.js` (physical census).

## Validation

Small synthetic fixtures compare the solver with an independent clock-by-clock oracle and cover repeated feedback, gap absorption, reconvergence, simultaneous outputs, old-version reads, exact memory latency, port broadcasts, reset, capture tail and wrong recording bindings. Tests distinguish the full physical population from filtered display layers and retain unrelated timing constraints. These are checks of the model, not validation of a proposed pipeline implementation.

## Clocked control replay

The gap-based panel above remains a sensitivity calculation. For a source-reviewed control profile, `scripts/replay-control.mjs` predicts clocks by advancing explicit owners, queues and handshakes instead. It does not use historical internal event clocks as scheduling floors. The current adapter covers the finite, failure-free, post-attachment source-protocol case; it is not an interpreter for arbitrary generated RTL.

```sh
node scripts/replay-control.mjs --profile control-profile.json \
  --output new-prediction.json --actors 2,3 --extra-latency 1
```

The result includes the zero-intervention baseline and changed schedule, individual operation/transfer clocks, accepted input/output words, completion targets and unresolved waits. `--targets ID,ID` selects explicit future public frames; `--end-cycle N` bounds replay. Repeated scalar options use the last value, and output creation is exclusive. No implementation-period assumption is required or inferred. Profiles are bounded JSON data, never executable plugins.

The source profile supplies fixed operation results and branch decisions, the identities of input messages and effect deliveries, exact carry-in ownership, and the host's stimulus policy. The model recomputes:

- Private-result latency and the separate commit edge, with one outstanding action per actor.
- Outbox admission and independent per-recipient publication, retaining an occupied buffer until its old contents are accepted.
- Sender-local capture ownership, consumption, registered credit return, per-sender ordering, round-robin selection and postponement until a phase boundary.
- Held endpoint grants, the gateway's one-stream-per-idle-clock polling, packet serialization and absolute ready windows.
- Causal host feedback from accepted public frames, including original exogenous word floors and multi-frame readout fences.

All components observe the same old state before committing an edge. A credit released now cannot be spent now; a captured message becomes visible next edge. An actor's actual selected message must match the fixed work script. A different message order is rejected, not delayed until the expected message appears. Reset, missing work, unresolved branches and incomplete effects stop the prediction with explicit diagnostics. The supported entry checkpoint has an idle, attached transmitter and no pending management/start transaction; a profile must not erase an in-flight packet to satisfy that restriction.

`clocked-owner.js`, `clocked-resources.js`, `clocked-transport.js` and `clocked-host.js` contain the isolated transition rules; `control-replay.js` connects them. Producer interpretation and capture comparisons remain separate from this scheduling engine. Source hashes establish input identity, not correctness of the interpretation. In particular, narrowed machine values remain opaque; the profile must justify any control decisions derived from them.

The retained numerical-pipeline comparison now reproduces both the 99-clock baseline and 106-clock changed step, followed by every observed completion through step 9 and readout. The five-step interval is 498→562 clocks, also reproduced. These are retrospective checks against known captures, with fixed work and source-reviewed controls; a new workload or a change that alters values, branches, scheduling policy or physical timing requires new qualification. The original 99/109 gap scenarios remain retained. See [the control-replay record](../yap/spacetime-control-replay-1.md) for exact coverage and limitations.
