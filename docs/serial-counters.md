# Wrapping counters

`hls_serial:counter(W)` stores a counter in W bits, for any positive W. Values are ordinary integers on BEAM and unsigned bit vectors in XLS. Packing, `wrap/2`, and `add/3` reduce modulo `2^W`; negative values and bignums are accepted. `pack_exact/2` rejects values that would change during packing. Counter fields compose with the existing record and collection codecs.

```erlang
Type = hls_serial:counter(32),
A = 16#fffffffe,
B = hls_serial:add(Type, A, 3),
1 = B,
true = hls_serial:before(Type, A, B),
3 = hls_serial:difference(Type, B, A),
-3 = hls_serial:difference(Type, A, B),
A = hls_serial:add(Type, B, -3).
```

`difference(Type, Left, Right)` returns the signed displacement from Right to Left. `before(Type, Left, Right)` tests whether that displacement is negative; equal counters return false. These operations recover chronological order only when the **actual separation is strictly less than `2^(W-1)` steps**. Keep this bound across all relevant in-flight messages, retained state, and restarts. Equal residues cannot reveal a lost full revolution. This uses the half-range ordering described in [RFC 1982](https://www.rfc-editor.org/rfc/rfc1982.html); addition here also permits signed offsets of arbitrary magnitude.

An exactly half-range pair is detectably ambiguous: difference and ordering raise `badarg` on BEAM and produce a source-located `badarg` failure in XLS. Other violations of the actual-separation bound cannot be detected from the stored bits. The ordering is not globally transitive over arbitrary counter populations and must not be used to sort an unbounded history.

Declare fields as, for example, `step = hls_type:zero() :: hls_serial:counter(32)`. Call `add/3`, `difference/3`, and `before/3` explicitly: annotations do not change Erlang's `+`, `-`, `<`, `min`, `max`, or sorting behavior. Ordinary equality is appropriate for normalized counters under the same temporal bound. Use a `case` for a serial comparison; provider calls are not Erlang guard expressions.

`difference/3` produces an XLS signed W-bit result; the antipodal minimum value is excluded. `add/3` accepts negative offsets without requiring callers to negate an unsigned counter. As with other HLS operations, argument expressions must have enough intermediate width before they reach the provider.

`bash tools/test_serial.sh XLS_ROOT` compares BEAM, the DSLX interpreter/JIT, and optimized RTL at 1, 3, 8, 9, 32, 64, and 65 bits. It exhausts byte-sized pairs, checks unequal signed/unsigned operand widths, and exercises rollover, selected/skipped ambiguity failures, and stalled replies through a framed actor.
