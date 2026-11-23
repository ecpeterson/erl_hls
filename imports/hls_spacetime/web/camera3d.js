/** Camera mathematics shared by GPU geometry and the CSS-pixel label/hit overlay.
 * World x/y are chip coordinates; increasing z is later time. Orthographic
 * projection is the default. Screen visibility means frustum inclusion, not
 * absence of occlusion by another primitive. */
const TAU = Math.PI * 2;
const EPSILON = 1e-9;
const DEFAULTS = {
  target: [0, 0, 0],
  yaw: Math.PI / 4,
  pitch: Math.PI / 5,
  roll: 0,
  distance: 6,
  span: 4,
  projection: "orthographic",
  fov: Math.PI / 4,
  near: 0.01,
  far: 1000,
};

/** Reject nonfinite inputs before they enter projection matrices. */
function requireValue(condition, message) {
  if (!condition) throw Error(`3D camera: ${message}`);
}
function vector(value) {
  requireValue(
    (Array.isArray(value) || ArrayBuffer.isView(value)) &&
      value.length === 3 &&
      [...value].every(Number.isFinite),
    "expected a finite three-coordinate point",
  );
  return [...value];
}
function dot(a, b) {
  return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}
function add(a, b) {
  return a.map((v, i) => v + b[i]);
}
function scale(a, factor) {
  return a.map((v) => v * factor);
}
function angle(value) {
  return ((((value + Math.PI) % TAU) + TAU) % TAU) - Math.PI;
}
function dimensions(viewport) {
  requireValue(
    Number.isFinite(viewport?.width) &&
      viewport.width > 0 &&
      Number.isFinite(viewport.height) &&
      viewport.height > 0,
    "invalid viewport",
  );
  return viewport.width / viewport.height;
}

/** Return an independent validated camera. Angles are radians, span is the full
 * orthographic vertical extent, and perspective fov is the vertical angle. */
export function createCamera(options = {}) {
  const camera = {
    ...DEFAULTS,
    ...options,
    target: vector(options.target ?? DEFAULTS.target),
  };
  for (const key of [
    "yaw",
    "pitch",
    "roll",
    "distance",
    "span",
    "fov",
    "near",
    "far",
  ])
    requireValue(Number.isFinite(camera[key]), `nonfinite ${key}`);
  requireValue(
    camera.distance > 0 &&
      camera.span > 0 &&
      camera.near > 0 &&
      camera.far > camera.near,
    "distance, span and clipping planes must be positive and ordered",
  );
  requireValue(
    camera.fov > 0 && camera.fov < Math.PI,
    "fov must be between zero and pi",
  );
  requireValue(
    ["orthographic", "perspective"].includes(camera.projection),
    "unknown projection",
  );
  for (const key of ["yaw", "pitch", "roll"]) camera[key] = angle(camera[key]);
  return camera;
}

/** Analytic orthonormal axes remain defined at the chip-view poles. Orbit
 * rotates in three-dimensional space; roll permits independent view rotation. */
export function cameraBasis(camera) {
  const cy = Math.cos(camera.yaw),
    sy = Math.sin(camera.yaw),
    cp = Math.cos(camera.pitch),
    sp = Math.sin(camera.pitch),
    cr = Math.cos(camera.roll),
    sr = Math.sin(camera.roll);
  const right = [sy, -cy, 0],
    up = [-sp * cy, -sp * sy, -cp],
    back = [cp * cy, cp * sy, -sp];
  return {
    right: add(scale(right, cr), scale(up, sr)),
    up: add(scale(up, cr), scale(right, -sr)),
    back,
    eye: add(camera.target, scale(back, camera.distance)),
  };
}

/** Named axis views preserve focus/scale; callers may fit again after changing
 * orientation. In xz/yz views time increases downward on the screen. */
