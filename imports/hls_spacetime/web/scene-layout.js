/** Real scene coordinates: chip X/Y plus increasing clock Z. Time is a third
 * coordinate, not a screen displacement; spacing changes no recorded clocks. */
export function clockPoint(point, cycle, first, window, spacing) {
  return [
    point.x,
    point.y,
    ((cycle - first - (window - 1) / 2) * spacing) / 80,
  ];
}

/** Bounds of selected geometry; no origin/centroid replaces a physical point. */
export function sceneBounds(points) {
  let min = [Infinity, Infinity, Infinity],
    max = [-Infinity, -Infinity, -Infinity];
  let count = 0;
  for (const point of points) {
    if (!point || point.length !== 3 || !point.every(Number.isFinite)) continue;
    count++;
    for (let k = 0; k < 3; k++) {
      min[k] = Math.min(min[k], point[k]);
      max[k] = Math.max(max[k], point[k]);
    }
  }
  if (!count) return { min: [-1, -1, -0.1], max: [1, 1, 0.1] };
  for (let k = 0; k < 3; k++)
    if (max[k] - min[k] < 0.05) {
      min[k] -= 0.025;
      max[k] += 0.025;
    }
  return { min, max };
}

/** Overview retains occupied grid bins, including separated islands and clocks.
 * Colors are assigned after aggregation: a bin unions function roles and destinations,
 * preserves unknown destination contributors, and keeps
 * the largest finite supplied delay plus an independent unknown-contributor flag.
 * Its center/count is a display aggregate, never a native cell or wire position. */
export function occupiedBins(marks, size = 0.025) {
  if (!(size > 0) || !Number.isFinite(size))
    throw Error("Invalid overview bin size");
  const bins = new Map();
  for (const mark of marks) {
    const p = mark.position;
    const x = Math.floor(p[0] / size),
      y = Math.floor(p[1] / size),
      key = `${x}/${y}/${p[2]}`;
    if (!bins.has(key))
      bins.set(key, {
        position: [(x + 0.5) * size, (y + 0.5) * size, p[2]],
        size: size * 0.8,
        count: 0,
        roles: new Set(),
        computations: new Set(),
        computationShared: false,
        computationUnknown: false,
        delayNs: null,
        timingUnknown: false,
        timingApplicable: false,
      });
    const bin = bins.get(key),
      known =
        typeof mark.delayNs === "number" &&
        Number.isFinite(mark.delayNs) &&
        mark.delayNs >= 0;
    bin.count++;
    bin.roles.add(typeof mark.role === "string" ? mark.role : null);
    if (mark.computationShared) bin.computationShared = true;
    else if (
      typeof mark.computationKey === "string" &&
      mark.computationKey.length
    )
      bin.computations.add(mark.computationKey);
    else bin.computationUnknown = true;
    if (mark.timingApplicable !== false) {
      bin.timingApplicable = true;
      if (known) bin.delayNs = Math.max(bin.delayNs ?? 0, mark.delayNs);
      if (!known || mark.timingUnknown) bin.timingUnknown = true;
    }
  }
  return [...bins.values()].map(
    ({ roles, computations, computationUnknown, ...bin }) => ({
      ...bin,
      computationKey:
        !computationUnknown && !bin.computationShared && computations.size === 1
          ? [...computations][0]
          : null,
      computationShared:
        !computationUnknown && (bin.computationShared || computations.size > 1),
      role: roles.size === 1 ? [...roles][0] : "mixed",
    }),
  );
}
