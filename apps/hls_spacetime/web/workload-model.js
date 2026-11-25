/** Decode one pre-edge control from four little-endian valid/ready value and known-bit masks. */
export function probeState(trace, probes, clock, index) {
  const step = Math.ceil(probes / 8),
    base = clock * 4 * step + (index >> 3),
    mask = 1 << index % 8;
  const valid = trace[base] & mask,
    validKnown = trace[base + step] & mask;
  if (validKnown && !valid) return 0;
  if (!validKnown || !(trace[base + 3 * step] & mask)) return 3;
  return trace[base + 2 * step] & mask ? 1 : 2;
}

/** Return the inclusive comparison interval, excluding the unpaired initial sample except at C0. */
export function windowStart(end, span) {
  return Math.max(end === 0 ? 0 : 1, end - span + 1);
}

/** Combine changes independently from unknowns across inclusive, contiguous fixed-size cycle blocks. */
export function unionMasks(blocks, first, end, chunk, stride) {
  const size = 2 * stride,
    low = Math.floor(first / chunk);
  if (
    first < 0 ||
    first > end ||
    blocks.length !== Math.floor(end / chunk) - low + 1 ||
    blocks.some((b) => b.length !== chunk * size)
  )
    throw Error("Incomplete cycle block");
  const union = new Uint8Array(size);
  for (let c = first; c <= end; c++) {
    const bytes = blocks[Math.floor(c / chunk) - low],
      offset = (c % chunk) * size;
    for (let i = 0; i < size; i++) union[i] |= bytes[offset + i];
  }
  return union;
}
