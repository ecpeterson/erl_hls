# Fixed-size bit syntax

Translated callbacks and typed local helpers can construct and match native Erlang bitstrings. `hls_bits:bits(Width)` declares a bitstring with exactly `Width` bits in a record field or helper spec. It accepts zero width and widths that are not multiples of eight. Packing preserves the bitstring exactly; integers, lists and bitstrings of a different length are rejected.

```erlang
-record(sample, {word = hls_type:zero() :: hls_bits:bits(24)}).

-spec decode(hls_bits:bits(24)) -> {hls_nums:uN(5), hls_nums:s16()}.
decode(<<5:3, Flags:5, Delta:16/signed-little>>) -> {Flags, Delta}.
```

The [`packed_samples`](../src/examples/packed_samples/packed_samples.erl) service decodes this format, adds the signed delta to an accumulator, and constructs a packed receipt. Its state and replies also exercise bitstrings inside generated record codecs.

## Segments and byte order

| Syntax | Meaning |
| --- | --- |
| `<<Value>>` | One unsigned, big-endian eight-bit integer segment. |
| `<<Value:Width/signed-little>>` | An integer segment with explicit width, sign and byte order. |
| `<<A:3, B:5, C:16/little>>` | Consecutive segments, with no implicit padding. |
| `<<Prefix:2/binary>>` | The first two bytes of a bitstring; a shorter value raises `badarg`. |
| `<<Prefix:3/binary-unit:5>>` | The first 15 bits; explicit sizes are multiplied by the unit. |
| `<<Value/binary>>` | The whole value, whose length must be divisible by eight. |
| `<<Value/bitstring>>` or `<<Value/bits>>` | The whole value, including any partial final byte. |
| `<<"AB", $C>>` | Literal character segments. String size/type annotations apply to each character. |

Widths must be nonnegative integer constants or constant integer expressions, including expanded macros. Units use Erlang's range of 1 through 256. The standard defaults and aliases (`bytes`, `bits`) are normalized by Erlang's bit-type implementation. Both big and little endian work for partial-byte integer widths and unaligned segments. `native`, float segments, UTF segments, runtime-dependent widths, and binary comprehensions are outside the translated subset.

Integer construction truncates to the requested width, just as Erlang bit syntax does. For example, `<<257:8>>` is `<<1>>` and `<<-1:8>>` is `<<255>>`. This operation is distinct from the checked numeric provider codecs. A constant bignum can be truncated directly; it need not first fit a narrower descriptor.

An integer segment's size does not widen arithmetic inside its value expression. The [numeric contract](numeric-contract.md) still applies: widen a bound operand with `hls_type:as/2` before an operation that needs a wider intermediate result. A matched unsigned field uses its segment width; a signed field uses the corresponding signed type. Zero-width integer fields bind zero, represented as a one-bit zero value.

## Matching and failures

Binary patterns work in callback or helper heads, `case` clauses and assignments, including inside records and tuples. They preserve clause order, guards, aliases and repeated or previously bound variables. An integer already bound at a different width compares by mathematical value: matching a signed `-1` against an unsigned eight-bit field does not match `255`. An out-of-range literal pattern does not truncate; it never matches.

A pattern without an unsized tail requires an exact length. Its final segment may instead be `Rest/binary` or `Rest/bitstring`; the prefix must fit, and a binary tail must be byte-sized. Empty tails are supported. A pattern whose prefix is longer than the input fails normally, including when its unselected branch would bind a tail.

Pattern failure rejects a clause or produces the existing `badmatch`, `case_clause` or `function_clause` outcome. A short construction source, or an unaligned whole `/binary` source, produces `badarg`. A failed value expression still fails inside a zero-width segment. Unselected branches do not contribute their failures. Hardware callbacks retain their established failure policy: `hls_gs` returns the error kind and clears its state; state-machine callbacks use their selected-outcome failure path.

`bit_size/1` and `byte_size/1`, including their `erlang:` forms, work on typed bitstrings in bodies and guards. They become constants; `byte_size/1` rounds up for a partial byte. Local definitions and `no_auto_import` declarations retain their ordinary resolution rules.

All values remain statically typed. Joined branch results and exported variables must agree in width, and operators require compatible XLS operand types. Different-length bitstrings are not a dynamic sum type. Bitstring operations require bitstring operands; a numeric value cannot be used as a binary segment. Dynamic Erlang term tests and general bitstring ordering are not supplied by this feature.

## Representation and checks

DSLX represents a live bitstring as a one-tuple containing its bits in stream order, with the first bit at the most significant position. The tuple distinguishes bitstrings from numbers without adding storage or logic. Its codec uses the shared fixed permutations in `hls_bits.x` to connect this representation to the transport's packed integer words. Records, explicit padding and fixed collections compose through the usual type-provider interface.

Construction and matching share one normalized segment representation. Short-input projections have well-typed placeholder values, paired with length predicates, so rejecting a pattern does not itself fail XLS type checking. Segment extraction and endian rearrangement have fixed offsets; synthesis can reduce them to wiring. Comparisons against format tags or previously bound values still require ordinary comparison logic.

Run `bash tools/test_binary.sh XLS_ROOT [STAGE]`. It compares a BEAM-derived corpus with DSLX, JIT and generated RTL; checks each codec direction independently; and asserts that a fixed extraction/rearrangement probe synthesizes with no cells. The live service test compares packed sample processing with BEAM, diagnoses an output stall through `hls_debug:get_counters/1`, and records the request/error/recovery sequence through `hls_debug:get_trace/1`. The bridge accesses only public AXI signals. Counter and trace records are saved under `STAGE/live`.
