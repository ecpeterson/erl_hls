/** Coalesce display overlays without altering event/storage evidence or hit targets.
 * Timing colors outrank neutral annotations; explicit selection outranks both.
 * Unknown timing is never replaced by known timing at the same selection level.
 * Equal-ranked color conflicts stay neutral, and retain their contributor kinds.
 */
const CONFLICT_COLOR = "#c3cdd4";

// Presentation intent is explicit: RGB values cannot establish timing evidence.
// Legacy timing marks already carry timingApplicable/timingUnknown metadata.
function timing(row) {
  return (
    row.overlayRole === "timing" ||
    (row.overlayRole !== "annotation" &&
      row.timingApplicable !== false &&
      (row.timingApplicable !== undefined || row.timingUnknown !== undefined))
  );
}
function rank(row) {
  const priority = row.priority ?? 0,
    selected = priority >= 2,
    timed = timing(row);
  return [
    Number(selected),
    selected ? priority : 0,
    Number(timed),
    Number(timed && row.timingUnknown === true),
    priority,
  ];
}
function compare(a, b) {
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return a[i] - b[i];
  return 0;
}
function identity(row) {
  return [row.kind ?? "", row.color, row.colorEnd ?? row.color].join("/");
}

// Accumulate presentation evidence separately from the winning paint. A neutral
// annotation contributes to the glyph without erasing the timing it annotates.
function merge(group, row) {
  const incomingRank = rank(row),
    colorEnd = row.colorEnd ?? row.color,
    count = row.contributors ?? 1;
  if (!group)
    group = {
      row,
      rank: incomingRank,
      color: row.color,
      colorEnd,
      conflict: Boolean(row.colorConflict),
      size: row.size,
      contributors: 0,
      kinds: new Set(),
      evidence: { known: 0, unknown: 0, annotations: 0 },
    };
  else {
    const order = compare(incomingRank, group.rank);
    if (order > 0) {
      group.row = row;
      group.rank = incomingRank;
      group.color = row.color;
      group.colorEnd = colorEnd;
      group.conflict = Boolean(row.colorConflict);
      group.size = row.size;
    } else if (order === 0) {
      group.conflict ||=
        Boolean(row.colorConflict) ||
        group.color !== row.color ||
        group.colorEnd !== colorEnd;
      if (identity(row) < identity(group.row)) group.row = row;
      if (row.size !== undefined)
        group.size = Math.max(group.size ?? 0, row.size);
    }
  }
  group.contributors += count;
  for (const kind of row.overlayKinds ?? (row.kind ? [row.kind] : []))
    group.kinds.add(kind);
  const evidence = row.overlayEvidence ?? {
    known: timing(row) && !row.timingUnknown ? count : 0,
    unknown: timing(row) && row.timingUnknown ? count : 0,
    annotations: timing(row) ? 0 : count,
  };
  for (const key of Object.keys(group.evidence))
    group.evidence[key] += evidence[key];
  return group;
}
function finish(group) {
  return {
    ...group.row,
    ...(group.size === undefined ? {} : { size: group.size }),
    color: group.conflict ? CONFLICT_COLOR : group.color,
    colorEnd: group.conflict ? CONFLICT_COLOR : group.colorEnd,
    colorConflict: group.conflict,
    contributors: group.contributors,
    overlayKinds: [...group.kinds].sort(),
    overlayEvidence: group.evidence,
  };
}

/** Merge exact marker/surface collisions deterministically. Kind is descriptive,
 * not a distinct surface: equal endpoints, radii and dashes draw only once.
 * Unequal radii/dashes retain intentional schematic cores and dashed sleeves.
 * Storage is a union of occupied vertical intervals, not a new value lifetime.
 */
export function overlayDisplay(scene) {
  const markers = new Map(),
    columns = new Map(),
    exact = new Map();
  for (const row of scene.markers) {
    const key = row.position.join("/");
    markers.set(key, merge(markers.get(key), row));
  }
  const surface = (row) => {
    const a = row.from.join("/"),
      b = row.to.join("/"),
      forward = a <= b;
    const from = forward ? row.from : row.to,
      to = forward ? row.to : row.from,
      color = forward ? row.color : (row.colorEnd ?? row.color),
      colorEnd = forward ? (row.colorEnd ?? row.color) : row.color;
    const key = `${from.join("/")}>${to.join("/")}/${row.radius ?? 0.002}/${row.dash ?? 0}`;
    exact.set(
      key,
      merge(exact.get(key), { ...row, from, to, color, colorEnd }),
    );
  };
  for (const row of scene.segments) {
    if (
      row.kind !== "storage" ||
      row.from[0] !== row.to[0] ||
      row.from[1] !== row.to[1]
    ) {
      surface(row);
      continue;
    }
    const key = row.from.slice(0, 2).join("/");
    if (!columns.has(key)) columns.set(key, []);
    columns.get(key).push(row);
  }
  let storageSpans = 0;
  for (const rows of columns.values()) {
    const events = new Map(),
      active = new Set();
    const at = (z) => {
      if (!events.has(z)) events.set(z, { add: [], remove: [] });
      return events.get(z);
    };
    for (const row of rows) {
      const [lo, hi] = [row.from[2], row.to[2]].sort((a, b) => a - b);
      if (lo === hi) continue;
      at(lo).add.push(row);
      at(hi).remove.push(row);
    }
    const stops = [...events.keys()].sort((a, b) => a - b);
    for (let i = 0; i < stops.length - 1; i++) {
      const lo = stops[i],
        hi = stops[i + 1];
      for (const row of events.get(lo).remove) active.delete(row);
      for (const row of events.get(lo).add) active.add(row);
      if (!active.size) continue;
      let radius = 0;
      for (const row of active) radius = Math.max(radius, row.radius ?? 0.002);
      let group = null;
      for (const row of active) {
        const forward = row.from[2] < row.to[2];
        group = merge(group, {
          ...row,
          // Existing storage selection is expressed by thickness. Convert that
          // display choice into a rank before merging coincident annotations.
          priority: (row.radius ?? 0.002) === radius ? (row.priority ?? 0) : -1,
          from: [row.from[0], row.from[1], lo],
          to: [row.to[0], row.to[1], hi],
          color: forward ? row.color : (row.colorEnd ?? row.color),
          colorEnd: forward ? (row.colorEnd ?? row.color) : row.color,
        });
      }
      surface({ ...finish(group), radius });
      storageSpans++;
    }
  }
  const ordered = (groups) =>
    [...groups.entries()]
      .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
      .map(([, group]) => finish(group));
  return {
    ...scene,
    markers: ordered(markers),
    segments: ordered(exact),
    overlaySummary: {
      inputMarkers: scene.markers.length,
      displayedMarkers: markers.size,
      inputStorage: [...columns.values()].reduce(
        (n, rows) => n + rows.length,
        0,
      ),
      storageSpans,
    },
  };
}
