import {
  createCamera,
  cameraMatrices,
  cameraPreset,
  fitCamera,
  orbitCamera,
  panCamera,
  zoomCamera,
  projectPoint,
  projectSegment,
} from "./camera3d.js";

/** Opaque, depth-tested geometry for a chip/time scene. A segment is an actual
 * four-sided prism, not a screen-space line. Geometry uploads are independent of
 * camera motion; instances share one indexed cube mesh and one draw call. */
const STRIDE = 14;
const MAX_BUFFER_BYTES = 256 * 1024 * 1024;
const DEFAULT_COLOR = "#67d7c3";

function requireValue(condition, reason) {
  if (!condition) throw Error(`3D scene: ${reason}`);
}
/** WebGL positions are float32; reject overflow before allocating GPU buffers. */
function point(value) {
  requireValue(
    (Array.isArray(value) || ArrayBuffer.isView(value)) &&
      value.length === 3 &&
      [...value].every(
        (v) => Number.isFinite(v) && Number.isFinite(Math.fround(v)),
      ),
    "expected three finite GPU coordinates",
  );
  return value;
}
/** RGB only: translucent line accumulation is deliberately not a rendering mode. */
function rgb(value = DEFAULT_COLOR) {
  if (typeof value === "string") {
    requireValue(
      /^#[0-9a-f]{3}([0-9a-f]{3})?$/i.test(value),
      "color must be #rgb, #rrggbb or normalized RGB",
    );
    const hex =
      value.length === 4
        ? [...value.slice(1)].map((c) => c + c).join("")
        : value.slice(1);
    return [0, 2, 4].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255);
  }
  requireValue(
    (Array.isArray(value) || ArrayBuffer.isView(value)) &&
      value.length === 3 &&
      [...value].every((v) => Number.isFinite(v) && v >= 0 && v <= 1),
    "color must be normalized opaque RGB",
  );
  return value;
}
function positive(value, label) {
  requireValue(
    Number.isFinite(value) && value > 0 && Number.isFinite(Math.fround(value)),
    `invalid ${label}`,
  );
  return value;
}
function normal(a, b, c) {
  const u = b.map((v, i) => v - a[i]),
    v = c.map((x, i) => x - a[i]),
    n = [
      u[1] * v[2] - u[2] * v[1],
      u[2] * v[0] - u[0] * v[2],
      u[0] * v[1] - u[1] * v[0],
    ],
    length = Math.hypot(...n);
  return length ? n.map((x) => x / length) : null;
}

/** Pack an immutable scene without clipping, sampling or retaining per-camera
 * copies. Segment color/colorEnd tint the source/destination of one prism;
 * omitted colorEnd keeps a uniform color. Markers always use one color.
 * Zero-length segments/degenerate triangles are counted and omitted.
 * Memory overflow rejects the whole upload; it never silently drops a prefix. */
