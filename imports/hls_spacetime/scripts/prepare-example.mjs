#!/usr/bin/env node
/** Prepare a portable, bounded browser projection from the retained S3/S4
 * example archives. This command transforms saved evidence only; it never
 * starts compilation, simulation, Vivado or a producer-validator rerun. */
import { createHash } from "node:crypto";
import { mkdir, readFile, stat, writeFile } from "node:fs/promises";
import {
  resolve,
  join,
  relative,
  isAbsolute,
  basename,
  dirname,
} from "node:path";
import { isDeepStrictEqual } from "node:util";
import { fileURLToPath } from "node:url";
import { gunzipSync } from "node:zlib";
import { parseTimingPaths } from "./timing-paths.mjs";
import { createModel } from "../web/model.js";

const MAX_PACKED_BYTES = 32 * 1024 * 1024;
const MAX_RAW_BYTES = 256 * 1024 * 1024;

/** Hash exact file bytes, including compression where that is the bound object. */
function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

/** Stop on missing evidence rather than silently generating a plausible picture. */
function check(condition, message) {
  if (!condition) throw new Error(message);
}

/** Compare content identities independently of JSON object key order. */
function sameBuild(left, right) {
  return ["source", "rtl", "observation"].every(
    (key) => left?.[key] === right?.[key],
  );
}

/** Keep an explicit projection of a large object; omitted fields stay in the
 * original hash-bound source rather than being misrepresented as empty data. */
function pick(object, keys) {
  return Object.fromEntries(
    keys
      .filter((key) => Object.hasOwn(object, key))
      .map((key) => [key, object[key]]),
  );
}

/** Read one file with an allocation bound before consuming its bytes. */
async function boundedRead(path, limit) {
  const info = await stat(path);
  check(
    info.isFile() && info.size <= limit,
    `File exceeds ${limit} bytes or is not regular: ${path}`,
  );
  return readFile(path);
}

/** Open an explicit local archive root. The manifest is the caller's trusted
 * evidence inventory, not a signature or an authenticity proof. */
export async function openArchive(directory, name) {
  const root = resolve(directory);
  const bytes = await boundedRead(join(root, "manifest.json"), 1024 * 1024);
  const manifest = JSON.parse(bytes);
  check(
    manifest.schema === 1 && Array.isArray(manifest.files),
    `Unsupported ${name} manifest`,
  );
  const files = new Map();
  for (const entry of manifest.files) {
    check(
      typeof entry.file === "string" && !files.has(entry.file),
      `Duplicate/invalid ${name} manifest entry`,
    );
    files.set(entry.file, entry);
  }
  return {
    root,
    name,
    manifest,
    files,
    manifest_sha256: sha256(bytes),
    sources: [],
  };
}

/** Verify a requested compressed/plain file against its retained manifest
 * before bounded decompression. Record both packed and decoded identities. */
export async function readVerifiedBytes(archive, name, expectedRawSha) {
  const entry = archive.files.get(name);
  check(entry, `Unmanifested source: ${archive.name}/${name}`);
  const path = resolve(archive.root, name),
    pathWithin = relative(archive.root, path);
  check(
    !isAbsolute(pathWithin) && !pathWithin.startsWith(".."),
    `Unsafe archive path: ${name}`,
  );
  const packed = await boundedRead(path, MAX_PACKED_BYTES);
  check(
    packed.length === entry.bytes && sha256(packed) === entry.sha256,
    `Source hash/length mismatch: ${archive.name}/${name}`,
  );
  const raw = name.endsWith(".gz")
    ? gunzipSync(packed, { maxOutputLength: MAX_RAW_BYTES })
    : packed;
  check(raw.length <= MAX_RAW_BYTES, `Decoded source too large: ${name}`);
  const rawSha = sha256(raw);
  check(
    !expectedRawSha || expectedRawSha === rawSha,
    `Decoded source hash mismatch: ${archive.name}/${name}`,
  );
  archive.sources.push({
    archive: archive.name,
    file: name,
    packed_bytes: packed.length,
    packed_sha256: entry.sha256,
    raw_bytes: raw.length,
    raw_sha256: rawSha,
  });
  return raw;
}
/** Decode JSON only after the underlying saved bytes pass their identity gate. */
export async function readVerifiedJson(archive, name, expectedRawSha) {
  return JSON.parse(await readVerifiedBytes(archive, name, expectedRawSha));
}

