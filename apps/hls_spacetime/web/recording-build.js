const legacy = Object.freeze(["source", "rtl", "observation"]);
const current = Object.freeze([...legacy, "implementation"]);

/** Older saved recordings bind native data by checkpoint. If any participant declares
 * an implementation identity, all participants must supply the same identity. */
export function recordingBuildKeys(...builds) {
  return builds.some((build) => build && Object.hasOwn(build, "implementation"))
    ? current
    : legacy;
}