export function packScene(scene) {
  requireValue(scene && typeof scene === "object", "missing scene");
  const segments = scene.segments ?? [],
    markers = scene.markers ?? [],
    surfaces = scene.surfaces ?? [];
  for (const rows of [segments, markers, surfaces])
    requireValue(Array.isArray(rows), "primitive list must be an array");
  const bytes =
    (segments.length + markers.length) * STRIDE * 4 +
    surfaces.length * 6 * 9 * 4;
  requireValue(
    Number.isSafeInteger(bytes) && bytes <= MAX_BUFFER_BYTES,
    "geometry buffer exceeds 256 MiB; reduce the displayed clock window",
  );
  const instances = new Float32Array(
      (segments.length + markers.length) * STRIDE,
    ),
    triangles = new Float32Array(surfaces.length * 6 * 9),
    colors = new Map();
  const bounds = {
    min: [Infinity, Infinity, Infinity],
    max: [-Infinity, -Infinity, -Infinity],
  };
  const counts = {
    segments: 0,
    markers: 0,
    surfaceTriangles: 0,
    zeroSegments: 0,
    degenerateTriangles: 0,
  };
  let offset = 0,
    surfaceOffset = 0;
  const color = (value = DEFAULT_COLOR) => {
    if (typeof value !== "string") return rgb(value);
    if (!colors.has(value)) colors.set(value, rgb(value));
    return colors.get(value);
  };
  const extend = (p, radius = 0) => {
    for (let i = 0; i < 3; i++) {
      bounds.min[i] = Math.min(bounds.min[i], p[i] - radius);
      bounds.max[i] = Math.max(bounds.max[i], p[i] + radius);
    }
  };
  const instance = (from, to, tint, endTint, radius, shape) => {
    instances.set(from, offset);
    instances.set(to, offset + 3);
    instances.set(tint, offset + 6);
    instances[offset + 9] = radius;
    instances[offset + 10] = shape;
    instances.set(endTint, offset + 11);
    offset += STRIDE;
  };
  for (const item of segments) {
    const from = point(item.from),
      to = point(item.to),
      tint = color(item.color),
      endTint = item.colorEnd === undefined ? tint : color(item.colorEnd),
      radius = positive(item.radius ?? 0.002, "segment radius");
    if (from.every((v, i) => v === to[i])) {
      counts.zeroSegments++;
      continue;
    }
    requireValue(
      from.some((v, i) => Math.fround(v) !== Math.fround(to[i])),
      "segment collapses at GPU precision; normalize world coordinates",
    );
    instance(from, to, tint, endTint, radius, 0);
    extend(from, radius);
    extend(to, radius);
    counts.segments++;
  }
  for (const item of markers) {
    const p = point(item.position),
      tint = color(item.color),
      radius = positive(item.size ?? 0.012, "marker size") / 2;
    instance(p, p, tint, tint, radius, 1);
    extend(p, radius);
    counts.markers++;
  }
  for (const item of surfaces) {
    requireValue(
      Array.isArray(item.vertices) && [3, 4].includes(item.vertices.length),
      "surface requires three or four vertices",
    );
    const vertices = item.vertices.map(point),
      tint = color(item.color);
    for (let j = 1; j < vertices.length - 1; j++) {
      const points = [vertices[0], vertices[j], vertices[j + 1]],
        n = normal(...points);
      if (!n) {
        counts.degenerateTriangles++;
        continue;
      }
      for (const p of points) {
        triangles.set(p, surfaceOffset);
        triangles.set(n, surfaceOffset + 3);
        triangles.set(tint, surfaceOffset + 6);
        surfaceOffset += 9;
        extend(p);
      }
      counts.surfaceTriangles++;
    }
  }
  return {
    instances: instances.subarray(0, offset),
    surfaces: triangles.subarray(0, surfaceOffset),
    counts,
    bounds: bounds.min[0] === Infinity ? null : bounds,
    bytes: offset * 4 + surfaceOffset * 4,
  };
}

const INSTANCE_VERTEX = `#version 300 es
precision highp float;
layout(location=0) in vec3 aPosition;
layout(location=1) in vec3 aNormal;
layout(location=2) in vec3 aStart;
layout(location=3) in vec3 aEnd;
layout(location=4) in vec3 aColor;
layout(location=5) in float aRadius;
layout(location=6) in float aShape;
layout(location=7) in vec3 aColorEnd;
uniform mat4 uMatrix;
out vec3 vColor;
out vec3 vNormal;
void main() {
  vec3 world;
  if (aShape > 0.5) {
    world = aStart + aPosition * aRadius;
    vNormal = aNormal;
  } else {
    vec3 delta = aEnd - aStart;
    float extent = length(delta);
    vec3 forward = delta / extent;
    vec3 reference = abs(forward.z) < 0.9 ? vec3(0,0,1) : vec3(0,1,0);
    vec3 side = normalize(cross(forward, reference));
    vec3 other = cross(forward, side);
    world = (aStart + aEnd) * 0.5 + side * (aPosition.x * aRadius)
      + other * (aPosition.y * aRadius) + forward * (aPosition.z * extent * 0.5);
    vNormal = side * aNormal.x + other * aNormal.y + forward * aNormal.z;
  }
  vColor = aShape > 0.5 ? aColor
    : mix(aColor, aColorEnd, (aPosition.z + 1.0) * 0.5);
  gl_Position = uMatrix * vec4(world, 1);
}`;
const SURFACE_VERTEX = `#version 300 es
precision highp float;
layout(location=0) in vec3 aPosition;
layout(location=1) in vec3 aNormal;
layout(location=2) in vec3 aColor;
uniform mat4 uMatrix;
out vec3 vColor;
out vec3 vNormal;
void main() { vColor = aColor; vNormal = aNormal; gl_Position = uMatrix * vec4(aPosition, 1); }`;
const FRAGMENT = `#version 300 es
precision highp float;
in vec3 vColor;
in vec3 vNormal;
uniform float uShading;
out vec4 outColor;
void main() {
  float light = 0.76 + 0.24 * abs(dot(normalize(vNormal), normalize(vec3(0.4,0.7,-0.6))));
  outColor = vec4(vColor * mix(1.0, light, uShading), 1);
}`;