/** Separate complete execution records from a compact physical presentation.
 * Cell properties, all nets and native timing remain unavailable in this view,
 * with their original source identity retained for a later detail reader. */
export function projectBundle(bundle) {
  check(
    bundle.format === "spacetime" &&
      bundle.schema === 1 &&
      bundle.unit === "cycle",
    "Unsupported source bundle",
  );
  const physical = bundle.physical;
  if (physical)
    check(
      sameBuild(bundle.build, physical.build),
      "Bundle/physical build mismatch",
    );
  const catalogue = physical
    ? {
        ...pick(physical, [
          "build",
          "checkpoint",
          "evidence",
          "coordinate_unit",
          "bindings",
          "generated",
        ]),
        cells: physical.cells.map((cell) =>
          pick(cell, [
            "id",
            "kind",
            "site",
            "bel",
            "x",
            "y",
            "placement",
            "tile",
            "clock_region",
          ]),
        ),
        omitted: ["cell.properties", "nets", "native"],
        omitted_scope:
          "Available in the retained source catalogue; omitted from this bounded browser projection, not measured empty",
      }
    : null;
  return { bundle: { ...bundle, physical: null }, catalogue };
}

/** Public records remain contextual unless their producer supplies explicit
 * graph anchors. createModel validates those anchors before a view is written. */
function publicAnnotations(publicData) {
  return {
    public: publicData.events.map((row, i) => ({
      id: `public/${i}`,
      ...row,
      label: `${row.stream}: ${JSON.stringify(row.event)}`,
      dependency_endpoint: row.graph_events !== undefined,
      scope:
        row.graph_events === undefined
          ? "Independently decoded public observation; no graph contributor attribution supplied"
          : "Explicit accepted-transfer contributors; annotation introduces no graph event or edge",
    })),
    boundaries: publicData.boundaries.map((row, i) => ({
      id: `boundary/${i}`,
      ...row,
      dependency_endpoint: row.graph_events !== undefined,
      scope:
        row.graph_events === undefined
          ? "All-coordinate public completion boundary; not an execution-graph event"
          : "Completion selects recorded accepted-transfer contributors; no synthetic completion edge",
    })),
    input_stalls: publicData.input_stalls,
    output_stalls: publicData.output_stalls,
  };
}

/** Canonical keys compare relation records independently of JSON field order. */
function recordKey(value) {
  if (Array.isArray(value)) return `[${value.map(recordKey).join(",")}]`;
  if (value && typeof value === "object")
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${recordKey(value[key])}`)
      .join(",")}}`;
  return JSON.stringify(value);
}

/** An observation extension may add graph records, but cannot rewrite the
 * qualified graph or change the resource definitions behind retained mappings. */
function checkPreservedGraph(original, extended) {
  for (const table of ["events", "versions", "resources"]) {
    check(Array.isArray(extended[table]), `Missing extended ${table}`);
    const rows = new Map(extended[table].map((row) => [row.id, row]));
    for (const row of original[table])
      check(
        isDeepStrictEqual(row, rows.get(row.id)),
        `Changed original ${table}: ${row.id}`,
      );
  }
  const relations = new Map();
  for (const row of extended.relations ?? []) {
    const key = recordKey(row);
    relations.set(key, (relations.get(key) ?? 0) + 1);
  }
  for (const row of original.relations) {
    const key = recordKey(row),
      count = relations.get(key) ?? 0;
    check(count > 0, "Changed original relation");
    relations.set(key, count - 1);
  }
}

/** Reuse a qualified physical presentation for an explicitly reviewed capture
 * extension. The loader checks exact file bytes; this pure operation checks the
 * review's identity/bounds contract and unchanged original graph records. The
 * review is a trusted local evidence inventory, not an equivalence proof.
 * Physical correspondence and static timing retain their original provenance;
 * new stream resources get no guessed mapping or inherited event coverage. */
