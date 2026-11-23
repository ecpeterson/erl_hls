#!/usr/bin/env node
/** Bounded offline control prediction. Profiles are data, never executable code;
 * historical clocks belong in separate comparisons, not internal release floors.
 */
import { open, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { controlReplay } from "../web/control-replay.js";
const limit = 16 * 1024 * 1024;

/** Hash the exact supplied bytes and execute only the maintained control model. */
export function replayControl(bytes, options = {}) {
  if (!(bytes instanceof Uint8Array) || bytes.length > limit)
    throw new TypeError("Control profile byte limit");
  const profile = JSON.parse(
    new TextDecoder("utf-8", { fatal: true }).decode(bytes),
  );
  const baseline = controlReplay(profile, { ...options, extraLatency: 0 });
  const candidate = controlReplay(profile, options);
  return {
    format: "spacetime-control-prediction",
    schema: 1,
    input: {
      bytes: bytes.length,
      sha256: createHash("sha256").update(bytes).digest("hex"),
    },
    provenance: profile.provenance ?? [],
    intervention: options,
    baseline,
    candidate,
    cycleDelta:
      baseline.completion && candidate.completion
        ? candidate.completion.elapsedCycles - baseline.completion.elapsedCycles
        : null,
  };
}

/** Last scalar option wins, consistent with the rest of the project toolchain. */
function parse(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 2) {
    const key = argv[i];
    if (
      ![
        "--profile",
        "--output",
        "--actors",
        "--extra-latency",
        "--targets",
        "--end-cycle",
      ].includes(key) ||
      i + 1 === argv.length
    )
      throw new Error(
        "Usage: replay-control.mjs --profile FILE --output NEWFILE --actors 2,3 --extra-latency 1 [--targets ID,ID] [--end-cycle N]",
      );
    args[key.slice(2)] = argv[i + 1];
  }
  if (
    !args.profile ||
    !args.output ||
    !args.actors ||
    args["extra-latency"] === undefined
  )
    throw new Error("Missing required replay options");
  const number = (s) => {
    if (!/^\d+$/.test(s) || !Number.isSafeInteger(Number(s)))
      throw new Error("Invalid integer option");
    return Number(s);
  };
  return {
    profile: args.profile,
    output: args.output,
    options: {
      actors: args.actors.split(",").map((id) => {
        if (!id) throw new Error("Empty actor identity");
        return /^\d+$/.test(id) ? number(id) : id;
      }),
      extraLatency: number(args["extra-latency"]),
      ...(args.targets ? { targets: args.targets.split(",") } : {}),
      ...(args["end-cycle"] ? { endCycle: number(args["end-cycle"]) } : {}),
    },
  };
}
async function main() {
  const args = parse(process.argv.slice(2)),
    f = await open(args.profile, "r");
  let bytes;
  try {
    const stat = await f.stat();
    if (!stat.isFile() || stat.size > limit)
      throw new Error("Control profile size or kind");
    bytes = await f.readFile();
  } finally {
    await f.close();
  }
  const report = replayControl(bytes, args.options);
  await writeFile(args.output, JSON.stringify(report, null, 2) + "\n", {
    flag: "wx",
  });
  process.stdout.write(
    JSON.stringify({
      baseline: report.baseline.completion,
      candidate: report.candidate.completion,
      status: report.candidate.status,
      reason: report.candidate.reason,
      cycleDelta: report.cycleDelta,
    }) + "\n",
  );
  if (
    report.baseline.status !== "conditional" ||
    report.candidate.status !== "conditional"
  )
    process.exitCode = 2;
}
if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(resolve(process.argv[1])).href
)
  main().catch((e) => {
    console.error(e.message);
    process.exitCode = 1;
  });
