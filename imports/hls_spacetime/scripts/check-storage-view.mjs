#!/usr/bin/env node
/** Independently replay declared logical storage operations clock by clock and
 * compare the viewer's compressed bridges. Reads saved JSON only: no producer,
 * simulator, native catalogue importer or hardware job is run. */
import { readFile, stat } from "node:fs/promises";
import { createHash } from "node:crypto";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createModel, storageSegments } from "../web/model.js";

const MAX_BYTES = 128 * 1024 * 1024;
const DEFAULT_COMPARISONS = 1_000_000;

/** Contradictions reject; missing continuity coverage is reported separately. */
function check(condition, message) {
  if (!condition) throw new Error(message);
}

/** Word identity is independent of recorded value or its physical placement. */
function word(resource, address) {
  return JSON.stringify([resource, address]);
}

/** One connection joins two adjacent pre-edge samples within an incarnation. */
function edgeKey(resource, address, cycle) {
  return JSON.stringify([resource, address, cycle]);
}

/** Reject invalid dimensions before arithmetic or wide-mask allocation. */
function integer(value, minimum, maximum, message) {
  check(
    Number.isSafeInteger(value) && value >= minimum && value <= maximum,
    message,
  );
  return value;
}

/** Replay complete declared storage coverage independently of viewer lifetimes.
 * Unknown root contents/ancestry remain unknown; known version retention can
 * still be checked. Incomplete captures and observer gaps do not qualify holds.
 * The edge budget bounds cycle-by-word comparisons, including compressed holds. */