export function applyCaptureExtension(base, bundle, summary, review) {
  check(
    base?.format === "spacetime-view" && base.schema === 1 && base.catalogue,
    "Capture extension requires a qualified physical base projection",
  );
  check(
    review?.format === "spacetime-capture-extension-review" &&
      review.schema === 1,
    "Unsupported capture extension review",
  );
  for (const name of [
    "base_projection_sha256",
    "original_trace_sha256",
    "extended_trace_sha256",
    "bundle_sha256",
    "public_sha256",
    "original_simulator_sha256",
    "extended_simulator_sha256",
    "checkpoint_sha256",
  ])
    check(
      /^[a-f0-9]{64}$/.test(review[name] ?? ""),
      `Missing extension identity: ${name}`,
    );
  check(
    sameBuild(base.bundle.build, review.base_build) &&
      sameBuild(bundle.build, review.extended_build),
    "Extension review/build mismatch",
  );
  check(
    ["source", "rtl"].every(
      (key) => base.bundle.build[key] === bundle.build[key],
    ) && review.original_simulator_sha256 === review.extended_simulator_sha256,
    "Extension changed source, RTL or simulator",
  );
  check(
    sameBuild(base.catalogue.build, base.bundle.build) &&
      base.catalogue.checkpoint === review.checkpoint_sha256,
    "Extension physical origin mismatch",
  );
  check(
    !bundle.physical,
    "Extension bundle must not supply replacement physical evidence",
  );
  const originalCapture = base.bundle.capture,
    capture = bundle.capture;
  check(
    capture?.complete === true &&
      originalCapture.complete === true &&
      capture.first_cycle === originalCapture.first_cycle &&
      capture.end_cycle === originalCapture.end_cycle &&
      isDeepStrictEqual(capture.incarnations, originalCapture.incarnations),
    "Extension capture bounds/reset incarnations changed",
  );
  const comparison = review.comparison;
  check(
    comparison?.old_taps_equal === true &&
      comparison.public_fields_equal === true &&
      Number.isSafeInteger(comparison.original_taps) &&
      comparison.original_taps > 0 &&
      comparison.first_cycle === capture.first_cycle &&
      comparison.end_cycle === capture.end_cycle &&
      comparison.compared_cycles === capture.end_cycle - capture.first_cycle,
    "Extension lacks complete original-tap/public-field equality review",
  );
  checkPreservedGraph(base.bundle, bundle);
  check(
    Array.isArray(summary?.events) && Array.isArray(summary.boundaries),
    "Missing extended public observations",
  );
  const annotations = publicAnnotations(summary);
  const selected = annotations.boundaries.find(
    (row) =>
      row.step === base.selection.step &&
      row.cycle === base.selection.completionCycle,
  );
  check(selected, "Extended selected completion boundary missing");
  const waitOperations = review.wait_operations ?? [];
  check(
    Array.isArray(waitOperations) &&
      waitOperations.length <= 1 &&
      waitOperations.every((name) => name === "entry_wait"),
    "Unqualified wait-operation classification",
  );
  const origin = {
    build: base.bundle.build,
    checkpoint: base.catalogue.checkpoint,
    base_projection_sha256: review.base_projection_sha256,
    original_trace_sha256: review.original_trace_sha256,
    extended_trace_sha256: review.extended_trace_sha256,
    simulator_sha256: review.original_simulator_sha256,
    comparison,
    scope:
      "Retained finite physical correspondence/static timing; same RTL and simulator, all original taps equal. No new native run or dynamic gate attribution.",
  };
  const originalResources = new Set(base.bundle.resources.map((row) => row.id));
  const addedResources = bundle.resources.filter(
    (row) => !originalResources.has(row.id),
  );
  const document = {
    ...base,
    title: `${base.title} · transfer ancestry`,
    bundle: { ...bundle, physical: null },
    catalogue: {
      ...base.catalogue,
      build: bundle.build,
      correspondence_origin: origin,
    },
    annotations,
    examples: [
      ...(base.examples ?? []).filter(
        (example) => example.id !== "completion-context",
      ),
      ...(selected.graph_events?.length
        ? [
            {
              id: "completion-ancestry",
              label: `Completion C${selected.cycle}: accepted-transfer ancestry`,
              event: selected.graph_events.at(-1),
              events: selected.graph_events,
              annotation: selected,
              boundary: selected.id,
              firstCycle: base.selection.firstCycle,
              endCycle: base.selection.endCycle,
              scope:
                "Explicit accepted public-word contributors; unresolved upstream operands remain roots.",
            },
          ]
        : []),
    ],
    coverage: {
      resource_associations: [
        ...(base.coverage?.resource_associations ?? []),
        ...addedResources.map((row) => ({
          resource: row.id,
          status: "unmapped",
          reason:
            "New observation resource; no physical correspondence was produced",
        })),
      ],
      scope:
        "Original resource correspondence retained after complete tap comparison; added resources explicitly unmapped. Original event coverage counts do not describe this extended graph.",
    },
    metric_hints: {
      wait_operations: waitOperations,
      scope:
        "entry_wait is the producer's sampled registered selected-action egress_blocked condition; gaps are not waits.",
    },
    measurement_origin: origin,
    provenance: {
      ...base.provenance,
      capture_extension: {
        review,
        original_coverage: base.coverage ?? null,
        original_scope: base.scope,
        physical_reuse: origin,
        integrity:
          "Caller must verify exact base and extension file hashes; review inventories are trusted local evidence, not signatures.",
      },
    },
    scope: [
      "Fresh finite observation extension: accepted boundary and public-word lineage; original sampled taps and public fields match at every captured cycle.",
      "Physical correspondence and static timing are reused with explicit original-build provenance, not remeasured or upgraded to native equivalence.",
      "Numerical D operands and unmatched publication/arrival ancestry remain explicit roots; new stream resources have no placement attribution.",
      "Original limitations remain in provenance.capture_extension.original_scope with their original capture context.",
    ],
  };
  if (base.nativePaths) {
    check(
      sameBuild(base.nativePaths.build, base.bundle.build) &&
        base.nativePaths.checkpoint === base.catalogue.checkpoint,
      "Extension native timing origin mismatch",
    );
    document.nativePaths = {
      ...base.nativePaths,
      build: bundle.build,
      correspondence_origin: origin,
    };
  }
  createModel(document);
  checkExamples(document);
  return document;
}

