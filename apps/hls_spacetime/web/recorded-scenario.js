/** Fixed-work counterfactual adapter. Recorded dependencies remain evidence;
 * added version/order and source-profile constraints are explicit model rules. */
import { latencyScenario } from "./latency-scenario.js";

function check(ok, reason) {
  if (!ok) throw Error(`Recorded scenario: ${reason}`);
}
const cycle = (value) => Number.isSafeInteger(value) && value >= 0;
const sameBuild = (a, b) =>
  ["source", "rtl", "observation", "implementation"].every(
    (k) => a?.[k] === b?.[k],
  );

/** Bind a small, separately reviewed obligation profile to the exact recording.
 * Names never identify owners. Every group member and extra edge must exist;
 * simultaneous coupled writes form one completion barrier, not repeated delays. */
export function validateLatencyProfile(model, profile, recording) {
  check(
    profile?.format === "spacetime-latency-profile" && profile.schema === 1,
    "unsupported profile",
  );
  check(sameBuild(model.bundle.build, profile.build), "profile build mismatch");
  check(
    recording &&
      profile.recording &&
      recording.bytes === profile.recording.bytes &&
      recording.sha256 === profile.recording.sha256 &&
      /^[0-9a-f]{64}$/.test(recording.sha256),
    "profile recording mismatch",
  );
  check(
    typeof profile.label === "string" &&
      Array.isArray(profile.evidence) &&
      profile.evidence.length &&
      profile.evidence.every(
        (e) =>
          typeof e.description === "string" &&
          typeof e.path === "string" &&
          /^[0-9a-f]{64}$/.test(e.sha256),
      ),
    "missing source evidence",
  );
  check(
    Array.isArray(profile.groups) &&
      Array.isArray(profile.edges) &&
      Array.isArray(profile.unknowns),
    "missing profile tables",
  );
  const ids = new Set(),
    members = new Set();
  for (const group of profile.groups) {
    check(
      typeof group.id === "string" && !ids.has(group.id),
      "duplicate group",
    );
    ids.add(group.id);
    check(
      Array.isArray(group.members) &&
        group.members.length &&
        group.members.includes(group.trigger),
      "invalid coupled group",
    );
    const trigger = model.events.get(group.trigger);
    check(
      trigger && (group.cycle === undefined || group.cycle === trigger.cycle),
      "missing or stale trigger",
    );
    for (const id of group.members) {
      const event = model.events.get(id);
      check(
        event &&
          !members.has(id) &&
          event.cycle === trigger.cycle &&
          event.incarnation === trigger.incarnation,
        "non-simultaneous or overlapping group",
      );
      members.add(id);
    }
  }
  for (const edge of profile.edges) {
    const source = model.events.get(edge.source),
      target = model.events.get(edge.target);
    check(
      source &&
        target &&
        source.incarnation === target.incarnation &&
        cycle(edge.minLag) &&
        target.cycle - source.cycle >= edge.minLag &&
        typeof edge.reason === "string",
      "invalid source obligation",
    );
  }
  check(
    Array.isArray(profile.choices) && profile.choices.length,
    "missing choices",
  );
  const choices = new Set();
  for (const choice of profile.choices) {
    check(
      typeof choice.id === "string" &&
        !choices.has(choice.id) &&
        typeof choice.label === "string" &&
        Array.isArray(choice.groups) &&
        choice.groups.every((id) => ids.has(id)) &&
        new Set(choice.groups).size === choice.groups.length,
      "invalid choice",
    );
    choices.add(choice.id);
  }
  return profile;
}

/** Solve one bounded step with fixed incoming work, branch decisions, versions
 * and accepted order. Original clocks are release floors, not service durations.
 * "preserve_gaps" additionally retains every observed edge gap as a stress case;
 * neither policy is an upper/lower bound on a different implementation.
 *
 * Interventions apply strictly after the previous completion: (startCycle,end].
 * Register values become readable the next edge. Declared write-first requests
 * may read a same-edge write; responses retain exact declared latency. Readers
 * precede replacement and accepted ports retain their order. Holds add no work.
 * Source obligations repair only explicitly reviewed lifecycle gaps. Unknown
 * operand histories and unmodelled resource arbitration remain visible.
 * The profile is immutable; adding k clocks delays each selected coupled result
 * once, and dependent recurrences accumulate through the constraint graph. */
