/** Function, computation, direction and perceptually ordered static-path-delay colors.
 * Delays are supplied by the caller; this module never infers timing or activity.
 * Selection belongs to a separate outline/halo, not this color mapping.
 */
export const UNKNOWN_COLOR = "#81738f";
export const OUTSIDE_TIMING_COLOR = "#526471";
export const FUNCTION_COLORS = Object.freeze({
  data: "#65dac7",
  enable: "#f1bb6c",
  reset: "#b6a1e8",
  mixed: "#d2dfe5",
  shared: "#d2dfe5",
});

const knownDelay = (value) =>
  typeof value === "number" && Number.isFinite(value) && value >= 0;

/** Compute one capture-wide zero-based domain before applying display filters. */
export function timingExtent(values) {
  let max = null;
  let known = 0;
  let unknown = 0;
  for (const value of values) {
    if (knownDelay(value)) {
      max = Math.max(max ?? 0, value);
      known++;
    } else {
      unknown++;
    }
  }
  return { min: 0, max, known, unknown };
}

// Oklab preserves a meaningful lightness axis while changing hue. Gamut fitting
// reduces chroma only; it does not flatten the increasing lightness of the scale.
function linearRgb(lightness, a, b) {
  const l = (lightness + 0.3963377774 * a + 0.2158037573 * b) ** 3;
  const m = (lightness - 0.1055613458 * a - 0.0638541728 * b) ** 3;
  const s = (lightness - 0.0894841775 * a - 1.291485548 * b) ** 3;
  return [
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
  ];
}

function inGamut(rgb) {
  return rgb.every((value) => value >= 0 && value <= 1);
}

function hexColor(lightness, a, b) {
  let rgb = linearRgb(lightness, a, b);
  if (!inGamut(rgb)) {
    let low = 0;
    let high = 1;
    for (let iteration = 0; iteration < 16; iteration++) {
      const chroma = (low + high) / 2;
      if (inGamut(linearRgb(lightness, a * chroma, b * chroma))) {
        low = chroma;
      } else {
        high = chroma;
      }
    }
    rgb = linearRgb(lightness, a * low, b * low);
  }
  const encode = (linear) => {
    const bounded = Math.max(0, Math.min(1, linear));
    const srgb =
      bounded <= 0.0031308
        ? 12.92 * bounded
        : 1.055 * bounded ** (1 / 2.4) - 0.055;
    return Math.round(srgb * 255)
      .toString(16)
      .padStart(2, "0");
  };
  return `#${rgb.map(encode).join("")}`;
}

// Constant Oklab lightness keeps categorical hue from suggesting a rank. The
// small palette deliberately permits collisions: color is not a unique identity.
const COMPUTATION_HUES = Object.freeze([
  15, 45, 75, 105, 135, 165, 195, 225, 255, 285, 315, 345,
]);
const computationHue = (lightness, index) => {
  const radians = (COMPUTATION_HUES[index] * Math.PI) / 180;
  return hexColor(
    lightness,
    0.13 * Math.cos(radians),
    0.13 * Math.sin(radians),
  );
};
export const COMPUTATION_COLORS = Object.freeze(
  COMPUTATION_HUES.map((_, index) => computationHue(0.73, index)),
);
export const COMPUTATION_SHARED_COLOR = hexColor(0.8, 0, 0);

/** Stable FNV-1a over JavaScript string code units; key type is part of identity.
 * Missing/invalid keys are unknown rather than silently joining one category.
 */
function computationIndex(key) {
  const value =
    typeof key === "string" && key.length
      ? `text:${key}`
      : Number.isSafeInteger(key)
        ? `number:${key}`
        : null;
  if (value === null) return null;
  let hash = 2166136261;
  for (let i = 0; i < value.length; i++) {
    hash = Math.imul(hash ^ value.charCodeAt(i), 16777619);
  }
  return (hash >>> 0) % COMPUTATION_HUES.length;
}

/** Stable categorical hue, independent of display order, filters and timing.
 * Supply a nonempty semantic key or safe integer; twelve colors may be shared.
 */
export function computationColor(key) {
  const index = computationIndex(key);
  return index === null ? UNKNOWN_COLOR : COMPUTATION_COLORS[index];
}

/** Clamp a supplied scalar coordinate; unknown values do not become zero. */
function fraction(value) {
  return typeof value === "number" && Number.isFinite(value)
    ? Math.max(0, Math.min(1, value))
    : null;
}

/** A zero-only capture has one known low endpoint; overscale values saturate. */
function delayFraction(delayNs, maxDelayNs) {
  if (!knownDelay(delayNs) || !knownDelay(maxDelayNs)) return null;
  return maxDelayNs === 0
    ? delayNs === 0
      ? 0
      : 1
    : Math.min(1, delayNs / maxDelayNs);
}

/** Direction means a caller-supplied source-to-sink coordinate, not timing or
 * observed activity. Dark cool sources lead to bright warm sinks.
 */
export function directionColor(position) {
  const value = fraction(position);
  if (value === null) return UNKNOWN_COLOR;
  return hexColor(
    0.5 + 0.38 * value,
    -0.035 + 0.065 * value,
    -0.11 + 0.23 * value,
  );
}
export const DIRECTION_SOURCE_COLOR = directionColor(0);
export const DIRECTION_SINK_COLOR = directionColor(1);

/** Dim low-delay circuitry and brighten high-delay circuitry on one fixed
 * capture-wide scale. Unknown timing and an absent domain remain distinct.
 */
export function timingColor(delayNs, maxDelayNs) {
  const value = delayFraction(delayNs, maxDelayNs);
  if (value === null) return UNKNOWN_COLOR;
  return hexColor(
    0.4 + 0.5 * value,
    0.025 + 0.005 * value,
    -0.085 + 0.215 * value,
  );
}

/** Map supplied function, computation identity or complete-path delay to opaque
 * CSS color. Hybrid mode retains a computation hue and uses timing lightness.
 * Explicitly shared computation ownership uses neutral gray, never a fake key.
 * Use the same maxDelayNs across the capture, not each window or selection.
 */
export function sceneColor({
  role = "data",
  mode = "role",
  delayNs = null,
  maxDelayNs = null,
  computationKey = null,
  computationShared = false,
  timingApplicable = true,
} = {}) {
  if (mode === "role") return FUNCTION_COLORS[role] ?? UNKNOWN_COLOR;
  if ((mode === "timing" || mode === "computation-timing") && !timingApplicable)
    return OUTSIDE_TIMING_COLOR;
  if (mode === "timing") return timingColor(delayNs, maxDelayNs);
  if (mode === "computation")
    return computationShared
      ? COMPUTATION_SHARED_COLOR
      : computationColor(computationKey);
  if (mode === "computation-timing") {
    const index = computationIndex(computationKey);
    const value = delayFraction(delayNs, maxDelayNs);
    if (value === null || (!computationShared && index === null))
      return UNKNOWN_COLOR;
    const lightness = 0.4 + 0.5 * value;
    return computationShared
      ? hexColor(lightness, 0, 0)
      : computationHue(lightness, index);
  }
  throw new RangeError(`Unknown scene color mode: ${mode}`);
}
