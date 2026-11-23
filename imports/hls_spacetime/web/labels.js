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

/** Project labels sharing an anchor group on one common spatial column.
 * Alternatives in a group must use the same ordering (for example chip corners).
 * Prefer the column with most visible labels, then the leftmost mean position.
 * Clipped members stay omitted: choosing a different corner for each clock can
 * reorder their apparent screen positions even when time coordinates are linear.
 */
export function projectLabelAnchors(labels, project) {
  const rows = labels.map((label) => ({
    label,
    points: (label.alternatives ?? [label.position]).map(project),
  }));
  const groups = new Map();
  for (const row of rows) {
    if (row.label.anchorGroup === undefined) continue;
    const key = row.label.anchorGroup;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(row);
  }
  const anchors = new Map();
  for (const [key, members] of groups) {
    const count = members[0].points.length;
    if (members.some((row) => row.points.length !== count))
      throw Error("Aligned label alternatives must have equal lengths");
    const choices = Array.from({ length: count }, (_, index) => {
      const visible = members
        .map((row) => row.points[index])
        .filter((point) => point.visible);
      return {
        index,
        count: visible.length,
        x: visible.length
          ? visible.reduce((sum, point) => sum + point.x, 0) / visible.length
          : Infinity,
      };
    });
    choices.sort((a, b) => b.count - a.count || a.x - b.x || a.index - b.index);
    anchors.set(key, choices[0]?.index);
  }
  return rows.flatMap(({ label, points }) => {
    const point =
      label.anchorGroup === undefined
        ? points.filter((point) => point.visible).sort((a, b) => a.x - b.x)[0]
        : points[anchors.get(label.anchorGroup)];
    return point?.visible ? [{ label, point }] : [];
  });
}
