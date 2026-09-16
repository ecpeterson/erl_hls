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