export function auditStorageView(
  document,
  { maxComparisons = DEFAULT_COMPARISONS } = {},
) {
  integer(maxComparisons, 1, DEFAULT_COMPARISONS, "Invalid comparison budget");
  const model = createModel(document);
  const { capture, events, versions, resources } = document.bundle;
  const base = {
    evidence: "saved-logical-storage-rendering-check",
    scope:
      "Within complete declared storage-write coverage; no raw signal, native write-enable, ancestry, or physical-equivalence proof",
    qualified_storage_edges: false,
    max_comparisons: maxComparisons,
  };
  if (
    capture.complete !== true ||
    !capture.observers?.length ||
    capture.observers.some(
      (observer) => !Array.isArray(observer.gaps) || observer.gaps.length,
    )
  ) {
    return {
      ...base,
      reason:
        "Incomplete or gapped observation coverage; continuity is unqualified",
      comparisons: 0,
    };
  }
  for (const observer of capture.observers) {
    const sequence = events
      .filter((event) => event.observer === observer.id)
      .map((event) => event.sequence)
      .sort((a, b) => a - b);
    check(
      sequence.length === observer.next_sequence - observer.first_sequence &&
        sequence.every(
          (value, index) => value === observer.first_sequence + index,
        ),
      `Observer sequence coverage mismatch: ${observer.id}`,
    );
  }
  check(
    events.every((event) =>
      capture.observers.some((observer) => observer.id === event.observer),
    ),
    "Event has no declared observer",
  );

  const resourceById = new Map(
    resources.map((resource) => [resource.id, resource]),
  );
  const versionById = new Map(versions.map((version) => [version.id, version]));
  const epochs = [...capture.incarnations].sort(
    (a, b) => a.first_cycle - b.first_cycle,
  );
  let nextCycle = capture.first_cycle;
  const wordsByEpoch = new Map();
  let comparisons = 0;
  for (const epoch of epochs) {
    check(
      epoch.first_cycle === nextCycle,
      `Incarnation partition gap/overlap: ${epoch.id}`,
    );
    nextCycle = epoch.end_cycle;
    const words = new Map();
    for (const version of versions.filter(
      (item) => item.incarnation === epoch.id && item.storage,
    )) {
      const { resource, address } = version.storage;
      const shape = resourceById.get(resource);
      integer(shape?.width, 1, 1_000_000, `Invalid storage width: ${resource}`);
      integer(
        shape?.depth,
        1,
        Number.MAX_SAFE_INTEGER,
        `Invalid storage depth: ${resource}`,
      );
      integer(
        address,
        0,
        shape.depth - 1,
        `Invalid storage address: ${version.id}`,
      );
      const key = word(resource, address);
      if (!words.has(key)) words.set(key, { resource, address, root: null });
      if (version.producer === "root") {
        check(
          !words.get(key).root,
          `Duplicate storage root: ${key}/${epoch.id}`,
        );
        check(
          ["initial", "carry_in", "unknown"].includes(version.origin),
          `Invalid storage root origin: ${version.id}`,
        );
        words.get(key).root = version.id;
      }
    }
    check(
      [...words.values()].every((entry) => entry.root),
      `Missing initial storage root: ${epoch.id}`,
    );
    comparisons += words.size * (epoch.end_cycle - epoch.first_cycle - 1);
    check(
      Number.isSafeInteger(comparisons) && comparisons <= maxComparisons,
      "Storage comparison budget exceeded",
    );
    wordsByEpoch.set(epoch.id, words);
  }
  check(
    nextCycle === capture.end_cycle,
    "Incarnation partition does not cover capture",
  );

  const counts = {
    comparisons,
    write_bridges: 0,
    hold_bridges: 0,
    committed_writes: 0,
    full_writes: 0,
    masked_writes: 0,
    explicit_holds: 0,
    read_requests: 0,
    read_results: 0,
    responses_after_replacement: 0,
    reset_retired_requests: 0,
    capture_tail_requests: 0,
    terminal_writes_without_next_sample: 0,
    unknown_storage_roots: versions.filter(
      (v) => v.storage && v.producer === "root" && v.origin === "unknown",
    ).length,
  };
  const expected = new Map();
  for (const epoch of epochs) {
    const words = wordsByEpoch.get(epoch.id);
    if (!words.size) {
      check(
        !events.some((event) => event.incarnation === epoch.id && event.access),
        `Storage access without any represented word: ${epoch.id}`,
      );
      continue;
    }
    const current = new Map(
      [...words].map(([key, entry]) => [key, entry.root]),
    );
    const requests = new Map(),
      responded = new Set();
    const byCycle = new Map();
    for (const event of events.filter(
      (item) => item.incarnation === epoch.id && item.access,
    )) {
      if (!byCycle.has(event.cycle)) byCycle.set(event.cycle, []);
      byCycle.get(event.cycle).push(event);
    }
    for (let cycle = epoch.first_cycle; cycle < epoch.end_cycle; cycle++) {
      const accessEvents = byCycle.get(cycle) ?? [];
      const writes = new Map();
      for (const event of accessEvents) {
        const access = event.access,
          key = word(access.resource, access.address);
        check(current.has(key), `Access has no storage root: ${event.id}`);
        if (access.kind !== "write") continue;
        check(!writes.has(key), `Concurrent writes: ${event.id}`);
        check(
          access.before === current.get(key),
          `Stale write before-version: ${event.id}`,
        );
        const after = versionById.get(access.after_version);
        check(
          after &&
            after.id !== access.before &&
            after.producer === event.id &&
            after.origin === "event" &&
            after.incarnation === epoch.id &&
            after.storage?.resource === access.resource &&
            after.storage.address === access.address &&
            event.outputs.length === 1 &&
            event.outputs[0] === after.id,
          `Invalid write after-version: ${event.id}`,
        );
        const width = resourceById.get(access.resource).width;
        check(
          typeof access.mask === "string"
            ? /^0x[0-9a-f]+$/i.test(access.mask)
            : Number.isSafeInteger(access.mask),
          `Invalid write mask: ${event.id}`,
        );
        const mask = BigInt(access.mask),
          full = (1n << BigInt(width)) - 1n;
        check(mask > 0n && mask <= full, `Invalid write mask: ${event.id}`);
        check(
          mask === full || event.inputs.includes(access.before),
          `Masked write loses prior bits: ${event.id}`,
        );
        counts[mask === full ? "full_writes" : "masked_writes"]++;
        counts.committed_writes++;
        writes.set(key, event);
      }
      // Requests and explicit holds observe this edge before ordinary updates.
      for (const event of accessEvents) {
        const access = event.access,
          key = word(access.resource, access.address);
        if (access.kind === "hold") {
          check(
            !writes.has(key) &&
              access.version === current.get(key) &&
              event.inputs.includes(access.version),
            `Invalid explicit hold: ${event.id}`,
          );
          counts.explicit_holds++;
        } else if (access.kind === "read_request") {
          const resource = resourceById.get(access.resource),
            write = writes.get(key);
          integer(
            resource.read_latency,
            0,
            Number.MAX_SAFE_INTEGER,
            `Invalid read latency: ${event.id}`,
          );
          check(
            !write ||
              ["read_first", "write_first"].includes(resource.collision),
            `Unsupported read/write collision: ${event.id}`,
          );
          const selected =
            write && resource.collision === "write_first"
              ? write.access.after_version
              : current.get(key);
          check(
            access.version === selected && event.inputs.includes(selected),
            `Wrong selected read version: ${event.id}`,
          );
          requests.set(event.id, event);
          counts.read_requests++;
        } else
          check(
            ["write", "read_result"].includes(access.kind),
            `Unknown storage operation: ${event.id}`,
          );
      }
      // A delayed response retains its accepted request, not the current word.
      for (const event of accessEvents.filter(
        (item) => item.access.kind === "read_result",
      )) {
        const access = event.access,
          request = requests.get(access.request);
        check(
          request &&
            !responded.has(request.id) &&
            ["resource", "address", "port", "version"].every(
              (name) => request.access[name] === access[name],
            ) &&
            event.inputs.includes(access.version) &&
            cycle ===
              request.cycle + resourceById.get(access.resource).read_latency,
          `Read response/request mismatch: ${event.id}`,
        );
        if (
          cycle > request.cycle &&
          current.get(word(access.resource, access.address)) !== access.version
        )
          counts.responses_after_replacement++;
        responded.add(request.id);
        counts.read_results++;
      }
      for (const [key, entry] of words) {
        const write = writes.get(key);
        if (cycle + 1 < epoch.end_cycle) {
          const kind = write ? "write" : "hold";
          const version = write ? write.access.after_version : current.get(key);
          expected.set(edgeKey(entry.resource, entry.address, cycle), {
            kind,
            version,
          });
          counts[kind === "write" ? "write_bridges" : "hold_bridges"]++;
        } else if (write) counts.terminal_writes_without_next_sample++;
        if (write) current.set(key, write.access.after_version);
      }
    }
    for (const request of requests.values()) {
      if (!responded.has(request.id)) {
        check(
          request.cycle +
            resourceById.get(request.access.resource).read_latency >=
            epoch.end_cycle,
          `Missing due read response: ${request.id}`,
        );
      }
    }
    counts[
      epoch.end_cycle < capture.end_cycle
        ? "reset_retired_requests"
        : "capture_tail_requests"
    ] += requests.size - responded.size;
  }

  const seen = new Set();
  for (const segment of storageSegments(model)) {
    for (
      let cycle = segment.visibleFromCycle;
      cycle < segment.visibleToCycle;
      cycle++
    ) {
      check(seen.size < maxComparisons, "Rendered bridge budget exceeded");
      const key = edgeKey(segment.resource, segment.address, cycle);
      check(!seen.has(key), `Duplicate rendered storage bridge: ${key}`);
      const wanted = expected.get(key);
      check(
        wanted?.kind === segment.kind && wanted.version === segment.version,
        `Rendered storage bridge mismatch: ${key}`,
      );
      seen.add(key);
    }
  }
  check(
    seen.size === expected.size,
    `Missing rendered storage bridges: ${expected.size - seen.size}`,
  );
  return {
    ...base,
    qualified_storage_edges: true,
    ...counts,
    qualification:
      "Recorded logical storage edges agree with an independent cycle replay; unknown root contents and numerical ancestry remain unknown",
  };
}

