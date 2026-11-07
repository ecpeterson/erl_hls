import test from "node:test";
import assert from "node:assert/strict";
import { packScene, createScene3D } from "../web/scene3d.js";

test("scene packing retains every finite prism/marker, reports degeneracy and uses opaque RGB", () => {
  const packed = packScene({
    segments: [
      { from: [0, 0, 0], to: [1, 0, 0], radius: 0.1, color: "#f80" },
      { from: [1, 2, 3], to: [1, 2, 3], color: "#ffffff" },
    ],
    markers: [{ position: [0, 0, 2], size: 0.4, color: [0.1, 0.2, 0.3] }],
    surfaces: [
      {
        vertices: [
          [0, 0, 0],
          [1, 0, 0],
          [1, 1, 0],
          [0, 1, 0],
        ],
        color: "#123456",
      },
    ],
  });
  assert.deepEqual(packed.counts, {
    segments: 1,
    markers: 1,
    surfaceTriangles: 2,
    zeroSegments: 1,
    degenerateTriangles: 0,
  });
  assert.equal(packed.instances.length, 28);
  assert.equal(packed.surfaces.length, 54);
  assert.equal(packed.instances[10], 0);
  assert.equal(packed.instances[24], 1);
  assert.deepEqual(packed.bounds, {
    min: [-0.2, -0.2, -0.1],
    max: [1.1, 1, 2.2],
  });
  assert.equal(packed.instances[6], 1);
  assert(Math.abs(packed.instances[7] - 136 / 255) < 1e-7);
});

test("endpoint tinting preserves one instance per segment and leaves markers uniform", () => {
  const packed = packScene({
    segments: [
      { from: [0, 0, 0], to: [0, 0, 2], color: "#f00", colorEnd: "#00f" },
      { from: [0, 0, 2], to: [1, 0, 2], color: "#0f0" },
    ],
    markers: [{ position: [0, 0, 0], color: "#ff0", colorEnd: "#00f" }],
  });
  const instances = [...packed.instances];
  assert.equal(packed.counts.segments, 2);
  assert.equal(packed.counts.markers, 1);
  assert.equal(instances.length, 42);
  assert.deepEqual(instances.slice(6, 9), [1, 0, 0]);
  assert.deepEqual(instances.slice(11, 14), [0, 0, 1]);
  assert.deepEqual(instances.slice(20, 23), [0, 1, 0]);
  assert.deepEqual(instances.slice(25, 28), [0, 1, 0]);
  assert.deepEqual(instances.slice(34, 37), [1, 1, 0]);
  assert.deepEqual(instances.slice(39, 42), [1, 1, 0]);
});

test("malformed or imprecise geometry rejects rather than silently uploading NaNs", () => {
  for (const segment of [
    { from: [NaN, 0, 0], to: [1, 0, 0] },
    { from: [0, 0, 0], to: [Infinity, 0, 0] },
    { from: [0, 0, 0], to: [1, 0, 0], radius: -1 },
    { from: [0, 0, 0], to: [1, 0, 0], color: [1, 0, 0, 0.5] },
    { from: [0, 0, 0], to: [1, 0, 0], colorEnd: [NaN, 0, 1] },
    { from: [0, 0, 0], to: [1, 0, 0], colorEnd: [1, 0, 0, 0.5] },
    { from: [1e10, 0, 0], to: [1e10 + 1, 0, 0] },
  ])
    assert.throws(() => packScene({ segments: [segment] }), /3D scene/);
  assert.equal(packScene({}).bounds, null);
});

/** This mock checks renderer lifecycle/command reuse only, not native GPU pixels. */
function mockCanvas() {
  const calls = [],
    listeners = new Map();
  const special = {
    getShaderParameter: () => true,
    getProgramParameter: () => true,
    getUniformLocation: () => ({}),
    getError: () => 0,
    getParameter: () => 4096,
    getShaderInfoLog: () => "",
    getProgramInfoLog: () => "",
  };
  const gl = new Proxy(
    { NO_ERROR: 0 },
    {
      get(target, key) {
        if (key in target) return target[key];
        if (key in special) return special[key];
        if (/^[A-Z_]+$/.test(key)) return (target[key] = key);
        return (target[key] = (...args) => {
          calls.push([key, ...args]);
          return key.startsWith("create") ? {} : undefined;
        });
      },
    },
  );
  return {
    calls,
    listeners,
    canvas: {
      clientWidth: 800,
      clientHeight: 600,
      width: 800,
      height: 600,
      getContext: () => gl,
      addEventListener: (name, callback) => listeners.set(name, callback),
      removeEventListener: (name) => listeners.delete(name),
    },
  };
}

