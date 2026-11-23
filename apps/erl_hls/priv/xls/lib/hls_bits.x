// Erlang writes the low byte of a /little integer first, followed by further
// complete bytes and finally any partial high byte. In stream order, the first
// physical bit is the MSB. Conversion indices depend only on the static width;
// inlining and unrolling reduce these permutations to wires.
fn permute<N: u32, FROM_STREAM: bool>(value: bits[N]) -> bits[N] {
  // The extra byte keeps both slices well-typed even for N < 8. It is
  // discarded after the fixed permutation and adds no physical storage.
  let extended = value as bits[N + u32:8];
  let full = for (i, result): (u32, bits[N + u32:8]) in u32:0..(N / u32:8) {
    let packed_index = i * u32:8;
    let stream_index = N - packed_index - u32:8;
    let source = if FROM_STREAM { stream_index } else { packed_index };
    let target = if FROM_STREAM { packed_index } else { stream_index };
    bit_slice_update(result, target, extended[source+:u8])
  } (zero!<bits[N + u32:8]>());
  let remainder = N % u32:8;
  let source = if FROM_STREAM { u32:0 } else { N - remainder };
  let target = if FROM_STREAM { N - remainder } else { u32:0 };
  bit_slice_update(full, target, extended[source+:bits[N % u32:8]]) as bits[N]
}

pub fn to_stream<N: u32>(value: bits[N]) -> bits[N] {
  permute<N, false>(value)
}

pub fn from_stream<N: u32>(value: bits[N]) -> bits[N] {
  permute<N, true>(value)
}

// Append padding to a physical bitstring, without extending its numeric value.
pub fn pad<N: u32, W: u32>(value: bits[N]) -> bits[W] {
  from_stream(to_stream(value) ++ zero!<bits[W - N]>())
}

pub fn frame_payload<N: u32, W: u32 = {((N + u32:31) / u32:32) * u32:32}>(
    value: bits[N]) -> bits[W] {
  pad<N, W>(value)
}

// Live bitstrings use a one-tuple, with the first stream bit at the MSB.
// This keeps integer and bitstring operations distinct in the DSLX type system.
pub fn length<N: u32>(value: (bits[N],)) -> u32 { N }

// Out-of-range projections are placeholders: the enclosing pattern checks
// length before accepting a match. Widening also makes zero-width inputs legal.
pub fn segment<OFFSET: u32, W: u32, N: u32>(value: (bits[N],)) -> bits[W] {
  let end = if N >= OFFSET + W { OFFSET + W } else { N };
  let shift = N - end;
  ((value.0 as bits[N + W]) >> shift) as bits[W]
}

pub fn tail<OFFSET: u32, N: u32,
    REST: u32 = {N - (if N >= OFFSET { OFFSET } else { N })}>(
    value: (bits[N],)) -> (bits[REST],) {
  const_assert!(REST == N - (if N >= OFFSET { OFFSET } else { N }));
  (value.0 as bits[REST],)
}

// A prebound Erlang variable may have a wider integer type than its segment.
// Compare mathematical values, including signed/unsigned and negative cases.
pub fn same_integer<S: bool, W: u32, T: bool, V: u32>(
    left: xN[S][W], right: xN[T][V]) -> bool {
  (left as sN[W + V + u32:1]) == (right as sN[W + V + u32:1])
}

pub fn same_bits<N: u32, M: u32>(left: (bits[N],), right: (bits[M],)) -> bool {
  N == M && (left.0 as bits[N + M]) == (right.0 as bits[N + M])
}

#[test]
fn fixed_bitstring_projections() {
  assert_eq(segment<u32:3, u32:9>((u16:0xa5c7,)), u9:92);
  assert_eq(tail<u32:8>((u16:0xa5c7,)), (u8:0xc7,));
  assert_eq(tail<u32:16>((u16:0xa5c7,)), (bits[0]:0,));
  assert_eq(length(tail<u32:17>((u16:0xa5c7,))), u32:0);
  assert_eq(segment<u32:0, u32:8>((bits[0]:0,)), u8:0);
  assert_eq(same_integer(s8:-1, u8:255), false);
  assert_eq(same_integer(s32:255, u8:255), true);
  assert_eq(same_bits((u8:1,), (u16:1,)), false);
}
