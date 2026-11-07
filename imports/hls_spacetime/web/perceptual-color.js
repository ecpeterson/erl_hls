/** Fixed function colors and a perceptually ordered static-delay scale.
 * Delays are supplied by the caller; this module never infers timing or activity.
 * Selection belongs to a separate outline/halo, not this color mapping.
 */
export const UNKNOWN_COLOR = "#81738f";
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

/** Map supplied function or static cone delay to an opaque CSS color.
 * Unknown delays or absent domains get their own color; zero is a known delay.
 * Use the same maxDelayNs across the capture, not each visible window/selection.
 */
export function sceneColor({
  role = "data",
  mode = "role",
  delayNs = null,
  maxDelayNs = null,
} = {}) {
  if (mode === "role") return FUNCTION_COLORS[role] ?? UNKNOWN_COLOR;
  if (mode !== "timing")
    throw new RangeError(`Unknown scene color mode: ${mode}`);
  if (!knownDelay(delayNs) || !knownDelay(maxDelayNs)) return UNKNOWN_COLOR;
  const fraction =
    maxDelayNs === 0
      ? delayNs === 0
        ? 0
        : 1
      : Math.min(1, delayNs / maxDelayNs);
  return hexColor(
    0.56 + 0.28 * fraction,
    -0.025 + 0.115 * fraction,
    -0.09 + 0.15 * fraction,
  );
}
