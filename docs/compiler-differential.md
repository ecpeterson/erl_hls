# Differential compiler checks

`tools/compiler_differential.py` generates bounded Erlang functions and compares their successful values and failure kinds across BEAM, the DSLX interpreter, and the XLS JIT. Every successful batch also converts and optimizes serialized IR. Selected batches generate combinational RTL and compare it with the same BEAM results in Icarus Verilog.

The reference is the compiled Erlang program, executed in a fresh Erlang VM for each batch. Python generates source syntax; it does not implement a second arithmetic interpreter. Integer operations explicitly use `hls_nums:wrap/2` so intermediate precision follows the [numeric contract](numeric-contract.md). The current grammar covers signed/unsigned 8- and 32-bit words, arithmetic and comparisons, shifts with independently signed/unsigned byte counts, short-circuit Boolean expressions, partial cases, guard alternatives, local and joined bindings, tuple/literal matches, record construction/projection, typed helpers, and checked vector accesses and slices. Shift counts are normalized separately to keep BEAM intermediates bounded, and their results are wrapped before subsequent operations. Half the generated programs use a subset constructed to succeed; the rest can fail. Guard arithmetic failures still cause guard fallthrough in both groups.

The comparison reports the first failure kind and ignores the value after failure. It does not compare BEAM exception payloads or source-site numbers. These are function-level probes: actor effects, schedules, transport backpressure, physical timing, and debug protocols have separate integration tests. The syntax counts in `campaign.json` describe generated expressions, not measured compiler branch coverage. `outcomes` in each batch result counts BEAM successes (`0`) and failure kinds.

## Running a campaign

Put Erlang, rebar3, Python 3.11+, and (for RTL) `iverilog`/`vvp` on `PATH`. Supply an XLS directory containing `interpreter_main`, `ir_converter_main`, `opt_main`, `codegen_main`, and `xls/dslx/stdlib`.

```sh
python3 tools/compiler_differential.py XLS_ROOT --stage _build/differential-smoke \
  --seed 20260915 --count 16 --depth 3 --inputs 20 --rtl-batches 2

python3 tools/compiler_differential.py XLS_ROOT --stage _build/differential-long \
  --seed 20260917 --count 256 --depth 5 --inputs 32 --rtl-batches 2
```

A stage must be fresh. Seeds and case IDs determine programs independently of batch size and generation order. `--start` selects a later range of case IDs. `--batch-size` controls how many functions share a compiler invocation; the default is eight. `--rtl-batches` selects the first batches for RTL, while all batches receive interpreter/JIT and serialized-IR checks. `--skip-compile` reuses an already compiled test build; omit it after changing Erlang code.

Every external command has a timeout (`--timeout`, default 90 seconds; initial rebar compilation allows 180 seconds). Timed-out tools and their process groups are stopped. A campaign stops at its first failure. It distinguishes invalid generated Erlang, lowering errors, tool errors/timeouts, semantic mismatches, and missing test execution. Infrastructure failures are not automatically minimized. Increasing depth can sharply increase compiler time even when the input count is small.

## Replaying and shrinking

A failing batch retains `cases.json`, generated Erlang and DSLX, the BEAM oracle, any generated IR/RTL, command arguments, stdout/stderr, and timing. `provenance.json` records the Git commit and hashes of the runner, Erlang build, DSLX libraries/stdlib, and XLS tools. `summary.json` reports the batches actually attempted; unattempted programs are not counted as tested.

For eligible failures, minimization first isolates one program, then reduces its inputs and syntax while preserving the failure phase/category and, for Erlang lowering exceptions, the reason and top stack location. Reductions preserve expression type and binding scope and strictly decrease syntax cost. This fingerprint helps retain the same failure but cannot prove that every candidate has the same root cause; inspect the final witness. The default budget is 120 tool attempts; `--shrink-budget 0` disables shrinking.