/** Face-local normals give opaque prisms legible shape without a large tube mesh. */
function cubeMesh() {
  const vertices = [],
    indices = [];
  for (const [n, corners] of [
    [
      [1, 0, 0],
      [
        [1, -1, -1],
        [1, 1, -1],
        [1, 1, 1],
        [1, -1, 1],
      ],
    ],
    [
      [-1, 0, 0],
      [
        [-1, -1, 1],
        [-1, 1, 1],
        [-1, 1, -1],
        [-1, -1, -1],
      ],
    ],
    [
      [0, 1, 0],
      [
        [-1, 1, -1],
        [-1, 1, 1],
        [1, 1, 1],
        [1, 1, -1],
      ],
    ],
    [
      [0, -1, 0],
      [
        [-1, -1, 1],
        [-1, -1, -1],
        [1, -1, -1],
        [1, -1, 1],
      ],
    ],
    [
      [0, 0, 1],
      [
        [-1, -1, 1],
        [1, -1, 1],
        [1, 1, 1],
        [-1, 1, 1],
      ],
    ],
    [
      [0, 0, -1],
      [
        [1, -1, -1],
        [-1, -1, -1],
        [-1, 1, -1],
        [1, 1, -1],
      ],
    ],
  ]) {
    const first = vertices.length / 6;
    for (const p of corners) vertices.push(...p, ...n);
    indices.push(first, first + 1, first + 2, first, first + 2, first + 3);
  }
  return {
    vertices: new Float32Array(vertices),
    indices: new Uint16Array(indices),
  };
}

/** Compile/link errors surface to the caller instead of replacing 3D with a
 * projection that merely resembles it. Shader strings are static source. */
function program(gl, vertex) {
  const shaders = [],
    result = gl.createProgram();
  requireValue(result, "GPU program allocation failed");
  try {
    for (const [type, source] of [
      [gl.VERTEX_SHADER, vertex],
      [gl.FRAGMENT_SHADER, FRAGMENT],
    ]) {
      const shader = gl.createShader(type);
      requireValue(shader, "GPU shader allocation failed");
      shaders.push(shader);
      gl.shaderSource(shader, source);
      gl.compileShader(shader);
      requireValue(
        gl.getShaderParameter(shader, gl.COMPILE_STATUS),
        gl.getShaderInfoLog(shader) || "shader compilation failed",
      );
      gl.attachShader(result, shader);
    }
    gl.linkProgram(result);
    requireValue(
      gl.getProgramParameter(result, gl.LINK_STATUS),
      gl.getProgramInfoLog(result) || "shader linking failed",
    );
    return {
      handle: result,
      matrix: gl.getUniformLocation(result, "uMatrix"),
      shading: gl.getUniformLocation(result, "uShading"),
    };
  } catch (error) {
    gl.deleteProgram(result);
    throw error;
  } finally {
    for (const shader of shaders) gl.deleteShader(shader);
  }
}