/** Curated navigation targets point into existing evidence. They introduce no
 * dependencies and disclose unknown computation and completion ancestry. */
function liveExamples() {
  return [
    {
      id: "register-residence",
      label: "Register residence: C1852 → C1866",
      event: "e/25527",
      version: "v/25067",
      events: ["e/25066", "e/25521", "e/25522", "e/25527"],
      firstCycle: 1852,
      endCycle: 1867,
      scope:
        "Write → retained encoded word → read → accepted actor action. Numerical D contributor is unknown; actor logic is unmapped.",
    },
    {
      id: "off-window-residence",
      label: "Earlier producer: C1760 → C1851",
      event: "e/24978",
      version: "v/21996",
      events: ["e/21995", "e/24972", "e/24973", "e/24978"],
      firstCycle: 1760,
      endCycle: 1852,
      scope:
        "Producer precedes the selected 99-clock step; traversal retains that ancestry rather than inventing a window root.",
    },
    {
      id: "completion-context",
      label: "Completion clock C1873: actor context",
      event: "e/25740",
      events: [
        "e/25711",
        "e/25720",
        "e/25730",
        "e/25731",
        "e/25733",
        "e/25734",
        "e/25736",
        "e/25738",
        "e/25740",
      ],
      firstCycle: 1870,
      endCycle: 1874,
      scope:
        "Same-clock actor accept/head completion/take. The public step completion is separate and has no evidenced graph edge.",
    },
  ];
}

