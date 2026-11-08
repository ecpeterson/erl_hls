/** Coalesce display overlays without altering event/storage evidence or hit targets.
 * Tile coordinates may stand for many native cells. A marker is one display glyph;
 * priority preserves selection, and conflicting equal-priority colors stay neutral.
 * Storage is a union of occupied vertical intervals, not a new value lifetime. */
export function overlayDisplay(scene) {
  const markers = new Map(),
    columns = new Map(),
    exact = new Map(),
    segments = [];
  for (const row of scene.markers) {
    const key = row.position.join("/");
    const old = markers.get(key);
    const priority = row.priority ?? 0;
    if (!old || priority > old.priority) {
      markers.set(key, {
        ...row,
        priority,
        contributors: (old?.contributors ?? 0) + 1,
      });
    } else if (priority === old.priority) {
      old.contributors++;
      old.size = Math.max(old.size ?? 0.006, row.size ?? 0.006);
      if (old.color !== row.color) old.color = "#c3cdd4";
    } else old.contributors++;
  }
  for (const row of scene.segments) {
    if (
      row.kind !== "storage" ||
      row.from[0] !== row.to[0] ||
      row.from[1] !== row.to[1]
    ) {
      const a = row.from.join("/"),
        b = row.to.join("/");
      const forward = a <= b;
      const from = forward ? row.from : row.to,
        to = forward ? row.to : row.from;
      const color = forward ? row.color : (row.colorEnd ?? row.color);
      const colorEnd = forward ? (row.colorEnd ?? row.color) : row.color;
      const key = `${row.kind}/${row.radius ?? 0.002}/${row.dash ?? 0}/${from.join("/")}>${to.join("/")}`;
      if (!exact.has(key))
        exact.set(key, { ...row, from, to, color, colorEnd, contributors: 1 });
      else {
        const old = exact.get(key);
        old.contributors++;
        if (old.color !== color || old.colorEnd !== colorEnd)
          old.color = old.colorEnd = "#c3cdd4";
      }
      continue;
    }
    const key = row.from.slice(0, 2).join("/");
    if (!columns.has(key)) columns.set(key, []);
    columns.get(key).push(row);
  }
  for (const row of exact.values()) segments.push(row);
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
      const prominent = [...active].filter(
        (row) => (row.radius ?? 0.002) === radius,
      );
      const colors = prominent.map((row) =>
        row.from[2] < row.to[2]
          ? [row.color, row.colorEnd ?? row.color]
          : [row.colorEnd ?? row.color, row.color],
      );
      const mixed = colors.some(
        (pair) => pair[0] !== colors[0][0] || pair[1] !== colors[0][1],
      );
      segments.push({
        ...prominent[0],
        from: [rows[0].from[0], rows[0].from[1], lo],
        to: [rows[0].from[0], rows[0].from[1], hi],
        radius,
        color: mixed ? "#c3cdd4" : colors[0][0],
        colorEnd: mixed ? "#c3cdd4" : colors[0][1],
        contributors: active.size,
      });
      storageSpans++;
    }
  }
  return {
    ...scene,
    markers: [...markers.values()],
    segments,
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
