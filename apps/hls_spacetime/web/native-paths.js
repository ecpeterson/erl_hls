/** Validate optional native STA annotations without adding any execution edges.
 * The drawing uses ordered placed cells; route bends and dynamic sensitization
 * are deliberately absent. The document's provenance binds the saved report. */
export function nativePaths(model) {
  const detail = model.document.nativePaths;
  if (!detail) return [];
  const fail = (condition, message) => {
    if (!condition) throw Error(`Native paths: ${message}`);
  };
  fail(
    model.catalogue &&
      detail.checkpoint === model.catalogue.checkpoint &&
      ["source", "rtl", "observation", "implementation"].every(
        (key) => detail.build?.[key] === model.bundle.build[key],
      ),
    "build/checkpoint mismatch",
  );
  fail(
    detail.scope === "static_timing" && detail.wireGeometry === false,
    "unsupported evidence scope",
  );
  fail(
    Array.isArray(detail.paths) && detail.paths.length <= 100,
    "path limit exceeded",
  );
  const ids = new Set();
  const ranking = detail.ranking;
  if (ranking) {
    fail(
      ranking.selection === "least_slack_per_capture_pin" &&
        Number.isSafeInteger(ranking.eligible) &&
        ranking.eligible >= 0 &&
        Number.isSafeInteger(ranking.limit) &&
        ranking.limit > 0 &&
        ranking.limit <= 100 &&
        ranking.retained === Math.min(ranking.limit, ranking.eligible) &&
        detail.paths.length <= ranking.retained,
      "invalid endpoint population",
    );
  }
  let lastRank = 0,
    lastSlack = -Infinity;
  const rankedPins = new Set();
  for (const path of detail.paths) {
    if (ranking) {
      fail(
        Number.isSafeInteger(path.rank) &&
          path.rank > lastRank &&
          path.rank <= ranking.retained &&
          path.slackNs >= lastSlack &&
          !rankedPins.has(path.endpoint),
        "invalid ranked endpoint",
      );
      lastRank = path.rank;
      lastSlack = path.slackNs;
      rankedPins.add(path.endpoint);
    }
    fail(
      typeof path.id === "string" && !ids.has(path.id),
      "duplicate/invalid path ID",
    );
    ids.add(path.id);
    fail(
      [
        path.slackNs,
        path.dataDelayNs,
        path.logicDelayNs,
        path.routeDelayNs,
      ].every(Number.isFinite),
      "invalid nanosecond timing",
    );
    fail(
      Number.isSafeInteger(path.logicLevels) && path.logicLevels >= 0,
      "invalid logic-level count",
    );
    fail(
      Array.isArray(path.steps) &&
        path.steps.length >= 2 &&
        path.steps.length <= 512,
      "invalid ordered pin list",
    );
    for (const step of path.steps) {
      const cell = model.cells.get(step.cell);
      fail(
        cell && Number.isFinite(cell.x) && Number.isFinite(cell.y),
        `missing placed cell ${step.cell}`,
      );
      fail(
        typeof step.pin === "string" &&
          step.pin.slice(0, step.pin.lastIndexOf("/")) === step.cell,
        "pin/cell mismatch",
      );
      fail(
        [step.incrementNs, step.arrivalNs].every(
          (value) => value === null || Number.isFinite(value),
        ),
        "invalid pin delay",
      );
    }
    fail(
      Array.isArray(path.arcs) && path.arcs.length === path.steps.length - 1,
      "ordered arc count disagrees with data pins",
    );
    let logicArcs = 0;
    for (const [index, arc] of path.arcs.entries()) {
      const source = path.steps[index],
        target = path.steps[index + 1];
      fail(
        ["net", "logic"].includes(arc.kind) &&
          arc.source === source.pin &&
          arc.target === target.pin &&
          Number.isFinite(arc.delayNs) &&
          arc.delayNs >= 0 &&
          Number.isFinite(arc.arrivalNs),
        "invalid ordered timing arc",
      );
      if (arc.kind === "logic") {
        logicArcs++;
        fail(source.cell === target.cell, "logic arc crosses native cells");
      } else {
        fail(
          typeof arc.net === "string" &&
            arc.net.length > 0 &&
            Number.isSafeInteger(arc.fanout) &&
            arc.fanout >= 0,
          "invalid timing net arc",
        );
      }
    }
    fail(
      logicArcs === path.logicLevels,
      "logic arcs disagree with logic levels",
    );
    fail(
      typeof path.source === "string" &&
        path.source.slice(0, path.source.lastIndexOf("/")) ===
          path.steps[0].cell &&
        path.launchPin === path.steps[0].pin &&
        path.endpoint === path.steps.at(-1).pin,
      "path endpoints disagree",
    );
  }
  return detail.paths;
}