```sh
python3 tools/compiler_differential.py XLS_ROOT --stage _build/differential-replay \
  --replay _build/differential-long/minimized.json --rtl-batches 1 --shrink-budget 0
```

`minimized.json` contains complete programs and inputs and can be replayed without regenerating its original seed. `shrink.json` records accepted/rejected attempts and budget exhaustion. Preserve a useful witness as a small regression fixture when fixing the compiler.

The runner itself has fast tests and an end-to-end fault-injection check. The latter deliberately changes a generated literal, requires a BEAM/DSLX disagreement, shrinks it, and verifies that the uncorrupted witness agrees through RTL:

```sh
python3 tools/test_compiler_differential.py
python3 tools/test_compiler_differential.py --xls-root XLS_ROOT \
  --stage _build/differential-self-test
```

## Actor transition sequences

`tools/actor_differential.py` generates small two-phase `hls_statem` actors and compares finite transition sequences against their normally lowered XLS owners. Its oracle runs the actual compiled actor in the BEAM `hls_statem` runtime. It compares committed phase/data, postponed-message counts and the complete ordered output sequence after each drained input prefix. The source varies unsigned byte arithmetic, initial state, entry updates, conditional effect counts and output-port order. Schedules cover postponement followed by a phase change, same-phase updates, `repeat_phase`, selected and unselected failure, partial entry backpressure, absorbing hardware failure, and fresh incarnations.

The RTL testbench carries the complete generated `Machine` value between calls to the generated `machine_step`; it does not reproduce the mailbox, selection, effect or commit implementation. A small appended DSLX function frames inputs with the generated codecs and exposes observations. Each segment has 64 owner transitions, with an independently chosen output-readiness calendar for the first 16 and readiness thereafter. Healthy segments must accept every offered input and drain all eligible work; an incomplete tail is a failed qualification, not equality. Outputs while blocked and movement after latched failure also reject the trace. All CPU output ports target the oracle process, retaining source ordering; generated payload markers identify the intended ports independently of the RTL egress selector.

These are finite simulation witnesses for the generated owner, not proofs or full streaming-service/transport tests. BEAM does not simulate ready/valid clocks: comparison uses drained prefixes and ordered effects, not cycle-by-cycle equality with BEAM. The RTL may take several transitions to execute one CPU callback. CPU callback failure terminates the process; its `terminate/3` hook reports the preceding committed state, which is compared with the hardware's latched failure. Reset occurs only at segment boundaries after quiescence or failure, replacing the CPU process and resetting the RTL owner. Mid-flight reset, replay/retry delivery, links and physical timing are outside this check.

```sh
python3 tools/actor_differential.py XLS_ROOT --stage _build/actor-smoke \
  --seed 20261109 --count 4
python3 tools/actor_differential.py XLS_ROOT --stage _build/actor-replay \
  --replay _build/actor-smoke/minimized.json --shrink-budget 0
python3 tools/test_actor_differential.py
python3 tools/test_actor_differential.py --xls-root XLS_ROOT \
  --stage _build/actor-detector-self-test
```

The same prerequisites, fresh-stage requirement, tool timeouts and provenance retention apply. Every actor crosses serialized XLS IR, optimization and generated RTL; no large application workload is required. `--skip-compile` reuses a current test build. The optional detector self-test changes an arithmetic literal only in generated DSLX, requires an RTL/BEAM disagreement, shrinks the schedule and replays it without the corruption.

Actor minimization removes segments and commands, then reduces input values and readiness calendars while retaining exact actor source and the fixed horizon. It preserves the mismatch phase, category and observable, with a default budget of 20 tool attempts; changing the observable or exhausting the drain horizon does not count as preserving the original mismatch. The final witness still requires inspection because a common observable is not a proof of common root cause. `case.json`, `minimized.json`, `shrink.json`, source, oracle observations, complete RTL trace and command logs make failures reproducible without the original seed.