export function cameraPreset(camera, name) {
  const orientations = {
    isometric: { yaw: Math.PI / 4, pitch: Math.PI / 5, roll: 0 },
    chip: { yaw: Math.PI / 2, pitch: Math.PI / 2, roll: 0 },
    xz: { yaw: Math.PI / 2, pitch: 0, roll: 0 },
    yz: { yaw: Math.PI, pitch: 0, roll: 0 },
  };
  requireValue(orientations[name], `unknown preset ${name}`);
  return createCamera({ ...camera, ...orientations[name] });
}

/** Drag angles rotate around time and a chip-plane axis, including pole crossings. */
export function orbitCamera(camera, horizontal, vertical) {
  requireValue(
    Number.isFinite(horizontal) && Number.isFinite(vertical),
    "invalid orbit delta",
  );
  return createCamera({
    ...camera,
    yaw: camera.yaw + horizontal,
    pitch: camera.pitch + vertical,
  });
}

/** Move focus opposite the screen drag so geometry follows the pointer. */
export function panCamera(camera, dx, dy, viewport) {
  dimensions(viewport);
  requireValue(Number.isFinite(dx) && Number.isFinite(dy), "invalid pan delta");
  const { right, up } = cameraBasis(camera),
    extent =
      camera.projection === "orthographic"
        ? camera.span
        : 2 * camera.distance * Math.tan(camera.fov / 2),
    unit = extent / viewport.height;
  return createCamera({
    ...camera,
    target: add(
      camera.target,
      add(scale(right, -dx * unit), scale(up, dy * unit)),
    ),
  });
}

/** A factor above one magnifies. Finite bounds avoid zero-scale matrices after
 * long wheel gestures; these constrain the camera, never the scene population. */
export function zoomCamera(camera, factor) {
  requireValue(Number.isFinite(factor) && factor > 0, "invalid zoom factor");
  const key = camera.projection === "orthographic" ? "span" : "distance";
  return createCamera({
    ...camera,
    [key]: Math.max(1e-6, Math.min(1e12, camera[key] / factor)),
  });
}

/** Fit every bound corner in the current orientation, accounting for viewport
 * aspect ratio. Bounds have {min:[x,y,z], max:[x,y,z]}; degenerate bounds are valid. */
export function fitCamera(camera, bounds, viewport, { padding = 1.12 } = {}) {
  const aspect = dimensions(viewport),
    min = vector(bounds?.min),
    max = vector(bounds?.max);
  requireValue(
    min.every((v, i) => v <= max[i]),
    "reversed bounds",
  );
  requireValue(Number.isFinite(padding) && padding >= 1, "invalid fit padding");
  const target = min.map((v, i) => v / 2 + max[i] / 2),
    half = max.map((v, i) => (v - min[i]) / 2),
    radius = Math.max(1e-3, Math.hypot(...half)),
    { right, up, back } = cameraBasis(camera);
  let horizontal = 0,
    vertical = 0,
    distance = radius * 3;
  if (camera.projection === "perspective") distance = radius + 1e-3;
  for (let corner = 0; corner < 8; corner++) {
    const p = half.map((v, i) => (corner & (1 << i) ? v : -v)),
      x = Math.abs(dot(p, right)),
      y = Math.abs(dot(p, up)),
      z = dot(p, back);
    horizontal = Math.max(horizontal, x);
    vertical = Math.max(vertical, y);
    if (camera.projection === "perspective")
      distance = Math.max(
        distance,
        z + (padding * y) / Math.tan(camera.fov / 2),
        z + (padding * x) / (Math.tan(camera.fov / 2) * aspect),
      );
  }
  return createCamera({
    ...camera,
    target,
    distance,
    span: Math.max(1e-3, 2 * padding * Math.max(vertical, horizontal / aspect)),
    near: Math.max(1e-6, radius * 1e-4),
    far: distance + radius * 2 + 1,
  });
}

/** Column-major multiplication matches WebGL uniform matrices. */
function multiply(a, b) {
  const result = new Float64Array(16);
  for (let column = 0; column < 4; column++)
    for (let row = 0; row < 4; row++)
      for (let k = 0; k < 4; k++)
        result[column * 4 + row] += a[k * 4 + row] * b[column * 4 + k];
  return result;
}