/** Build reusable VAOs/buffers. Only scene changes replace buffer contents. */
function resources(gl) {
  const programs = [],
    buffers = [],
    vaos = [];
  const allocated = (value, list) => {
    requireValue(value, "GPU allocation failed");
    list.push(value);
    return value;
  };
  const buffer = () => allocated(gl.createBuffer(), buffers),
    vao = () => allocated(gl.createVertexArray(), vaos);
  const attribute = (location, count, stride, offset, divisor = 0) => {
    gl.enableVertexAttribArray(location);
    gl.vertexAttribPointer(location, count, gl.FLOAT, false, stride, offset);
    gl.vertexAttribDivisor(location, divisor);
  };
  const dispose = () => {
    for (const item of buffers) gl.deleteBuffer(item);
    for (const item of vaos) gl.deleteVertexArray(item);
    for (const item of programs) gl.deleteProgram(item.handle);
  };
  try {
    const instanceProgram = program(gl, INSTANCE_VERTEX);
    programs.push(instanceProgram);
    const surfaceProgram = program(gl, SURFACE_VERTEX);
    programs.push(surfaceProgram);
    const instanceVao = vao(),
      mesh = cubeMesh(),
      meshBuffer = buffer(),
      elementBuffer = buffer(),
      instanceBuffer = buffer();
    gl.bindVertexArray(instanceVao);
    gl.bindBuffer(gl.ARRAY_BUFFER, meshBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, mesh.vertices, gl.STATIC_DRAW);
    attribute(0, 3, 24, 0);
    attribute(1, 3, 24, 12);
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, elementBuffer);
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, mesh.indices, gl.STATIC_DRAW);
    gl.bindBuffer(gl.ARRAY_BUFFER, instanceBuffer);
    for (const [location, size, offset] of [
      [2, 3, 0],
      [3, 3, 3],
      [4, 3, 6],
      [5, 1, 9],
      [6, 1, 10],
      [7, 3, 11],
    ])
      attribute(location, size, STRIDE * 4, offset * 4, 1);
    const surfaceVao = vao(),
      surfaceBuffer = buffer();
    gl.bindVertexArray(surfaceVao);
    gl.bindBuffer(gl.ARRAY_BUFFER, surfaceBuffer);
    attribute(0, 3, 36, 0);
    attribute(1, 3, 36, 12);
    attribute(2, 3, 36, 24);
    gl.bindVertexArray(null);
    return {
      instanceProgram,
      surfaceProgram,
      instanceVao,
      surfaceVao,
      instanceBuffer,
      surfaceBuffer,
      dispose,
    };
  } catch (error) {
    dispose();
    throw error;
  }
}

/** Create a real WebGL2 scene or return null and notify onUnsupported. The caller
 * owns gestures and a separate overlay canvas. Colors are opaque RGB; geometry
 * is immutable between setScene calls. No browser/npm dependency is required. */
