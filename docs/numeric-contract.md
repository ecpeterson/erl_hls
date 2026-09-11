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
| `hls_nums:float16/float32` | Round to IEEE binary16/binary32 using the VM's float encoding, including ties to even and gradual underflow; reject results that encode infinity. | `hls_type:normalize/2` exposes the rounded host value; `pack_exact/2` rejects any change to the original term. |
| `hls_nums:float64` | Preserve finite binary64 floats, including signed zero and subnormals. Integer inputs undergo ERTS's integer-to-binary64 conversion. | `pack_exact/2` rejects integer-to-float coercion as well as any other term change. |

All float codecs continue to accept integer inputs through the VM's binary64 conversion before encoding. This can lose integer precision before narrowing, and excessively large integers are rejected. For example, normalizing `(1 bsl 53) + 1` as `float64` produces `9007199254740992.0`. Use `pack_exact/2` when coercion is unwanted. Bignum storage itself is never a reason to reject an integer: an in-range `u64` or `uN(96)` value remains valid regardless of how ERTS stores it.

Fixed-size lists and vectors require exact lengths, and generated record packers require the declared record tag and arity. Numeric normalization does not permit deleting, adding, or padding fields or elements. Nested providers are checked individually, so one short element cannot be compensated by an oversized neighbor.

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

[ERTS uses binary64 live floats and does not support live infinity or NaN](https://www.erlang.org/docs/28/system/data_types.html#float). Its bit syntax can nevertheless produce narrow infinity when a finite input overflows: encoding `65520.0` as binary16 produces the infinity pattern. The codecs reject that result so a successful pack is always decodable.

Rounding to the largest finite value remains valid: binary16 packing accepts `65519.0` and normalizes it to `65504.0`. Underflow to signed zero is also valid. Both signed zeros and finite subnormals retain their wire bits. Applications that require exact values can select `pack_exact/2`; applications that require infinity/NaN payloads need an explicit bit-level representation instead of an ERTS float.

## Arithmetic is a separate contract

The codec laws do not imply that arbitrary ERTS and XLS computations agree. For addition, subtraction, and multiplication at a common modular integer width, reducing arbitrary-precision intermediates at the end gives the same residue as reducing after each operation. This follows from the ring homomorphism from integers to integers modulo `2^Width`.

Division, comparisons, and right shifts generally do not preserve that equivalence. With `X = 255`, `(X + 1) div 2` produces `128` on ERTS and `0` with `u8` intermediate arithmetic. Both the original input and the ERTS result fit `u8`, so even checked boundary packing cannot detect the disagreement. Applying `wrap(Word, X + 1)` before division explicitly selects the modular intermediate on ERTS too.

Floating-point rounding also depends on its schedule. Binary64 evaluation of `(16777216.0 + 1.0) - 16777216.0` produces `1.0`. Binary32 addition followed by binary32 subtraction produces `0.0`. All inputs are exactly representable in binary32. Rounding each operation therefore differs from rounding only the final output. Cancellation can magnify small local discrepancies, and a comparison can turn them into different actor messages.

XLS's [floating-point add/subtract and multiply](https://google.github.io/xls/floating_point/#apfloataddsub) also flush subnormal inputs and outputs to zero and do not report exception flags. That differs from the finite subnormal encodings supported by our codecs. Selecting `float64` does not by itself eliminate this difference. Nor is evaluating every operation in binary64 and then narrowing a universal exact emulator: double rounding and operations such as fused multiply-add need their own treatment.

The generic Erlang-to-DSLX compiler does not yet provide complete floating-point expression lowering: it lacks qualified float type emission and typed dispatch to XLS's arithmetic library. Host codecs and normalization are useful independently, and the handwritten FMAC experiment already calls that library directly. This PR's float reference tests exercise the XLS library explicitly; they are not evidence that an arbitrary float-bearing Erlang actor can be translated.

## Extending arithmetic support

The intended bridge keeps ordinary ERTS values while declaring the places where precision changes. The compiler can later infer necessary conversions and eliminate redundant ones. Modular polynomial regions can often defer normalization; division and comparisons need attention to the particular widths. Fixed-point multiplication must account for the combined fractional scale, and `hls_vec:dot/3` requires a sufficiently wide accumulator before any subsequent wrapping or saturation.

An exact execution reference should evaluate typed operations with their declared intermediate widths and float policies, using the XLS interpreter/JIT where practical. Ordinary ERTS execution remains useful for algorithm development. Approximate numerical kernels can instead declare error tolerances over specified inputs and an explicit rounding schedule. Actor control, routing, and protocol observations still require exact agreement. A tolerance on one arithmetic operation is not automatically a bound on a complete computation.

## Executable coverage

- `hls_float_tests` checks every binary16 encoding: all 63,488 finite encodings repack exactly, and all 2,048 nonfinite encodings are rejected. Binary32/binary64 tests cover every exponent, both signs, fraction boundaries, and deterministic additional bit patterns.
- Float tests cover rounding ties and adjacent values, both overflow signs, finite rounding at the overflow threshold, subnormals, signed underflow, numeric coercion, recursive normalization, and exact-packing rejection.
- Integer/fixed-point tests cover checked boundaries, intentional wrapping of large bignums, idempotence, wire agreement, scale preservation, and the distinction between saturation and wrapping.
- `hls_numeric_dslx` lowers actual Erlang wrapping expressions and compares their XLS results with BEAM values. `hls_numeric_semantics.inc.x` records the integer-division and float-cancellation counterexamples and verifies XLS's subnormal behavior. The simulation preparation and CI runner include these tests.
