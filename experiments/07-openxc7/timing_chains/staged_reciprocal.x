// Isolated exact rounded division by twelve for every signed 37-bit numerator.
// These functions are separate experiment stages, not a streaming interface.
import hls_fixed;

// Unsplit reference, with nearest rounding and ties away from zero.
pub fn reference(n: sN[37]) -> sN[37] {
  hls_fixed::round_ratio<u32:12>(n)
}

// Six independent products fit the signed 25-by-18 DSP multiplier inputs.
// Return aligned rows modulo 2^80; their sum is the exact signed product.
pub fn products(n: sN[37]) -> sN[80][6] {
  const M = uN[38]:183251937963;
  let lo = (n as uN[37])[0+:uN[24]];
  let hi = ((n as uN[37])[24+:uN[13]]) as sN[13];
  let m0 = M[0+:uN[17]];
  let m1 = M[17+:uN[17]];
  let m2 = M[34+:uN[4]];
  let p00 = (lo as uN[41]) * (m0 as uN[41]);
  let p01 = (lo as uN[41]) * (m1 as uN[41]);
  let p02 = (lo as uN[28]) * (m2 as uN[28]);
  let p10 = (hi as sN[31]) * (m0 as sN[31]);
  let p11 = (hi as sN[31]) * (m1 as sN[31]);
  let p12 = (hi as sN[18]) * (m2 as sN[18]);
  [p00 as sN[80], (p01 as sN[80]) << u32:17,
   (p02 as sN[80]) << u32:34, (p10 as sN[80]) << u32:24,
   (p11 as sN[80]) << u32:41, (p12 as sN[80]) << u32:58]
}

// Preserve the sum modulo 2^80 without propagating a carry along either row.
fn compress(a: sN[80], b: sN[80], c: sN[80]) -> (sN[80], sN[80]) {
  (a ^ b ^ c, ((a & b) | (a & c) | (b & c)) << u32:1)
}

// Reduce six aligned products and the rounding bias to two carry-save rows.
pub fn reduce(rows: sN[80][6]) -> (sN[80], sN[80]) {
  let (a, b) = compress(rows[u32:0], rows[u32:1], rows[u32:2]);
  let (c, d) = compress(rows[u32:3], rows[u32:4], rows[u32:5]);
  let (e, f) = compress(a, b, c);
  let (g, h) = compress(d, sN[80]:1 << u32:40, e);
  compress(f, g, h)
}

// Complete the biased product and retain the same quotient bits as reference.
pub fn finish(rows: (sN[80], sN[80])) -> sN[37] {
  ((rows.0 + rows.1) >> u32:41) as sN[37]
}