/** Later repeated options take precedence; the input remains explicit. */
export function parseArguments(args) {
  if (args.length === 1 && args[0] === "--help") return { help: true };
  check(
    args[0] && !args[0].startsWith("--"),
    "Usage: check-storage-view.mjs PROJECTION.json [--max-comparisons COUNT]",
  );
  const options = { path: args[0], maxComparisons: DEFAULT_COMPARISONS };
  for (let index = 1; index < args.length; index += 2) {
    check(
      args[index] === "--max-comparisons" && args[index + 1] !== undefined,
      `Unknown or incomplete option: ${args[index]}`,
    );
    options.maxComparisons = Number(args[index + 1]);
  }
  return options;
}

/** Read one explicitly selected local projection, with a bounded JSON size. */
async function main(args) {
  const options = parseArguments(args);
  if (options.help) {
    console.log(
      "node scripts/check-storage-view.mjs PROJECTION.json [--max-comparisons COUNT]",
    );
    return;
  }
  const path = resolve(options.path),
    info = await stat(path);
  check(
    info.isFile() && info.size <= MAX_BYTES,
    "Projection exceeds 128 MiB or is not a regular file",
  );
  const bytes = await readFile(path);
  check(bytes.length <= MAX_BYTES, "Projection exceeds 128 MiB");
  const report = {
    input_sha256: createHash("sha256").update(bytes).digest("hex"),
    ...auditStorageView(JSON.parse(bytes), {
      maxComparisons: options.maxComparisons,
    }),
  };
  console.log(JSON.stringify(report, null, 2));
  if (!report.qualified_storage_edges) process.exitCode = 2;
}

if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
