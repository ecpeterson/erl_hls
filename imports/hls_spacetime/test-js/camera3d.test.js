import test from "node:test";
import assert from "node:assert/strict";
import {
  createCamera,
  cameraBasis,
  cameraMatrices,
  cameraPreset,
  fitCamera,
  orbitCamera,
  panCamera,
  zoomCamera,
  projectPoint,
  projectSegment,
} from "../web/camera3d.js";

const viewport = { width: 800, height: 600 };
function near(actual, expected, tolerance = 1e-8) {
  assert(Math.abs(actual - expected) < tolerance, `${actual} ≠ ${expected}`);
}
function project(camera, point) {
  return projectPoint(point, cameraMatrices(camera, viewport).matrix, viewport);
}

test("orthographic camera focuses the target and preserves finite orthonormal axes at poles", () => {
  for (const pitch of [-Math.PI, -Math.PI / 2, 0, Math.PI / 2, Math.PI]) {
    const camera = createCamera({ pitch, target: [2, 3, 4] }),
      basis = cameraBasis(camera);
    const at = project(camera, camera.target);
    near(at.x, 400);
    near(at.y, 300);
    assert(at.visible);
    for (const axis of [basis.right, basis.up, basis.back])
      near(Math.hypot(...axis), 1);
    near(
      basis.right.reduce((sum, x, i) => sum + x * basis.up[i], 0),
      0,
    );
    assert([...cameraMatrices(camera, viewport).matrix].every(Number.isFinite));
  }
});

test("orbit changes world depth and roll rotates the screen axes", () => {
  const camera = cameraPreset(createCamera(), "xz"),
    front = [0, 1, 0],
    back = [0, -1, 0];
  assert(project(camera, front).depth < project(camera, back).depth);
  const opposite = orbitCamera(camera, Math.PI, 0);
  assert(project(opposite, front).depth > project(opposite, back).depth);
  const rolled = createCamera({ ...camera, roll: Math.PI / 2 });
  near(project(rolled, [1, 0, 0]).x, 400);
  assert(project(rolled, [1, 0, 0]).y > 300);
});

test("axis presets show chip coordinates and increasing time in the advertised directions", () => {
  const xz = cameraPreset(createCamera(), "xz"),
    yz = cameraPreset(createCamera(), "yz");
  assert(project(xz, [1, 0, 0]).x > 400);
  assert(project(yz, [0, 1, 0]).x > 400);
  assert(project(xz, [0, 0, 1]).y > 300);
  assert(project(yz, [0, 0, 1]).y > 300);
  const chip = cameraPreset(createCamera(), "chip");
  near(project(chip, [0, 0, 1]).x, 400);
  near(project(chip, [0, 0, 1]).y, 300);
  assert(project(chip, [1, 0, 0]).x > 400);
});

test("pan follows CSS-pixel drag and zoom changes extent without moving focus", () => {
  for (const projection of ["orthographic", "perspective"]) {
    const camera = createCamera({ projection }),
      before = project(camera, camera.target),
      moved = project(panCamera(camera, 35, -20, viewport), camera.target);
    near(moved.x - before.x, 35);
    near(moved.y - before.y, -20);
    const next = zoomCamera(camera, 2);
    assert.deepEqual(next.target, camera.target);
    if (projection === "orthographic") near(next.span, camera.span / 2);
    else near(next.distance, camera.distance / 2);
  }
});

test("fit encloses every corner for tall/wide aspect ratios and both projections", () => {
  const bounds = { min: [-2, -1, 0], max: [3, 5, 18] };
  for (const projection of ["orthographic", "perspective"])
    for (const dimensions of [
      { width: 200, height: 900 },
      { width: 1200, height: 200 },
    ]) {
      const camera = fitCamera(
          createCamera({ projection }),
          bounds,
          dimensions,
        ),
        matrix = cameraMatrices(camera, dimensions).matrix;
      for (let bits = 0; bits < 8; bits++) {
        const p = bounds.min.map((v, i) =>
          bits & (1 << i) ? bounds.max[i] : v,
        );
        assert(
          projectPoint(p, matrix, dimensions).visible,
          `${projection}: ${p}`,
        );
      }
    }
  const single = fitCamera(
    createCamera(),
    { min: [1, 1, 1], max: [1, 1, 1] },
    viewport,
  );
  assert(project(single, [1, 1, 1]).visible);
});

test("near/far and lateral clipping match finite point and crossing-segment projections", () => {
  const camera = cameraPreset(
      createCamera({ distance: 6, near: 1, far: 10, span: 4 }),
      "xz",
    ),
    matrix = cameraMatrices(camera, viewport).matrix;
  assert(!projectPoint([0, 5.5, 0], matrix, viewport).visible);
  assert(!projectPoint([0, -5, 0], matrix, viewport).visible);
  assert.equal(projectSegment([20, 0, 0], [30, 0, 0], matrix, viewport), null);
  const crossing = projectSegment([-10, 0, 0], [10, 0, 0], matrix, viewport);
  assert(crossing);
  near(crossing[0].x, 0);
  near(crossing[1].x, 800);
  assert(crossing.every((p) => p.visible && Number.isFinite(p.depth)));
  const perspective = createCamera({ ...camera, projection: "perspective" }),
    pm = cameraMatrices(perspective, viewport).matrix,
    eye = cameraBasis(perspective).eye;
  const atEye = projectPoint(eye, pm, viewport);
  assert(!atEye.visible);
  assert([atEye.x, atEye.y, atEye.depth].every(Number.isFinite));
  const nearCrossing = projectSegment([0, 5.5, 0], [0, 0, 0], pm, viewport);
  assert(nearCrossing);
  near(nearCrossing[0].depth, 0);
});

test("invalid coordinates and camera parameters reject instead of producing NaN overlays", () => {
  for (const patch of [
    { target: [0, NaN, 0] },
    { span: 0 },
    { far: 0.001 },
    { projection: "flat" },
    { fov: Math.PI },
  ])
    assert.throws(() => createCamera(patch), /3D camera/);
  const camera = createCamera();
  assert.throws(() => zoomCamera(camera, 0), /zoom/);
  assert.throws(
    () => fitCamera(camera, { min: [1, 0, 0], max: [0, 0, 0] }, viewport),
    /reversed/,
  );
  assert.throws(
    () => cameraMatrices(camera, { width: 0, height: 1 }),
    /viewport/,
  );
  assert.throws(() => project(camera, [Infinity, 0, 0]), /finite/);
});
