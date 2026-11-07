/** Select readable labels in CSS-pixel screen coordinates. Candidates carry
 * text, a top-left rectangle (x, y, width, height), and optional priority/key.
 * Higher priorities win; ties preserve input order. Duplicate keys (text by
 * default), overlapping rectangles and labels outside the viewport are omitted.
 * Keys are reserved only after placement, so a later visible copy can survive.
 * Returned objects are unchanged; the caller owns text measurement and drawing. */
export function layoutLabels(labels, { width, height, gap = 3 }) {
  const placed = [],
    keys = new Set();
  const ranked = labels
    .slice()
    .sort((a, b) => (b.priority ?? 0) - (a.priority ?? 0));
  for (const label of ranked) {
    const key = label.key ?? label.text;
    if (
      !label.text ||
      keys.has(key) ||
      ![label.x, label.y, label.width, label.height].every(Number.isFinite) ||
      label.width <= 0 ||
      label.height <= 0 ||
      label.x < 0 ||
      label.y < 0 ||
      label.x + label.width > width ||
      label.y + label.height > height ||
      placed.some((other) => overlaps(label, other, gap))
    )
      continue;
    placed.push(label);
    keys.add(key);
  }
  return placed;
}

/** A single gap is the minimum empty space between two screen rectangles. */
function overlaps(a, b, gap) {
  return (
    a.x < b.x + b.width + gap &&
    a.x + a.width + gap > b.x &&
    a.y < b.y + b.height + gap &&
    a.y + a.height + gap > b.y
  );
}