/** Build the exact view-projection matrix used by GPU drawing and overlays. */
export function cameraMatrices(camera, viewport) {
  const aspect = dimensions(viewport),
    { right: r, up: u, back: b, eye } = cameraBasis(camera),
    view = new Float64Array([
      r[0],
      u[0],
      b[0],
      0,
      r[1],
      u[1],
      b[1],
      0,
      r[2],
      u[2],
      b[2],
      0,
      -dot(r, eye),
      -dot(u, eye),
      -dot(b, eye),
      1,
    ]);
  const n = camera.near,
    f = camera.far;
  let projection;
  if (camera.projection === "orthographic")
    projection = new Float64Array([
      2 / (camera.span * aspect),
      0,
      0,
      0,
      0,
      2 / camera.span,
      0,
      0,
      0,
      0,
      -2 / (f - n),
      0,
      0,
      0,
      -(f + n) / (f - n),
      1,
    ]);
  else {
    const s = 1 / Math.tan(camera.fov / 2);
    projection = new Float64Array([
      s / aspect,
      0,
      0,
      0,
      0,
      s,
      0,
      0,
      0,
      0,
      (f + n) / (n - f),
      -1,
      0,
      0,
      (2 * f * n) / (n - f),
      0,
    ]);
  }
  const matrix = multiply(projection, view);
  requireValue(
    [...matrix].every((v) => Number.isFinite(Math.fround(v))),
    "matrix exceeds GPU coordinate range",
  );
  return { matrix, view, projection, eye, right: r, up: u, back: b };
}

/** Homogeneous coordinates preserve near-plane clipping before division. */
function clipPoint(world, matrix) {
  const p = [...vector(world), 1];
  return [0, 1, 2, 3].map((row) =>
    p.reduce((sum, v, column) => sum + matrix[column * 4 + row] * v, 0),
  );
}
function screen(clip, viewport) {
  const w = clip[3];
  if (!(w > EPSILON)) return { x: 0, y: 0, depth: 1, visible: false };
  const [x, y, z] = clip.slice(0, 3).map((v) => v / w);
  return {
    x: ((x + 1) * viewport.width) / 2,
    y: ((1 - y) * viewport.height) / 2,
    depth: (z + 1) / 2,
    visible: [x, y, z].every(
      (v) => Number.isFinite(v) && v >= -1 - EPSILON && v <= 1 + EPSILON,
    ),
  };
}

/** Project to CSS pixels and normalized depth. Invisible points must not be used
 * as overlay hits; projective points at/behind the eye return finite sentinels. */
export function projectPoint(world, matrix, viewport) {
  dimensions(viewport);
  return screen(clipPoint(world, matrix), viewport);
}

/** Clip a segment against all six homogeneous frustum planes. Return null when
 * wholly outside, otherwise CSS-pixel endpoints matching the GPU's clipped span. */
export function projectSegment(from, to, matrix, viewport) {
  dimensions(viewport);
  const a = clipPoint(from, matrix),
    b = clipPoint(to, matrix);
  let first = 0,
    last = 1;
  for (const [axis, sign] of [
    [0, 1],
    [0, -1],
    [1, 1],
    [1, -1],
    [2, 1],
    [2, -1],
  ]) {
    const av = a[3] + sign * a[axis],
      bv = b[3] + sign * b[axis];
    if (av < 0 && bv < 0) return null;
    if (av < 0 || bv < 0) {
      const crossing = av / (av - bv);
      if (av < 0) first = Math.max(first, crossing);
      else last = Math.min(last, crossing);
    }
  }
  if (first > last) return null;
  const interpolate = (t) => a.map((v, i) => v + t * (b[i] - v));
  const start = interpolate(first),
    end = interpolate(last);
  if (start[3] <= EPSILON || end[3] <= EPSILON) return null;
  return [screen(start, viewport), screen(end, viewport)];
}