export function recordedScenario(
  model,
  profile,
  {
    choice,
    extraLatency = 1,
    startCycle,
    targets,
    policy = "absorb_gaps",
    recording,
  } = {},
) {
  validateLatencyProfile(model, profile, recording);
  check(
    cycle(extraLatency) &&
      cycle(startCycle) &&
      ["absorb_gaps", "preserve_gaps"].includes(policy),
    "invalid intervention",
  );
  const selected = profile.choices.find((row) => row.id === choice);
  check(
    selected && Array.isArray(targets) && targets.length,
    "missing choice or targets",
  );
  const targetEvents = targets.map((id) => model.events.get(id));
  check(targetEvents.every(Boolean), "missing target");
  const incarnation = targetEvents[0].incarnation;
  check(
    targetEvents.every((e) => e.incarnation === incarnation),
    "targets cross reset",
  );
  const epoch = model.epochs.get(incarnation),
    end = Math.max(...targetEvents.map((e) => e.cycle));
  check(
    startCycle >= epoch.first_cycle && startCycle <= end,
    "start outside target incarnation",
  );
  const available = new Map(
    model.orderedEvents
      .filter(
        (e) =>
          e.incarnation === incarnation &&
          e.cycle <= end &&
          e.access?.kind !== "hold",
      )
      .map((e) => [e.id, e]),
  );
  const selectedGroups = new Set(selected.groups),
    groupFor = new Map(),
    groups = [];
  for (const group of profile.groups) {
    if (!available.has(group.trigger)) continue;
    check(
      group.members.every((id) => available.has(id)),
      "incomplete visible group",
    );
    const id = `scenario-group/${group.id}`,
      event = available.get(group.trigger);
    check(!model.events.has(id), "group identity collision");
    const affected = selectedGroups.has(group.id) && event.cycle > startCycle;
    groups.push({
      id,
      cycle: event.cycle,
      incarnation,
      extraLatency: affected ? extraLatency : 0,
      group: group.id,
      members: group.members,
    });
    group.members.forEach((member) => groupFor.set(member, id));
  }
  const events = [...available.values()]
    .filter((e) => !groupFor.has(e.id))
    .map((e) => ({
      id: e.id,
      cycle: e.cycle,
      incarnation,
    }))
    .concat(groups);
  const eventById = new Map(events.map((e) => [e.id, e])),
    edgeMap = new Map();
  const node = (id) => groupFor.get(id) ?? id;
  function add(source, target, minLag, reason, maxLag) {
    if (!available.has(source) || !available.has(target)) return;
    source = node(source);
    target = node(target);
    if (source === target) {
      check(minLag === 0, "coupled group hides clock separation");
      return;
    }
    const gap = eventById.get(target).cycle - eventById.get(source).cycle;
    check(gap >= minLag, `baseline violates ${reason}`);
    if (policy === "preserve_gaps") minLag = Math.max(minLag, gap);
    const key = JSON.stringify([source, target]);
    const old = edgeMap.get(key);
    edgeMap.set(key, {
      source,
      target,
      minLag: Math.max(minLag, old?.minLag ?? 0),
      ...(maxLag === undefined && old?.maxLag === undefined
        ? {}
        : { maxLag: Math.min(maxLag ?? Infinity, old?.maxLag ?? Infinity) }),
      reasons: [...new Set([...(old?.reasons ?? []), reason])],
    });
  }
  for (const edge of model.edges) {
    const target = available.get(edge.target),
      version = model.versions.get(edge.version);
    if (!target) continue;
    let lag = 0,
      maxLag;
    if (edge.kind === "read_request") {
      lag = model.resources.get(target.access.resource).read_latency;
      maxLag = lag;
    } else if (version?.storage && target.access?.kind !== "read_result") {
      const resource = model.resources.get(version.storage.resource);
      lag =
        target.access?.kind === "read_request" &&
        resource.collision === "write_first"
          ? 0
          : 1;
    }
    add(edge.source, edge.target, lag, `recorded:${edge.kind}`, maxLag);
  }
  // Keep overwritten values readable and serial accepted accesses serial. A read
  // result uses its request's copy; delaying it cannot hold up the original word.
  const lanes = new Map();
  for (const event of available.values()) {
    const access = event.access;
    if (!access || !["write", "read_request"].includes(access.kind)) continue;
    const key = JSON.stringify([access.resource, access.port]);
    if (!lanes.has(key)) lanes.set(key, []);
    lanes.get(key).push(event);
    if (access.kind !== "write") continue;
    const before = model.versions.get(access.before);
    if (before.producer !== "root")
      add(before.producer, event.id, 1, "version_write_order");
    const resource = model.resources.get(access.resource);
    for (const reader of model.consumers.get(access.before) ?? []) {
      const use = available.get(reader);
      if (
        !use ||
        use.id === event.id ||
        ["hold", "read_result"].includes(use.access?.kind)
      )
        continue;
      const strict =
        use.access?.kind === "read_request" &&
        resource.collision !== "read_first";
      add(use.id, event.id, strict ? 1 : 0, "preserve_old_version");
    }
  }
  for (const lane of lanes.values()) {
    lane.sort((a, b) => a.cycle - b.cycle || a.sequence - b.sequence);
    let previous = [],
      current = [],
      at = null;
    for (const event of lane) {
      if (event.cycle !== at) {
        previous = current;
        current = [];
        at = event.cycle;
      }
      for (const prior of previous)
        add(prior.id, event.id, 1, "accepted_port_order");
      current.push(event);
    }
  }
  for (const edge of profile.edges)
    add(edge.source, edge.target, edge.minLag, `profile:${edge.reason}`);
  const unknowns = [
    ...profile.unknowns,
    "Recorded branches and incoming work are held fixed.",
    "Unobserved arbitration and newly created contention are not simulated.",
  ];
  const mappedTargets = targets.map(node);
  const incoming = new Map();
  for (const edge of edgeMap.values()) {
    if (!incoming.has(edge.target)) incoming.set(edge.target, []);
    incoming.get(edge.target).push(edge.source);
  }
  const ancestors = new Set(mappedTargets),
    queue = [...ancestors];
  for (let at = 0; at < queue.length; at++)
    for (const source of incoming.get(queue[at]) ?? []) {
      if (!ancestors.has(source)) {
        ancestors.add(source);
        queue.push(source);
      }
    }
  const roots = new Map();
  for (const event of available.values())
    if (ancestors.has(node(event.id))) {
      for (const id of event.inputs) {
        const version = model.versions.get(id);
        if (version?.producer === "root")
          roots.set(id, { id, origin: version.origin ?? "unknown" });
      }
    }
  const rootCounts = {};
  for (const root of roots.values())
    rootCounts[root.origin] = (rootCounts[root.origin] ?? 0) + 1;
  unknowns.push(
    `${rootCounts.unknown ?? 0} unknown-origin root versions remain in selected completion ancestry.`,
  );
  const result = latencyScenario({
    events,
    edges: [...edgeMap.values()],
    start: { cycle: startCycle, incarnation },
    targets: [...new Set(mappedTargets)],
    bounds: {
      firstCycle: epoch.first_cycle,
      endCycle: epoch.end_cycle,
      endKind:
        epoch.end_cycle < model.bundle.capture.end_cycle ? "reset" : "capture",
    },
    dependencyComplete: false,
    unknowns,
  });
  const affected = result.events?.filter((e) => e.extraLatency > 0) ?? [];
  return {
    ...result,
    profile: profile.label,
    choice: selected.label,
    policy,
    intervention: {
      extraLatency,
      groups: affected.length,
      members: affected.reduce((n, e) => n + (e.members?.length ?? 0), 0),
    },
    rootCoverage: { counts: rootCounts, roots: [...roots.values()] },
    constraints: {
      edges: edgeMap.size,
      coupledGroups: groups.length,
      sourceObligations: profile.edges.length,
    },
    groupFor,
  };
}
