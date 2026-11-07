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
      ["source", "rtl", "observation"].every(
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
  for (const path of detail.paths) {
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