/** A local RAM witness has logical addresses, never fabricated tile locations. */
function memoryDocument(bundle) {
  return {
    format: "spacetime-view",
    schema: 1,
    title: "RTL memory witness",
    ...projectBundle(bundle),
    annotations: { public: [], boundaries: [] },
    selection: {
      firstCycle: bundle.capture.first_cycle,
      endCycle: bundle.capture.end_cycle,
    },
    layout: {
      coordinate_unit: "logical_address",
      physical: false,
      resources: bundle.resources.map((resource, lane) => ({
        resource: resource.id,
        lane,
        addresses: resource.depth,
      })),
      scope:
        "Logical resource/address lanes only; this witness has no native BRAM placement",
    },
    examples: [
      {
        id: "ram-read-first",
        label: "Read-first: old word survives overwrite in the response",
        event: "e-11",
        version: "word-e-2",
        events: ["e-2", "e-4", "e-6", "e-7", "e-11"],
        firstCycle: 3,
        endCycle: 8,
        scope:
          "Equal write creates a new version; C5 read selects the old word while a masked write replaces it. C7 response retains the selected old version.",
      },
      {
        id: "ram-reset",
        label: "Reset retires pending reads and starts carry-in roots",
        event: "e-32",
        version: "root-1-0",
        events: ["e-19", "e-23", "e-26", "e-32"],
        firstCycle: 9,
        endCycle: 15,
        scope:
          "Two requests are retired at C11. The C14 response follows a new request/carry-in root; no ancestry crosses reset.",
      },
    ],
    scope: [
      "Finite RTL simulation witness, not native BRAM placement or unrestricted proof.",
      "Memory contents are retained across reset, while response validity and dependency incarnation restart.",
    ],
  };
}

/** Check curated navigation references without rerunning old simulation checks. */
export function checkExamples(document) {
  const events = new Set(document.bundle.events.map((event) => event.id));
  const versions = new Set(
    document.bundle.versions.map((version) => version.id),
  );
  for (const example of document.examples) {
    check(
      events.has(example.event) && example.events.every((id) => events.has(id)),
      `Missing example event: ${example.id}`,
    );
    check(
      !example.version || versions.has(example.version),
      `Missing example version: ${example.id}`,
    );
  }
}

/** Write a deterministic JSON projection; output digests describe this derived
 * file while provenance describes the original retained evidence. */
async function writeDocument(directory, name, document) {
  const bytes = Buffer.from(JSON.stringify(document));
  check(bytes.length <= MAX_RAW_BYTES, `Projection too large: ${name}`);
  await writeFile(join(directory, name), bytes);
  return {
    file: name,
    title: document.title,
    bytes: bytes.length,
    sha256: sha256(bytes),
  };
}

/** Prepare the two current campaign examples, loading the large joined graph
 * once and deliberately avoiding a second full catalogue or reset-graph parse. */
