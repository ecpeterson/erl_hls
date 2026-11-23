#!/usr/bin/env node
/** Predict fixed-order latency from an exact recording and reviewed source
 * obligations. No source path is executed and no physical timing is inferred. */
import { open, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createHash } from "node:crypto";
import { createModel } from "../web/model.js";
import { recordedScenario } from "../web/recorded-scenario.js";
import { periodSensitivity } from "../web/latency-scenario.js";
const MiB = 1024 * 1024;
const POLICIES = ["absorb_gaps", "preserve_gaps"];
const cycle = (value) => Number.isSafeInteger(value) && value >= 0;
function check(ok, reason) {
  if (!ok) throw Error(`Predict latency: ${reason}`);
}
function descriptor(bytes) {
  return {
    bytes: bytes.length,
    sha256: createHash("sha256").update(bytes).digest("hex"),
  };
}
function json(bytes, limit, label) {
  check(
    bytes instanceof Uint8Array && bytes.length >= 2 && bytes.length <= limit,
    `${label} exceeds byte bound or is not encoded JSON`,
  );
  return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
}

/** Saved-step targets include every explicitly anchored public output inside
 * (previous completion, completion], not just the final completion annotation. */
function selection(model, { savedStep = false, startCycle, targets }) {
  if (savedStep) {
    check(
      startCycle === undefined && targets === undefined,
      "choose saved-step or explicit start/targets",
    );
    const saved = model.document.selection;
    check(
      cycle(saved?.previousCompletionCycle) &&
        cycle(saved?.completionCycle) &&
        saved.previousCompletionCycle < saved.completionCycle,
      "missing saved step boundaries",
    );
    startCycle = saved.previousCompletionCycle;
    const endCycle = saved.completionCycle;
    const annotations = (model.document.annotations?.public ?? []).filter(
      (a) =>
        a.dependency_endpoint === true &&
        a.cycle > startCycle &&
        a.cycle <= endCycle,
    );
    targets = [...new Set(annotations.flatMap((a) => a.graph_events))];
    check(targets.length, "saved step lacks accepted public output anchors");
    check(
      targets.reduce(
        (last, id) => Math.max(last, model.events.get(id).cycle),
        -1,
      ) === endCycle,
      "saved completion lacks a terminal public output anchor",
    );
    return {
      method: "saved_step_public_anchors",
      startCycle,
      endCycle,
      targets,
      publicAnnotations: annotations.map((a) => a.id ?? null),
    };
  }
  check(
    cycle(startCycle) &&
      Array.isArray(targets) &&
      targets.length &&
      targets.every((id) => typeof id === "string" && id.length),
    "explicit start cycle and target IDs are required",
  );
  targets = [...new Set(targets)];
  let endCycle = startCycle;
  for (const id of targets) {
    const event = model.events.get(id);
    check(event, `unknown target ${id}`);
    check(event.cycle >= startCycle, "target precedes start cycle");
    endCycle = Math.max(endCycle, event.cycle);
  }
  return { method: "explicit_targets", startCycle, endCycle, targets };
}

/** Retain complete targets, constraints, coverage, assumptions and failure
 * details; omit full event schedules, group lookup maps and individual root IDs.
 * Root counts remain explicit. The original recording/profile keep their graphs. */
function compact(result, targetEvents) {
  const { events, groupFor, rootCoverage, ...summary } = result;
  return {
    ...summary,
    targetAssociations: targetEvents.map((event) => ({
      event,
      scenarioNode: groupFor.get(event) ?? event,
    })),
    rootCoverage: { counts: { ...rootCoverage.counts } },
  };
}

/** Pure byte-bound prediction. Hash original UTF-8 bytes before interpretation;
 * the profile must name that exact recording and build. Run both gap policies by
 * default, or select one. Periods are explicit positive hypotheses. Source paths
 * in profile evidence are descriptions only: this function never opens them.
 * No event graph, native timing, placement or original artifact is changed. */
export function predictLatency(
  recordingBytes,
  profileBytes,
  {
    choice,
    extraLatency = 1,
    baselinePeriodNs,
    candidatePeriodNs,
    policy = "both",
    savedStep = false,
    startCycle,
    targets,
  } = {},
) {
  const document = json(recordingBytes, 128 * MiB, "recording"),
    profile = json(profileBytes, 4 * MiB, "profile"),
    recording = descriptor(recordingBytes);
  check(typeof choice === "string" && choice.length, "choice is required");
  check(cycle(extraLatency), "invalid extra latency");
  check(["both", ...POLICIES].includes(policy), "invalid gap policy");
  for (const period of [baselinePeriodNs, candidatePeriodNs])
    check(
      typeof period === "number" && Number.isFinite(period) && period > 0,
      "both assumed periods must be finite and positive",
    );
  const model = createModel(document),
    selected = selection(model, { savedStep, startCycle, targets });
  const reports = (policy === "both" ? POLICIES : [policy]).map((policy) => {
    const result = recordedScenario(model, profile, {
      recording,
      choice,
      extraLatency,
      policy,
      startCycle: selected.startCycle,
      targets: selected.targets,
    });
    return {
      policy,
      result: compact(result, selected.targets),
      time: periodSensitivity(result, { baselinePeriodNs, candidatePeriodNs }),
    };
  });
  return {
    format: "spacetime-latency-prediction",
    schema: 1,
    inputs: { recording, profile: descriptor(profileBytes) },
    build: document.bundle.build,
    profile: {
      label: profile.label,
      evidence: profile.evidence,
      unknowns: profile.unknowns,
    },
    selection: selected,
    intervention: { choice, extraLatency },
    assumedPeriods: { baselinePeriodNs, candidatePeriodNs },
    reports,
    scope:
      "Fixed-work, fixed-order latency scenarios under explicit periods; not simulation, native timing, or a global clock forecast.",
  };
}

