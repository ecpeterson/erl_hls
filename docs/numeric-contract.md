# Numeric values, conversion, and arithmetic

The host representation and the wire representation have different jobs. ERTS keeps integers as arbitrary-precision integers and floating-point values as binary64 floats. A wire descriptor chooses a finite representation. We keep those ordinary ERTS values and make conversion boundaries explicit rather than introduce a separate live representation for every width.

## The codec laws

For a descriptor `T`, let `P_T` be `hls_type:pack(Value, T)` and let `U_T` unpack exactly that payload, omitting the empty remainder. Define `Q_T = U_T ∘ P_T`. Every successful pack must satisfy:

```text
U_T(P_T(Value)) is defined and consumes the complete payload.
Q_T(Q_T(Value)) =:= Q_T(Value)
P_T(Q_T(Value)) =:= P_T(Value)
```

Successful packing also returns a binary whose bit width equals `hls_type:width(T)`. Custom providers must obey the same laws; `hls_type:pack/2` checks binary shape and width, while provider implementations and tests establish the normalization laws. It does not invoke arbitrary providers twice on every ordinary pack.

The laws permit normalization, but do not specify which normalization is appropriate. Wrapping, rounding, and saturation can all be idempotent; even returning a constant could satisfy idempotence. The descriptor's documented policy supplies the missing meaning:

| Type | Accepted packing policy | Explicit alternatives |
| --- | --- | --- |
| `hls_nums:u8/u16/u32/u64/uN` | Preserve integers in the unsigned range; reject overflow and negative values. | `hls_nums:wrap(T, Value)` reduces modulo `2^Width`. |
| `hls_nums:s8/s16/s32/s64` | Preserve integers in the signed range; reject overflow. | `hls_nums:wrap(T, Value)` reduces modulo `2^Width`, then interprets the sign bit. |
| `hls_fixed:signed(Width, FractionBits)` | Preserve in-range raw scaled integers; reject overflow. | `hls_fixed:wrap/2` wraps the raw integer; `saturate/2` clamps it. Neither changes the fractional scale. |
| `hls_nums:float16/float32` | Round to IEEE binary16/binary32, including ties to even and gradual underflow; reject results that encode infinity. | `hls_type:normalize/2` exposes the rounded host value; `pack_exact/2` rejects any change to the original term. |
| `hls_nums:float64` | Preserve finite binary64 floats, including signed zero and subnormals. Integer inputs undergo ERTS's integer-to-binary64 conversion. | `pack_exact/2` rejects integer-to-float coercion as well as any other term change. |

All float codecs continue to accept integer inputs through the VM's binary64 conversion before encoding. This can lose integer precision before narrowing, and excessively large integers are rejected. For example, normalizing `(1 bsl 53) + 1` as `float64` produces `9007199254740992.0`. Use `pack_exact/2` when coercion is unwanted. Bignum storage itself is never a reason to reject an integer: an in-range `u64` or `uN(96)` value remains valid regardless of how ERTS stores it.

Fixed-size lists and vectors require exact lengths, and generated record packers require the declared record tag and arity. Numeric normalization does not permit deleting, adding, or padding fields or elements. Nested providers are checked individually, so one short element cannot be compensated by an oversized neighbor.

## Checked collection access

`hls_lists:nth/2`, `hls_lists:set/3`, and their `hls_vec` counterparts use one-based indices in `1..Size`. Invalid indices raise `badarg` on BEAM and produce a source-located `badarg` failure in XLS. Reads do not clamp to the last element, and updates do not silently ignore an invalid index.

`hls_lists:array_slice(Descriptor, Values, Start, Length)` returns exactly `Length` elements. Its length must be a positive compile-time constant for XLS; its start may be dynamic. `hls_lists:sublist(Descriptor, Values, Start, Count)` permits a dynamic count and appends zero elements after the selected range to retain the descriptor's full size. Both require `Values` to have the declared type/size, `1 =< Start =< Size + 1`, and `0 =< Count =< Size + 1 - Start`. A zero-count range may start just past the end; a nonempty overrun fails instead of truncating or padding missing input. Empty collections and zero-length `array_slice` results remain supported on BEAM, but their XLS translation reports `empty_xls_collection`: XLS's IR does not support empty array values. A zero-count `sublist` of a nonempty collection is supported on both targets because its result retains the original size.

