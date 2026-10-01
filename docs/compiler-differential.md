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
