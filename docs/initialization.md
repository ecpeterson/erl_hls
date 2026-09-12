# Initialization and reset

Hardware translation accepts one unguarded `init([])` clause. `hls_gs` returns its state record; `hls_statem` ends with `{ok, Phase, Data}`, where `Phase` belongs to `-hls_phases` and `Data` is the declared data record. Prefix bindings and supported pure expressions, including exhaustive `case`/`if`, can compute the values. Argument-dependent initialization, multiple initializer clauses, guards, arbitrary Erlang calls, and other result shapes are outside this translated subset.

XLS evaluates the initializer at compile time. The generated module retains both the computed value and the supported match-failure predicate, then applies a module-level `const_assert!` before either value can become live state. A selected match failure rejects DSLX type checking and IR conversion, including when only a shared service or an unrelated function is selected as the compilation top. A match failure in an unselected branch does not reject initialization. The generated assertion is preceded by the source `init/1` line number; the file preamble identifies its Erlang source.

Initialization uses the same expression lowering and [numeric contract](numeric-contract.md) as callbacks. Compile-time checking does not establish equivalence for arbitrary Erlang arithmetic or exceptions: intermediate widths, overflow, rounding, and supported operator domains still apply. Use type-directed constructors and explicit conversions where a value's width matters.

Every translated record field must have an explicit `hls_type:zero()` default and a supported type. `hls_pack` supplies the corresponding BEAM default, and DSLX supplies the same type's zero. Other defaults, missing defaults, and untyped fields are rejected. Assign nonzero values in the initializer's record construction or update:

```erlang
-record(state, {
    value = hls_type:zero() :: hls_nums:u32()
}).

init([]) ->
    Base = hls_nums:wrap(hls_nums:u32(), 41),
    #state{value = Base + 1}.
```

## Cold start and startup messages

A direct service starts from the checked state. A shared scheduler first writes the checked phase/data and empty scheduler state into every actor RAM slot; it does not rely on RAM power-up contents. State-machine initial entry receives `OldPhase = Phase`, and its data update precedes dispatch of ordinary inputs, including topology startup messages.

Startup messages supply per-instance configuration after this common initializer. A topology target with startup messages must have an initial phase entry that emits no effects. Shared schedulers buffer their configured startup prefix before normal scheduling; those frames still pass through the actor's ordinary callbacks after initial entry. The initializer must therefore produce a usable initial phase and data independently of startup traffic.

The CPU adapters invoke the source `init/1` with the argument passed to `start_link`. CPU-only use can retain argument forms outside the hardware subset. A hardware-backed `hls_gs` proxy requires `[]` and rejects any other argument before registering its fabric route. Starting or restarting a proxy attaches to the existing hardware state; it does not run a remote initializer or reset the device.

## Reset

Hardware reset starts a new execution: direct actor state is restored, scheduler metadata is cleared, shared actor RAM is repopulated, and topology startup producers restart. The physical state and mailbox RAM arrays need not be cleared; initialization and empty-mailbox metadata keep stale contents from becoming live state. The checked initializer is a constant, so reset repeats its value rather than executing host code.

Reset must cover the actor's surrounding topology and transport control. An interrupted frame, pending reply, or debug query cannot be continued across that boundary. Establish a new host session after an interrupted transaction; see the [transport reset contract](debug-protocol.md). Resetting one actor independently of peers and in-flight traffic is not a supported recovery protocol.

Run `bash tools/test_initialization.sh XLS_ROOT [STAGE]` for the regression. It compares public BEAM replies with DSLX/JIT values and generated RTL at two schedules per fixture: one/two stages for direct services, two/three for shared RAM-backed services. The RTL tests cover nonzero state, zero defaults, a nonfirst initial phase, silent initial-entry updates, per-instance topology startup, mutations, output stalls, reset during RAM initialization, and reset after a reply becomes pending. The shared fixture uses production RAMs without a reset input. Negative fixtures require a supported failing initializer to be rejected by both BEAM and XLS.

CI also blocks the shared fixture's output and queries FIFO depths through the production debug endpoint. It checks that wait inspection reaches the external sink and observes recovery after release, while instrumentation preserves application outputs cycle by cycle:

```sh
python3 tools/test_topology_debug_integration.py \
  --top init_shared_wrapper --stage _build/initialization/debug \
  _build/initialization/init_shared_2.v \
  _build/initialization/init_shared_wrapper.v priv/rtl/hls_1r1w_ram.v
```
