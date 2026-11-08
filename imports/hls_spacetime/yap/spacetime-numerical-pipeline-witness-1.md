# Numerical-only Phi pipeline: prediction versus RTL

The isolated RTL variant measures **106 clocks** for the saved step, versus 99 in the original witness and the unchanged model scenarios of 99 and 109. The model correctly predicts the arithmetic recurrence, but not the final completion clock. This is one finite calibration case, not validation of either scenario as a bound.

## Controlled intervention

Both Phi owners register the two signed 36-bit diffusion numerators. The following edge performs rounding, anyon injection and saturation, then registers the complete private action; the existing entry/publication stage still commits it. Each owner adds 72 intermediate bits and one busy bit in the emitted RTL, retains one outstanding action and holds its committed machine during the new stage. Ordinary receipt and nonnumerical action paths retain their intrinsic latency. This is a real arithmetic boundary, not an idle clock after computing the result.

The experiment copies the exact generated sources and reuses the original compiler settings and application gateway. A diagnostic enable remains false through C1774 and true from C1775, preserving the model's original prefix. Its disabled path deliberately retains the old combinational arithmetic; this diagnostic design is not a physical timing candidate. A physical trial would remove that switch and qualify the constant-enabled design separately.

The driver reuses the recorded input release floors and absolute output-ready schedule, holds inputs until accepted, and waits for the corresponding correction or readout fence before returning host feedback. It preserves each recorded host response gap. No baseline RTL or native implementation job was rerun. Predictions and per-event schedules were saved before observing the candidate.

## Comparison

| Case                          | Step clocks | Change from baseline |
| ----------------------------- | ----------: | -------------------: |
| Retained baseline             |          99 |                    0 |
| Model: absorb recorded gaps   |          99 |                    0 |
| Model: preserve recorded gaps |         109 |                  +10 |
| New RTL witness               |     **106** |               **+7** |

The previous completion remains C1774; the changed completion is C1880. The three public anchors move from C1852/C1860/C1873 to C1857/C1872/C1880. Thus actual-minus-predicted error is +7 clocks for gap absorption and −3 for gap preservation.

Both scenarios correctly predict the private-result and commit clocks for all 20 remaining diffusion computations, epochs 50–59 across the two actors. Gap preservation also predicts all six ordinary actions and their commits in the selected source sequence. Its six remaining internal timestamp mismatches concern three numerical actions from the following diffusion episode, already overlapping publication of the selected step. Those action identities and values still agree.

The public trace explains the seven-clock completion change directly. The first correction becomes valid 12 clocks later, C1841→C1853. From that point through step completion, both designs transmit 15 words and spend six clocks without a valid word. The original encounters 12 valid-but-not-ready clocks; the variant encounters seven. Consequently `12 − 5 = 7` extra completion clocks. The model preserves or absorbs recorded gaps but does not replay the absolute ready-window phase. This accounting does not attribute its entire three-clock error to one particular omitted dependency.

The response to that correction remains two clocks after its accepted final word: the feedback's first beat moves C1854→C1859 and its last C1860→C1865, with zero input stalls. Owner receipt timing and outbox blocking also change; preserving every old gap is not a simulation of those controls.

## Functional and structural qualification

The diagnostic prefix has zero differences across all public pins and 88,750 comparisons of bound owner fields/control samples. Fresh source/IR mappings locate four actual 36-bit numerator registers feeding the private results, plus two busy registers. All 141 pipelined actions observed after the intervention have the intended added edge and correct intermediate/result arithmetic; no owner invariants failed. All 58 action/commit groups required by the selected comparison have full-value correspondence. Across the capture, 307 common private actions and 873 common committed writes agree in order and value.

All 70 accepted input words and 153 output words match their retained sequences; output comparison preserves order per logical sender. The canonical fence-8 witness retains 24 events, six corrections and the two zero-valued readouts. Three owner tests cover latency, reset cancellation, blocked entry and ordinary receipts; a rounding/saturation edge test and 1,000 arbitrary-bit-vector arithmetic comparisons also pass using XLS IR-JIT.

The original strict full-trace comparison is retained as failed on unequal suffix lengths. Different termination clocks leave different amounts of source step 10 in flight while step-9 publications drain. Its two unmatched actions and six unmatched committed writes all belong to step 10; none belongs to the selected step or the canonical fence-8 result. The first conservative tail assessment also remains retained. The final assessment qualifies the selected interval, common transaction values and public witness; it does not assert equal live terminal state or completion of that unobserved next step.

The first test attempt hit the XLS bytecode interpreter's existing signed-aggregate flattening limitation; IR-JIT executes the tests successfully. A C++ harness parenthesis error was fixed before any simulation ran. Both failures remain retained. The single successful RTL witness took 2.07 seconds including its wrapper, peak sampled process-group RSS 34.3 MB. All substantial jobs ran serially under the 6 GiB guard and ended without remaining processes.

## Consequence for the model

The numerical recurrence model earns limited confidence from this case. The public completion predictor still needs explicit ready/credit availability and host-response scheduling before it can provide point estimates. The two gap policies remain sensitivity scenarios, not validated lower/upper bounds. Do not tune them to 106 after seeing this result.

The short selected interval also hides ongoing cost: from the same C1774 boundary through the quiet step-8 fence, the baseline takes 498 clocks and the variant 562, a 12.9% increase. Final readout is 61 clocks later. The selected interval alone requires a period ratio below `99/106 ≈ 0.9340` to improve time; the longer five-interval observation requires below `498/562 ≈ 0.8861`. Neither is an achieved period or a steady-state throughput estimate. No Vivado run or physical speedup is claimed.

## Retained reproduction

Artifacts: `/Users/ecpeterson/Documents/code/hls_artifacts/runs/spacetime-2026-11-08/numerical-pipeline-witness-1/`. `preregistration.json` and `preregistered-event-schedule-2.json` preserve the predictions. `reproduction.tar.gz` and `candidate.patch` retain the complete isolated source/RTL, harness and analysis tooling. `witness-1/` retains the new capture and per-frame timing; `comparison-1.json`, `closure-1.json` and `final-review.json` preserve the distinct comparison scopes. All 174 original compiled files remain hash-identical. The original capture, physical database and reviewed prediction profile remain separate inputs.