test("camera-only frames reuse uploads and retain a depth-tested instanced draw", () => {
  const { canvas, calls } = mockCanvas(),
    renderer = createScene3D(canvas),
    scene = { segments: [{ from: [0, 0, 0], to: [1, 0, 1] }] };
  renderer.setScene(scene);
  renderer.fit();
  renderer.render({ width: 800, height: 600, pixelRatio: 2 });
  const uploads = calls.filter(([name]) => name === "bufferData").length;
  renderer.orbit(0.2, 0.3);
  renderer.pan(10, 20);
  renderer.zoom(1.2);
  renderer.render({ shading: false });
  renderer.setScene(scene);
  assert.equal(calls.filter(([name]) => name === "bufferData").length, uploads);
  assert(
    calls.some(([name, state]) => name === "enable" && state === "DEPTH_TEST"),
  );
  assert(
    calls.some(([name, state]) => name === "disable" && state === "BLEND"),
  );
  assert.equal(
    calls.filter(([name]) => name === "drawElementsInstanced").length,
    2,
  );
  assert.deepEqual(
    calls.filter(([name]) => name === "uniform1f").map((call) => call[2]),
    [1, 0],
  );
  const camera = renderer.getCamera();
  camera.target[0] = 999;
  assert.notEqual(renderer.getCamera().target[0], 999);
  assert.equal(canvas.width, 800); // Second frame uses the default DPR=1 in Node.
  renderer.dispose();
  assert.throws(() => renderer.render(), /disposed/);
});

test("endpoint colors reach the instanced GPU attribute without splitting geometry", () => {
  const { canvas, calls } = mockCanvas(),
    renderer = createScene3D(canvas);
  renderer.setScene({
    segments: [
      { from: [0, 0, 0], to: [1, 2, 3], color: "#f00", colorEnd: "#00f" },
    ],
    markers: [{ position: [1, 2, 3], color: "#00f" }],
  });
  renderer.render();
  assert.deepEqual(
    calls.filter(
      ([name, location]) => name === "vertexAttribPointer" && location === 7,
    ),
    [["vertexAttribPointer", 7, 3, "FLOAT", false, 56, 44]],
  );
  assert(
    calls.some(
      ([name, location, divisor]) =>
        name === "vertexAttribDivisor" && location === 7 && divisor === 1,
    ),
  );
  assert.deepEqual(
    calls.filter(([name]) => name === "drawElementsInstanced"),
    [["drawElementsInstanced", "TRIANGLES", 36, "UNSIGNED_SHORT", 0, 2]],
  );
  renderer.dispose();
});

test("unsupported contexts are explicit and context restoration reuploads the retained scene", () => {
  const notices = [];
  assert.equal(
    createScene3D(
      { getContext: () => null },
      { onUnsupported: (message) => notices.push(message) },
    ),
    null,
  );
  assert.match(notices[0], /WebGL2/);
  const { canvas, calls, listeners } = mockCanvas();
  const renderer = createScene3D(canvas, {
    onContextLost: (message) => notices.push(message),
  });
  renderer.setScene({ markers: [{ position: [0, 0, 0] }] });
  let prevented = false;
  listeners.get("webglcontextlost")({
    preventDefault() {
      prevented = true;
    },
  });
  assert(prevented);
  assert.equal(renderer.render(), false);
  const uploads = calls.filter(([name]) => name === "bufferData").length;
  listeners.get("webglcontextrestored")();
  assert(calls.filter(([name]) => name === "bufferData").length > uploads);
  assert.equal(renderer.render(), true);
  renderer.dispose();
  assert.equal(listeners.size, 0);
});