export function createScene3D(
  canvas,
  {
    camera: initialCamera = {},
    background = "#0b1117",
    onUnsupported = () => {},
    onContextLost = () => {},
    onContextRestored = () => {},
  } = {},
) {
  const validatedCamera = createCamera(initialCamera),
    clear = rgb(background),
    initialViewport = {
      width: canvas.clientWidth || 1,
      height: canvas.clientHeight || 1,
    },
    initialMatrices = cameraMatrices(validatedCamera, initialViewport);
  let gl, gpu;
  try {
    gl = canvas.getContext("webgl2", {
      alpha: false,
      antialias: true,
      depth: true,
      premultipliedAlpha: false,
    });
    if (!gl)
      throw Error("WebGL2 is unavailable; the 3D scene cannot be displayed.");
    gpu = resources(gl);
  } catch (error) {
    onUnsupported(error.message);
    return null;
  }
  let camera = validatedCamera,
    viewport = initialViewport,
    matrices = initialMatrices,
    scene = null,
    packed = packScene({}),
    lost = false,
    disposed = false,
    lastFit = null;
  const assertLive = () => requireValue(!disposed, "renderer was disposed");
  const update = (next) => {
    camera = next;
    matrices = cameraMatrices(camera, viewport);
    return createCamera(camera);
  };
  const upload = () => {
    gl.bindBuffer(gl.ARRAY_BUFFER, gpu.instanceBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, packed.instances, gl.STATIC_DRAW);
    gl.bindBuffer(gl.ARRAY_BUFFER, gpu.surfaceBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, packed.surfaces, gl.STATIC_DRAW);
    const error = gl.getError();
    requireValue(error === gl.NO_ERROR, `GPU upload failed (${error})`);
  };
  const lose = (event) => {
    event.preventDefault();
    lost = true;
    onContextLost(
      "The GPU context was lost. The saved scene remains retained; rendering will resume if the context is restored.",
    );
  };
  const restore = () => {
    if (disposed) return;
    try {
      gpu = resources(gl);
      lost = false;
      upload();
      onContextRestored();
    } catch (error) {
      lost = true;
      onUnsupported(`GPU restoration failed: ${error.message}`);
    }
  };
  canvas.addEventListener("webglcontextlost", lose);
  canvas.addEventListener("webglcontextrestored", restore);
  return {
    /** Upload only a changed immutable scene object; camera movement never calls this. */
    setScene(next) {
      assertLive();
      if (scene !== next) {
        const prepared = packScene(next);
        packed = prepared;
        scene = next;
        if (!lost) upload();
      }
      return { ...packed.counts, bytes: packed.bytes, bounds: packed.bounds };
    },
    getCamera() {
      return createCamera(camera);
    },
    setCamera(patch) {
      assertLive();
      return update(createCamera({ ...camera, ...patch }));
    },
    orbit(horizontal, vertical) {
      assertLive();
      return update(orbitCamera(camera, horizontal, vertical));
    },
    pan(dx, dy) {
      assertLive();
      return update(panCamera(camera, dx, dy, viewport));
    },
    zoom(factor) {
      assertLive();
      return update(zoomCamera(camera, factor));
    },
    fit(bounds = packed.bounds, options = {}) {
      assertLive();
      if (!bounds) return createCamera(camera);
      lastFit = { bounds, options };
      return update(fitCamera(camera, bounds, viewport, options));
    },
    preset(name) {
      assertLive();
      camera = cameraPreset(camera, name);
      return update(
        lastFit
          ? fitCamera(camera, lastFit.bounds, viewport, lastFit.options)
          : camera,
      );
    },
    project(world) {
      return projectPoint(world, matrices.matrix, viewport);
    },
    projectSegment(from, to) {
      return projectSegment(from, to, matrices.matrix, viewport);
    },
    /** Match CSS dimensions to the overlay; DPR affects framebuffer resolution only.
     * Disable shading for scalar colors so face orientation cannot alter the legend. */
    render({
      width = canvas.clientWidth || 1,
      height = canvas.clientHeight || 1,
      pixelRatio = globalThis.devicePixelRatio || 1,
      shading = true,
    } = {}) {
      assertLive();
      if (lost) return false;
      requireValue(typeof shading === "boolean", "invalid shading setting");
      requireValue(
        Number.isFinite(width) &&
          width > 0 &&
          Number.isFinite(height) &&
          height > 0 &&
          Number.isFinite(pixelRatio) &&
          pixelRatio > 0,
        "invalid viewport dimensions",
      );
      viewport = { width, height };
      matrices = cameraMatrices(camera, viewport);
      const maximum = gl.getParameter(gl.MAX_RENDERBUFFER_SIZE),
        ratio = Math.min(pixelRatio, maximum / width, maximum / height),
        pixelsWide = Math.max(1, Math.round(width * ratio)),
        pixelsHigh = Math.max(1, Math.round(height * ratio));
      if (canvas.width !== pixelsWide || canvas.height !== pixelsHigh) {
        canvas.width = pixelsWide;
        canvas.height = pixelsHigh;
      }
      gl.viewport(0, 0, pixelsWide, pixelsHigh);
      gl.disable(gl.BLEND);
      gl.enable(gl.DEPTH_TEST);
      gl.depthFunc(gl.LEQUAL);
      gl.depthMask(true);
      gl.clearDepth(1);
      gl.clearColor(...clear, 1);
      gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
      // Context patches are optional and double-sided. Their depth still occludes correctly.
      gl.disable(gl.CULL_FACE);
      if (packed.surfaces.length) {
        gl.enable(gl.POLYGON_OFFSET_FILL);
        gl.polygonOffset(1, 1);
        gl.useProgram(gpu.surfaceProgram.handle);
        gl.uniform1f(gpu.surfaceProgram.shading, shading ? 1 : 0);
        gl.uniformMatrix4fv(
          gpu.surfaceProgram.matrix,
          false,
          new Float32Array(matrices.matrix),
        );
        gl.bindVertexArray(gpu.surfaceVao);
        gl.drawArrays(gl.TRIANGLES, 0, packed.surfaces.length / 9);
        gl.disable(gl.POLYGON_OFFSET_FILL);
      }
      if (packed.instances.length) {
        gl.enable(gl.CULL_FACE);
        gl.cullFace(gl.BACK);
        gl.useProgram(gpu.instanceProgram.handle);
        gl.uniform1f(gpu.instanceProgram.shading, shading ? 1 : 0);
        gl.uniformMatrix4fv(
          gpu.instanceProgram.matrix,
          false,
          new Float32Array(matrices.matrix),
        );
        gl.bindVertexArray(gpu.instanceVao);
        gl.drawElementsInstanced(
          gl.TRIANGLES,
          36,
          gl.UNSIGNED_SHORT,
          0,
          packed.instances.length / STRIDE,
        );
      }
      gl.bindVertexArray(null);
      return true;
    },
    dispose() {
      if (disposed) return;
      canvas.removeEventListener("webglcontextlost", lose);
      canvas.removeEventListener("webglcontextrestored", restore);
      if (!lost) gpu.dispose();
      disposed = true;
      scene = null;
      packed = null;
    },
  };
}