/** Read a fixed-size regular file through its handle. A one-byte tail check
 * rejects growth without allowing an unbounded read after the size check. */
async function bounded(path, limit) {
  const file = await open(path, "r");
  try {
    const info = await file.stat();
    check(
      info.isFile() && info.size >= 2 && info.size <= limit,
      "input exceeds byte bound or is not a regular file",
    );
    const bytes = Buffer.alloc(info.size);
    let offset = 0;
    while (offset < bytes.length) {
      const { bytesRead } = await file.read(
        bytes,
        offset,
        bytes.length - offset,
        offset,
      );
      check(bytesRead > 0, "input changed while reading");
      offset += bytesRead;
    }
    const { bytesRead } = await file.read(Buffer.alloc(1), 0, 1, bytes.length);
    check(bytesRead === 0, "input changed while reading");
    return bytes;
  } finally {
    await file.close();
  }
}

/** CLI filesystem wrapper. Inputs are unchanged; output is compact JSON written
 * exclusively to a fresh file, bounded to 16 MiB. No parent directory is created. */
export async function writePrediction({
  recording,
  profile,
  output,
  ...options
}) {
  check(
    recording && profile && output,
    "recording, profile and output are required",
  );
  const recordingBytes = await bounded(resolve(recording), 128 * MiB),
    profileBytes = await bounded(resolve(profile), 4 * MiB);
  const report = predictLatency(recordingBytes, profileBytes, options);
  const bytes = Buffer.from(JSON.stringify(report) + "\n");
  check(bytes.length <= 16 * MiB, "prediction exceeds output byte bound");
  await writeFile(resolve(output), bytes, { flag: "wx" });
  return {
    output: resolve(output),
    ...descriptor(bytes),
    policies: report.reports.map((r) => r.policy),
  };
}

/** Scalar repeats use their last value; --targets is one comma-separated list,
 * likewise replaced in full. Saved-step and explicit selection are exclusive.
 * Repeated --saved-step is harmless. Unknown or missing options reject. */
export function parseArguments(args) {
  const result = {},
    names = {
      "--recording": "recording",
      "--profile": "profile",
      "--output": "output",
      "--choice": "choice",
      "--extra-latency": "extraLatency",
      "--baseline-period": "baselinePeriodNs",
      "--candidate-period": "candidatePeriodNs",
      "--start-cycle": "startCycle",
      "--targets": "targets",
      "--policy": "policy",
    };
  for (let i = 0; i < args.length; i++) {
    const flag = args[i];
    if (flag === "--saved-step") {
      result.savedStep = true;
      continue;
    }
    check(
      Object.hasOwn(names, flag) &&
        typeof args[i + 1] === "string" &&
        args[i + 1].length > 0 &&
        !args[i + 1].startsWith("--"),
      "invalid option",
    );
    const name = names[flag],
      value = args[++i];
    if (["startCycle", "extraLatency"].includes(name)) {
      check(
        /^\d+$/.test(value) && cycle(Number(value)),
        "invalid cycle/latency",
      );
      result[name] = Number(value);
    } else if (["baselinePeriodNs", "candidatePeriodNs"].includes(name)) {
      check(
        /^(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/.test(value) &&
          Number.isFinite(Number(value)) &&
          Number(value) > 0,
        "invalid assumed period",
      );
      result[name] = Number(value);
    } else if (name === "targets") {
      result.targets = value.split(",");
      check(
        result.targets.every((id) => id.length > 0 && id === id.trim()),
        "invalid target list",
      );
    } else if (name === "policy") {
      check(["both", ...POLICIES].includes(value), "invalid gap policy");
      result.policy = value;
    } else result[name] = value;
  }
  check(
    !result.savedStep ||
      (result.startCycle === undefined && result.targets === undefined),
    "choose saved-step or explicit start/targets",
  );
  return result;
}
if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  if (process.argv.length === 3 && process.argv[2] === "--help")
    console.log(
      "Usage: predict-latency.mjs --recording VIEW.json --profile PROFILE.json --output NEW.json --choice ID --baseline-period NS --candidate-period NS (--saved-step | --start-cycle C --targets ID,ID) [--extra-latency N] [--policy both|absorb_gaps|preserve_gaps]",
    );
  else {
    try {
      writePrediction(parseArguments(process.argv.slice(2)))
        .then((result) => console.log(JSON.stringify(result)))
        .catch((error) => {
          console.error(error.message);
          process.exitCode = 1;
        });
    } catch (error) {
      console.error(error.message);
      process.exitCode = 1;
    }
  }
}