export async function prepareExamples({
  physicalArchive,
  captureArchive,
  output,
  captureExtension,
  baseProjection,
}) {
  if (captureExtension) {
    check(
      !physicalArchive && !captureArchive,
      "Extension uses a base projection, not old archives",
    );
    return prepareCaptureExtension({
      captureExtension,
      baseProjection,
      output,
    });
  }
  check(!baseProjection, "A base projection requires --capture-extension");
  check(
    physicalArchive && captureArchive && output,
    "Both archive paths and an output directory are required",
  );
  const physical = await openArchive(physicalArchive, "physical");
  const capture = await openArchive(captureArchive, "capture");
  const joinReview = await readVerifiedJson(
    physical,
    "joined/join-review.json",
  );
  const liveReview = joinReview.cases.find((item) => item.name === "live-1");
  check(
    joinReview.complete && liveReview?.original_json_semantics_preserved,
    "Retained joined graph is not complete/reconciled",
  );
  const joined = await readVerifiedJson(
    physical,
    "joined/live-1.json.gz",
    liveReview.joined_json_sha256,
  );
  check(
    sameBuild(joined.build, physical.manifest.build) &&
      sameBuild(joined.build, joinReview.build),
    "Archive build mismatch",
  );
  check(
    joined.physical?.checkpoint === physical.manifest.checkpoint_sha256 &&
      joined.physical.checkpoint === joinReview.checkpoint,
    "Checkpoint identity mismatch",
  );
  const publicData = await readVerifiedJson(capture, "live-1/public.json");
  const captureReview = await readVerifiedJson(capture, "review/review.json");
  check(
    sameBuild(joined.build, captureReview.summary.build),
    "Public capture/build mismatch",
  );
  const coverage = await readVerifiedJson(
    physical,
    liveReview.event_physical_coverage.file.startsWith("joined/")
      ? liveReview.event_physical_coverage.file
      : `joined/${liveReview.event_physical_coverage.file}`,
    liveReview.event_physical_coverage.json_sha256,
  );
  check(
    sameBuild(joined.build, coverage.build),
    "Event coverage/build mismatch",
  );
  const physicalReview = await readVerifiedJson(physical, "review.json");
  check(
    sameBuild(joined.build, physicalReview.build),
    "Physical review/build mismatch",
  );
  const memory = await readVerifiedJson(capture, "review/memory.json.gz");
  const live = {
    format: "spacetime-view",
    schema: 1,
    title: "N2 source-protocol repetition · step 4",
    ...projectBundle(joined),
    annotations: publicAnnotations(publicData),
    selection: {
      step: captureReview.selected_step,
      previousCompletionCycle: captureReview.previous_completion_cycle,
      completionCycle: captureReview.completion_cycle,
      spacingCycles: captureReview.public_completion_spacing_cycles,
      firstCycle: captureReview.previous_completion_cycle + 1,
      endCycle: captureReview.completion_cycle + 1,
    },
    examples: liveExamples(),
    coverage: pick(coverage, ["resource_associations", "counts", "scope"]),
    measurement: physicalReview.measurement,
    nativePaths: {
      build: joined.build,
      checkpoint: joined.physical.checkpoint,
      scope: "static_timing",
      wireGeometry: false,
      report: "catalogue/timing-max.rpt.gz",
      paths: parseTimingPaths(
        (
          await readVerifiedBytes(physical, "catalogue/timing-max.rpt.gz")
        ).toString("utf8"),
        { cells: joined.physical.cells },
      ),
    },
    scope: [
      joinReview.scope,
      ...captureReview.limitations,
      ...physicalReview.remaining_unknowns,
      "Public completion annotations have no attributed execution-graph endpoint. Numerical D inputs remain unknown roots.",
      "Schematic dependency endpoints do not describe routed geometry or dynamically sensitized gates.",
    ],
  };
  const memoryView = memoryDocument(memory);
  const provenance = {
    archives: [physical, capture].map((archive) => ({
      name: archive.name,
      manifest_sha256: archive.manifest_sha256,
    })),
    sources: [...physical.sources, ...capture.sources],
    integrity:
      "Requested source files matched retained manifest bytes and SHA-256; manifests are trusted local inventories, not signatures",
    omitted_detail: {
      physical:
        "Cell scalar properties, canonical nets and timing beyond the sampled setup paths remain in joined/live-1.json.gz",
      sdf: physical.manifest.joined_sdf_sidecars,
    },
  };
  live.provenance = provenance;
  memoryView.provenance = {
    archives: provenance.archives.filter((item) => item.name === "capture"),
    sources: provenance.sources.filter(
      (item) => item.file === "review/memory.json.gz",
    ),
    integrity: provenance.integrity,
  };
  checkExamples(live);
  checkExamples(memoryView);
  check(
    live.selection.endCycle - live.selection.firstCycle ===
      live.selection.spacingCycles,
    "Completion spacing disagrees with selected window",
  );
  check(
    live.annotations.boundaries.some(
      (row) =>
        row.step === live.selection.step &&
        row.cycle === live.selection.completionCycle,
    ),
    "Selected public completion boundary missing",
  );
  await mkdir(resolve(output), { recursive: true });
  const entries = [
    await writeDocument(output, "live-1.json", live),
    await writeDocument(output, "memory.json", memoryView),
  ];
  await writeFile(
    join(output, "index.json"),
    JSON.stringify(
      { format: "spacetime-view-index", schema: 1, examples: entries },
      null,
      2,
    ),
  );
  return {
    examples: entries,
    physicalCells: live.catalogue.cells.length,
    events: live.bundle.events.length,
    versions: live.bundle.versions.length,
    selectedClocks: live.selection.spacingCycles,
    scope:
      "Saved-file projection and source integrity only; no old simulation/native work repeated",
  };
}

/** Read the new capture inventory and a qualified browser projection only.
 * Preserve the sibling example files after their existing index hashes match;
 * no old native archive, full report reader or simulation is revisited. */