The static [`hls_lists.x`](../priv/xls/lib/hls_lists.x) implementation accepts signed or unsigned indices and counts at their inferred integer widths, including values wider than 32 bits. It checks bounds before narrowing an index for the array primitive. Negative or oversized values cannot become valid by truncation. As with other arithmetic, an index expression may already have wrapped before reaching this API; widen its operands or use an overflow-free expression when mathematical bounds are intended. For example, after checking `0 < Count =< Size`, compare `Start =< Size - Count` for a zero-based range instead of adding `Start + Count` in a narrow type. `regsvc` uses this form for bulk reads.

The existing failure carrier preserves the first selected error, suppresses failed results/effects, and rejects a failing constant initializer. Unselected branches remain harmless. GS proxies decode the new reason as `{error, {remote_error, badarg}}`; shared-actor debug queries retain the source file and line, including calls inside included helpers. This adds no new recovery or exception-catching mechanism. Checks for constant in-range accesses can be eliminated during XLS optimization; dynamic checks can add comparison and selection logic.

`bash tools/test_collections.sh XLS_ROOT` compares lowered Erlang calls with BEAM, the DSLX interpreter/JIT, and optimized RTL. It exhausts all eight-bit start/count pairs for signed and unsigned indices and samples 32/64-bit boundaries, including values that would truncate to a valid 32-bit index. Existing control-failure and actor-debug regressions cover selected/skipped failures, first-error order, invalid initializers, stalled replies, and public source-location queries. The float collection regressions exercise structured and nested elements.

## Using explicit conversions

```erlang
Half = hls_nums:float16(),
Rounded = hls_type:normalize(Half, 0.1), % 0.0999755859375, still a BEAM float
Bytes = hls_type:pack(Rounded, Half),
Bytes = hls_type:pack(0.1, Half),
Bytes = hls_type:pack_exact(Rounded, Half).
% hls_type:pack_exact(0.1, Half) raises {inexact_packing, Half}.
```

`normalize(T, Value)` implements `Q_T` and works through composed types, including lists and vectors. `pack_exact(Value, T)` compares the unpacked value to the original Erlang term with exact equality; it rejects `1` becoming `1.0`, even though those are numerically equal. Both are host-only APIs. Translation reports a `host_only_type_operation` error rather than pretending that a DSLX cast supplies the same checks.

```erlang
Word = hls_nums:u8(),
0 = hls_nums:wrap(Word, 256),
255 = hls_nums:wrap(Word, -1),
-128 = hls_nums:wrap(hls_nums:s8(), 128),
<<0>> = hls_type:pack(hls_nums:wrap(Word, 256), Word).
% hls_type:pack(256, Word) raises badarg.

Fixed = hls_fixed:signed(16, 8),
256 = hls_fixed:wrap(Fixed, 65536 + 256), % 1.0 in this format
32767 = hls_fixed:saturate(Fixed, 32768),
-32768 = hls_fixed:wrap(Fixed, 32768).
```

Both numeric `wrap/2` operations translate to XLS integer casts. Literal arguments are normalized before emitting a typed constant. For computed arguments, the source expression must already have enough width to represent the intended intermediate value: wrapping an expression cannot recover bits lost while evaluating it. `hls_type:as/2` remains a host identity/type ascription, so it must not be used to request wrapping on ERTS.

Packing an invalid integer, malformed collection, or overflowing float raises `badarg`. Provider binary contract violations identify the descriptor and, for width mismatches, expected and actual widths. Nonfinite wire encodings are outside the float codecs' accepted domain and fail to match during unpacking. Existing process-level exception behavior remains in effect; these APIs do not add a recovery protocol for a failed hardware proxy.

## Finite floats and exceptional encodings

Binary16 encoding rounds directly from binary64 bits, and decoding reconstructs the exact binary64 value. This small wire codec avoids OTP 28.0.2's fallback conversion defects, which the Linux CI exposed: decoding and repacking the subnormal pattern `0x0002` produced `0x0001`, and a binary64 value just above a binary16 rounding tie could round down. The native half-float path on Apple Silicon passed those same tests. Binary32/binary64 continue to use the VM codecs. The wire codec is independent of the explicit arithmetic operations below; both use ordinary BEAM floats as live values.