export async function prepareCaptureExtension({
  captureExtension,
  baseProjection,
  output,
}) {
  check(
    captureExtension && baseProjection && output,
    "Capture extension, base projection and output directory are required",
  );
  const archive = await openArchive(captureExtension, "capture-extension");
  const review = await readVerifiedJson(archive, "review.json");
  const baseBytes = await boundedRead(resolve(baseProjection), MAX_RAW_BYTES);
  check(
    sha256(baseBytes) === review.base_projection_sha256,
    "Base projection hash mismatch",
  );
  const bundleNames = ["bundle.json", "bundle.json.gz"].filter((name) =>
    archive.files.has(name),
  );
  check(
    bundleNames.length === 1,
    "Extension manifest must contain exactly one bundle.json[.gz]",
  );
  const bundle = await readVerifiedJson(
    archive,
    bundleNames[0],
    review.bundle_sha256,
  );
  const summary = await readVerifiedJson(
    archive,
    "public.json",
    review.public_sha256,
  );
  const base = JSON.parse(baseBytes);
  const document = applyCaptureExtension(base, bundle, summary, review);
  document.provenance.archives = [
    ...(document.provenance.archives ?? []),
    {
      name: archive.name,
      manifest_sha256: archive.manifest_sha256,
    },
  ];
  document.provenance.sources = [
    ...(document.provenance.sources ?? []),
    ...archive.sources,
  ];
  document.provenance.capture_extension.integrity =
    "Base exact SHA-256 and all extension manifest lengths/digests verified before parsing; inventories are trusted local evidence, not signatures.";
  const root = dirname(resolve(baseProjection)),
    baseName = basename(baseProjection);
  const index = JSON.parse(
    await boundedRead(join(root, "index.json"), 1024 * 1024),
  );
  check(
    index.format === "spacetime-view-index" &&
      index.schema === 1 &&
      Array.isArray(index.examples),
    "Unsupported base example index",
  );
  const names = new Set(),
    siblings = [];
  for (const entry of index.examples) {
    check(
      typeof entry.file === "string" &&
        basename(entry.file) === entry.file &&
        ![".", ".."].includes(entry.file) &&
        !names.has(entry.file),
      "Unsafe/duplicate base example entry",
    );
    names.add(entry.file);
    const bytes =
      entry.file === baseName
        ? baseBytes
        : await boundedRead(join(root, entry.file), MAX_RAW_BYTES);
    check(
      bytes.length === entry.bytes && sha256(bytes) === entry.sha256,
      `Base example index mismatch: ${entry.file}`,
    );
    if (entry.file !== baseName) siblings.push({ entry, bytes });
  }
  check(names.has(baseName), "Base projection missing from example index");
  await mkdir(resolve(output), { recursive: true });
  const updated = await writeDocument(output, baseName, document);
  for (const { entry, bytes } of siblings)
    await writeFile(join(output, entry.file), bytes);
  const examples = index.examples.map((entry) =>
    entry.file === baseName ? updated : entry,
  );
  await writeFile(
    join(output, "index.json"),
    JSON.stringify({ ...index, examples }, null, 2),
  );
  return {
    examples,
    events: bundle.events.length,
    versions: bundle.versions.length,
    addedResources: bundle.resources.length - base.bundle.resources.length,
    scope:
      "Saved fresh capture projection; old physical/native evidence reused only under the recorded full original-tap equality contract",
  };
}

/** Later repeated options win, matching ordinary compiler-command composition. */
export function parseArguments(args) {
  const names = {
    "--physical-archive": "physicalArchive",
    "--capture-archive": "captureArchive",
    "--output": "output",
    "--capture-extension": "captureExtension",
    "--base-projection": "baseProjection",
  };
  const options = {};
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--help") return { help: true };
    check(
      names[args[i]] && args[i + 1] && !args[i + 1].startsWith("--"),
      `Unknown or incomplete argument: ${args[i]}`,
    );
    options[names[args[i]]] = args[++i];
  }
  return options;
}

if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  try {
    const options = parseArguments(process.argv.slice(2));
    if (options.help)
      console.log(
        "node scripts/prepare-example.mjs --physical-archive DIR --capture-archive DIR --output web/data\n" +
          "node scripts/prepare-example.mjs --capture-extension DIR --base-projection FILE --output web/data",
      );
    else console.log(JSON.stringify(await prepareExamples(options), null, 2));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