[ERTS uses binary64 live floats and does not support live infinity or NaN](https://www.erlang.org/docs/28/system/data_types.html#float). Its bit syntax can nevertheless produce narrow infinity when a finite input overflows: encoding `65520.0` as binary16 produces the infinity pattern. The codecs reject that result so a successful pack is always decodable.

Rounding to the largest finite value remains valid: binary16 packing accepts `65519.0` and normalizes it to `65504.0`. Underflow to signed zero is also valid. Both signed zeros and finite subnormals retain their wire bits. Applications that require exact values can select `pack_exact/2`; applications that require infinity/NaN payloads need an explicit bit-level representation instead of an ERTS float.

## Arithmetic is a separate contract

The codec laws do not imply that arbitrary ERTS and XLS computations agree. For addition, subtraction, and multiplication at a common modular integer width, reducing arbitrary-precision intermediates at the end gives the same residue as reducing after each operation. This follows from the ring homomorphism from integers to integers modulo `2^Width`.

Division, comparisons, and right shifts generally do not preserve that equivalence. With `X = 255`, `(X + 1) div 2` produces `128` on ERTS and `0` with `u8` intermediate arithmetic. Both the original input and the ERTS result fit `u8`, so even checked boundary packing cannot detect the disagreement. Applying `wrap(Word, X + 1)` before division explicitly selects the modular intermediate on ERTS too.

Floating-point rounding also depends on its schedule. Binary64 evaluation of `(16777216.0 + 1.0) - 16777216.0` produces `1.0`. Binary32 addition followed by binary32 subtraction produces `0.0`. All inputs are exactly representable in binary32. Rounding each operation therefore differs from rounding only the final output. Cancellation can magnify small local discrepancies, and a comparison can turn them into different actor messages.

XLS's [floating-point add/subtract and multiply](https://google.github.io/xls/floating_point/#apfloataddsub) also flush subnormal inputs and outputs to zero and do not report exception flags. That differs from the finite subnormal encodings supported by our codecs. Selecting `float64` does not by itself eliminate this difference. Nor is evaluating every operation in binary64 and then narrowing a universal exact emulator: double rounding and operations such as fused multiply-add need their own treatment.

### Integer division and remainder

Translated `div` truncates toward zero, and `rem` has the dividend's sign (or is zero). Operands must have the same XLS integer width and signedness; literals can take that type from context. A zero divisor produces a source-located `badarith` failure. The existing failure carrier suppresses the failed callback's result, retains the first selected failure, and rejects failed constant initializers. Unselected branches do not fail. In guards, the error rejects the current guard sequence and allows later semicolon alternatives or clauses; see [control flow](control-flow.md).

For nonzero divisors and representable quotients, these operations agree with Erlang on the same input integers. The signed minimum divided by `-1` is the one quotient overflow: XLS wraps to the signed minimum, while BEAM returns the positive bignum/integer. This is fixed-width overflow, not `badarith`. Use `hls_nums:wrap(Type, X div Y)` when the modular result is intended on both targets, or widen **both operands before division** when the mathematical quotient is needed. For example, `-128 div -1` becomes `-128` at `s8` width and `128` at `s16` width; its remainder is zero at both widths. Wrapping after a quotient cannot recover the wider mathematical result.

Signed `rem` uses the static [`hls_integer.x`](../priv/xls/lib/hls_integer.x) helper. It changes a signed divisor of `-1` to `+1`, preserving the zero remainder while preventing the signed-minimum remainder from reaching LLVM's overflowing `srem` operation in XLS's x86 JIT. Unsigned divisors are unchanged. This adds a signed-divisor test and selection; it does not change the arithmetic contract. [`xls_srem_overflow_repro.x`](../test_data/xls_srem_overflow_repro.x) retains the raw upstream case for checking a future XLS release.

The same intermediate-width rules apply inside guards. A comparison after an overflowing quotient can select a different clause on BEAM and XLS; matching boundary codecs alone does not prevent that. Neither this failure check nor a type annotation turns BEAM's ordinary arithmetic into a fixed-width evaluator.

Variable division and remainder can synthesize substantial combinational logic. A dynamic divisor adds a zero test to the existing failure carrier; a literal nonzero divisor needs no such test. There is no new history buffer or division-specific actor-state field; XLS may pipeline the checking logic. A guard's divider still exists in hardware even if selection prevents its result from being observed. Choose constant divisors, narrower operands, or application-specific algorithms when area or timing matters; no general area or timing bound is implied here.

### Integer shifts

`bsl` and `bsr` accept independently typed integer values and counts. A negative count reverses direction: `X bsl -N` shifts right, and `X bsr -N` shifts left. Right shifts sign-extend a signed value and zero-extend an unsigned value. Counts retain their full width, including the most negative signed count; they are never reduced modulo the value width or truncated to 32 bits.

The result keeps the shifted value's width and signedness. A left shift discards bits beyond that width. At or beyond the value width, a left shift returns zero; a right shift returns zero for a nonnegative value and `-1` for a negative signed value. To make BEAM observe the same modular result before a comparison, division, or subsequent right shift, wrap the intermediate explicitly:

```erlang
Value = hls_type:as(hls_nums:s8(), -64),
Count = hls_type:as(hls_nums:s16(), 2),
Shifted = hls_nums:wrap(hls_nums:s8(), Value bsl Count),
true = Shifted =:= 0.
```

The value must have its intended type **before** shifting. In particular, use `hls_type:as(hls_nums:u32(), 1) bsl Count` for a 32-bit bit mask. Casting the result afterwards cannot recover bits lost from a narrower operand. A direct untyped literal shifted by a runtime count is rejected with `untyped_shift_value`; give named literals explicit types too. When both operands are integer literals, the compiler evaluates the expression as an Erlang constant, allowing `hls_nums:wrap(hls_nums:u8(), 1 bsl 8)` to normalize to zero. Signed integer literals are accepted in guards as well as bodies.

Shifts on typed values use the static `hls_integer::shift` helper, including literal overshifts that DSLX's primitive constexpr-shift validation rejects. An unsigned count needs only the requested direction after specialization; a signed dynamic count can require both shift directions, magnitude logic, and selection. Constant shifts simplify to wiring and sign/zero fill after inlining. There is no new actor state or failure field. Huge effective left shifts on BEAM can exhaust its bignum resources (`system_limit`); fixed-width hardware produces the modular result without allocating that intermediate. VM resource exhaustion is outside the arithmetic agreement contract.

## Explicit floating-point operations

`hls_float` provides `add/3`, `sub/3`, `mul/3`, `eq/3`, and `lt/3`. Their first argument selects `hls_nums:float16()`, `float32()`, or `float64()`. The remaining arguments and the result are ordinary BEAM floats (Booleans for comparisons). Each call is a precision boundary:

```erlang
Sum = hls_float:add(hls_nums:float32(), X,
    hls_float:literal(hls_nums:float32(), 1.0)),
Delta = hls_float:sub(hls_nums:float32(), Sum, X).
```

For `X = 16777216.0`, `Delta` is positive zero on both targets. Multiplication followed by addition is two separately rounded operations; it is never implicitly fused.

The CPU implementation first normalizes operands to the declared format using its codec, then flushes subnormal operands to zero with their sign preserved. It computes addition, subtraction, and multiplication using exact integer significands and binary exponents, rounds once to nearest with ties to even, and flushes subnormal results to signed zero. Rounding can promote a value immediately below the minimum normal to that normal. The exact intermediate avoids binary64 double rounding and retains all 106 significand bits of a binary64 product before rounding.

The XLS implementation calls the corresponding `apfloat` operations with explicit exponent and fraction widths. Float fields and helper signatures use qualified `apfloat::APFloat` structs. Record and nested list/vector codecs flatten and reconstruct these structs without changing their bit patterns, including signed zeros and subnormals. Ordinary integer-only providers retain their direct bit casts and do not import the floating-point library.

`hls_float:literal(T, Number)` supplies a typed compile-time constant in translated code and codec normalization on BEAM. It preserves finite subnormals; flushing happens when an arithmetic operation consumes the value. Its value argument must be a literal in translated code. Runtime format conversion is not implemented: an XLS variable passed to an operation must already have that operation's precision. XLS rejects a mismatched float format or an integer passed in its place. Bare float literals must be given a type with `literal/2`; ordinary `+`, `-`, and `*` do not implement floating-point arithmetic on XLS structs.

`eq/3` and `lt/3` compare the normalized, flushed values numerically. In particular, positive and negative zero compare equal, and neither is less than the other. This differs from Erlang's strict `=:=`, which distinguishes their signs in OTP 27 and later. Use these explicit comparisons when controlling an actor from a numerical result.

Overflow raises `badarith` on BEAM. In hardware, a nonfinite operand or result produces a source-located `badarith` failure code. The compiler propagates that failure through helpers and selected branches with the same first-failure rule as other expressions; an unselected operation cannot fail the callback. Failure payloads are placeholders. Existing actor failure policy applies: a GS service returns a typed error reply and clears its state, while state-machine schedulers retain their existing failure handling. A wire pass-through or storage operation does not validate arbitrary nonfinite bit patterns; those remain outside the host codec contract.

There is no floating-point division, fused multiply-add, implicit mixed-format conversion, or general float operator inference. These need separate arithmetic policies and agreement tests. The explicit operations provide exact agreement at the declared rounding points; they do not establish an error bound for an approximate algorithm.

## Extending arithmetic support

Explicit operations keep ordinary ERTS values while declaring the places where precision changes. The compiler can later infer necessary conversions and eliminate redundant ones. Modular polynomial regions can often defer normalization; division and comparisons need attention to the particular widths. Fixed-point multiplication must account for the combined fractional scale, and `hls_vec:dot/3` requires a sufficiently wide accumulator before any subsequent wrapping or saturation.

An exact execution reference should evaluate typed operations with their declared intermediate widths and float policies, using the XLS interpreter/JIT where practical. Ordinary ERTS execution remains useful for algorithm development. Approximate numerical kernels can instead declare error tolerances over specified inputs and an explicit rounding schedule. Actor control, routing, and protocol observations still require exact agreement. A tolerance on one arithmetic operation is not automatically a bound on a complete computation.

## Executable coverage

- `hls_float_tests` checks every binary16 encoding against an independent arithmetic decoding reference: all 63,488 finite encodings repack exactly, and all 2,048 nonfinite encodings are rejected. It also checks every midpoint between adjacent finite binary16 magnitudes, both signs, and the immediately neighboring binary64 values. Binary32/binary64 tests cover every exponent, both signs, fraction boundaries, and deterministic additional bit patterns.
- Float tests cover rounding ties and adjacent values, both overflow signs, finite rounding at the overflow threshold, subnormals, signed underflow, numeric coercion, recursive normalization, and exact-packing rejection.
- Integer/fixed-point tests cover checked boundaries, intentional wrapping of large bignums, idempotence, wire agreement, scale preservation, and the distinction between saturation and wrapping.
- `bash tools/test_integer_arithmetic.sh XLS_ROOT` compares explicitly wrapped BEAM division/remainder with DSLX/JIT and optimized RTL at signed and unsigned 8/16/32/64-bit widths. RTL exhausts all 8-bit pairs and samples boundaries and a deterministic spread at larger widths. The control-failure regression checks guard alternatives, short-circuiting, first failures, zero-divisor initializers, and stalled service replies. The small actor-debug regression queries included-helper arithmetic failures through `hls_debug:info` with block-RAM scheduler state.
- `bash tools/test_integer_shifts.sh XLS_ROOT` compares lowered shifts across 12 value/count type combinations, including 128-bit values and 64-bit counts. RTL exhausts all four signedness combinations of 8-bit values/counts. Wider tests cover direction reversal, signed-count minima, overshifts, and counts above 32 bits. The reference executes BEAM shifts directly for counts up to magnitude 1,024; larger counts use the equivalent width-saturated count to avoid enormous bignum allocations. The control-flow service tests additionally exercise literal counts, wrapping before comparisons, guard fallthrough, and stalled replies at three pipeline schedules.
- `hls_numeric_dslx` lowers actual Erlang wrapping expressions and compares their XLS results with BEAM values. `hls_numeric_semantics.inc.x` records the integer-division and float-cancellation counterexamples and verifies XLS's subnormal behavior. The simulation preparation and CI runner include these tests.
- `tools/test_float_arithmetic.sh` lowers real Erlang operations for binary16/32/64, compares selected cases with the DSLX interpreter and JIT, and replays boundary and deterministic bit-pattern corpora through optimized generated RTL. Macro-configured actors exercise public message packing, nested vector codecs, initialization, overflow errors, unselected overflow, recovery, and stalled replies.
