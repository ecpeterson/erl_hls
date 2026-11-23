/** Bounded control-only replay of an already interpreted source workload.
 * Recorded arithmetic/results and branch decisions remain fixed. All internal
 * scheduling is recomputed from old state: no recorded internal clock is a floor.
 * The profile adapter, not this engine, owns source interpretation and provenance.
 */
import { ownerInitial, ownerView, ownerStep } from "./clocked-owner.js";
import {
  publicationView,
  publicationStep,
  captureStep,
  pairSelect,
  pairStep,
  inboxEligible,
  inboxView,
  inboxStep,
} from "./clocked-resources.js";
import {
  transmitterInitial,
  transmitterStep,
  egressInitial,
  egressView,
  egressStep,
} from "./clocked-transport.js";
import { hostInitial, hostView, hostStep } from "./clocked-host.js";

/** Refuse mismatched recorded work instead of idling until it becomes convenient. */
function mismatch(actor, operation, picked, cycle) {
  return {
    kind: "work_order_changed",
    actor,
    operation: operation?.id ?? null,
    expected: operation?.input ?? null,
    actual: picked,
    cycle,
  };
}

/** Replay a profile with explicit finite targets. Definitions:
 * actors={id,slots:[{kind,link?,slot?,host?}],initial:{owner,inbox},operations};
 * links={id,slots:[captureState],order:pairState}; publishers match actor indices;
 * each delivery has recipient,slot (credit key),kind,link/captureSlot or frame;
 * endpoints contain ordered producer actor IDs. Host commands carry actual
 * exogenous floors and causal public-frame IDs. All states are serializable.
 * Returns diagnostic schedule plus a score only after every target is accepted.
 * An unknown next branch, changed message order, reset or finite tail is explicit.
 * Requires a declared failure-free domain and an idle gateway checkpoint; seeded
 * public completions must name known frames accepted strictly before start.
 */
export function controlReplay(
  profile,
  {
    extraLatency = 0,
    actors: interventions = [],
    targets = profile.targets,
    endCycle = profile.endCycle,
  } = {},
) {
  if (
    profile.schema !== 1 ||
    !Number.isSafeInteger(profile.start) ||
    !Number.isSafeInteger(endCycle) ||
    endCycle <= profile.start ||
    endCycle - profile.start > 1000000 ||
    !Number.isSafeInteger(extraLatency) ||
    extraLatency < 0 ||
    !Array.isArray(targets) ||
    !targets.length ||
    new Set(targets).size !== targets.length
  )
    throw new TypeError("Invalid bounded control replay request");
  if (profile.failureFree !== true)
    throw new TypeError(
      "Replay requires a declared failure-free source domain",
    );
  const definition = structuredClone(profile);
  const initialTransmitter = definition.host.initial.transmitter;
  if (
    initialTransmitter.frame != null ||
    initialTransmitter.source != null ||
    (initialTransmitter.index !== undefined && initialTransmitter.index !== 0)
  )
    throw new TypeError("Replay requires an idle transmitter checkpoint");
  const actorDefs = new Map(definition.actors.map((a) => [a.id, a]));
  const actorStates = new Map(
    definition.actors.map((a) => [
      a.id,
      {
        owner: ownerInitial(a.initial.owner),
        inbox: a.initial.inbox,
        position: 0,
      },
    ]),
  );
  let links = new Map(
    definition.links.map((l) => [l.id, { slots: l.slots, order: l.order }]),
  );
  let publishers = new Map(
    definition.publishers.map((p) => [p.actor, p.state]),
  );
  let egress = definition.endpoints.map((e) => ({
    ...egressInitial(e.producers.length),
    ...e.initial,
  }));
  let transmitter = {
    ...transmitterInitial(
      definition.host.initial.transmitter.streamCount,
      definition.host.initial.transmitter,
    ),
  };
  let host = hostInitial(definition.host.commands);
  let ingress = definition.initialIngress ?? null;
  const completed = { ...definition.host.initial.completed };
  const events = [],
    words = [],
    inputWords = [],
    controls = [];
  const enabledActors = new Set(interventions);
  const frameById = new Map(definition.host.frames.map((f) => [f.id, f]));
  const commandById = new Map(definition.host.commands.map((c) => [c.id, c]));
  if (
    Object.entries(completed).some(
      ([id, cycle]) =>
        !frameById.has(id) ||
        !Number.isSafeInteger(cycle) ||
        cycle < 0 ||
        cycle >= profile.start,
    )
  )
    throw new TypeError(
      "Initial completion must name a known frame from before the checkpoint",
    );
  if (
    actorDefs.size !== definition.actors.length ||
    links.size !== definition.links.length ||
    publishers.size !== actorDefs.size ||
    interventions.some((id) => !actorDefs.has(id)) ||
    frameById.size !== definition.host.frames.length ||
    definition.endpoints.length !==
      definition.host.initial.transmitter.streamCount ||
    definition.endpoints.some(
      (e) =>
        !e.producers.length ||
        new Set(e.producers).size !== e.producers.length ||
        e.producers.some((id) => !actorDefs.has(id)),
    ) ||
    targets.some((id) => !frameById.has(id) || Object.hasOwn(completed, id))
  )
    throw new TypeError(
      "Replay identities, endpoint population or future targets disagree",
    );
  for (const [id, def] of actorDefs) {
    if (
      !publishers.has(id) ||
      def.initial.inbox.slotCount !== def.slots.length ||
      new Set(def.operations.map((o) => o.id)).size !== def.operations.length ||
      def.slots.some(
        (s) =>
          s.kind === "capture" &&
          (!links.has(s.link) ||
            !Number.isSafeInteger(s.slot) ||
            s.slot < 0 ||
            s.slot >= links.get(s.link).slots.length),
      )
    )
      throw new TypeError(`Invalid actor profile ${id}`);
  }
  const result = {
    start: profile.start,
    targets: targets.slice(),
    status: "censored",
    reason: "clock_bound",
    completion: null,
    events,
    words,
    inputWords,
    controls,
    completed,
    coverage: {
      sourceFailureFree: definition.failureFree,
      unknowns: definition.unknowns ?? [],
    },
    sourceAssumptions: definition.assumptions ?? [],
    assumptions: [
      "Recorded work, values, branch decisions and logical message identities remain applicable.",
      "Every modeled component observes old state and commits once per clock.",
      "Only declared host stimulus and initial state supply timing floors.",
      "This finite control replay does not predict physical period or prove RTL equivalence.",
    ],
  };
  const creditKey = (link, slot) => `link/${link}/slot/${slot}`;
  const finish = (status, reason, cycle) => {
    result.status = status;
    result.reason = reason;
    result.lastCycle = cycle;
    result.waiting = {
      owners: [...actorStates].map(([actor, s]) => ({
        actor,
        action: s.owner.action?.operation.id ?? null,
        pending: s.owner.pending,
        outbox: s.owner.outbox?.id ?? null,
        held: s.inbox.held,
        postponed: s.inbox.postponed,
      })),
      publications: [...publishers]
        .filter(([, s]) => s.batchId)
        .map(([actor, s]) => ({
          actor,
          batch: s.batchId,
          deliveries: s.queues.flat().map((d) => d.id),
        })),
      captures: [...links].flatMap(([link, l]) =>
        l.slots.flatMap((s, slot) =>
          s.owner === "free"
            ? []
            : [{ link, slot, owner: s.owner, id: s.value?.id ?? null }],
        ),
      ),
      ingress,
      transmitterFrame: transmitter.frame?.id ?? null,
    };
    result.positions = Object.fromEntries(
      [...actorStates].map(([id, s]) => [id, s.position]),
    );
    return result;
  };
  for (let cycle = profile.start; cycle < endCycle; cycle++) {
    if (definition.resetCycles?.includes(cycle))
      return finish("censored", "reset_boundary", cycle);
    // First view all old publications and endpoint selections. No readiness
    // signal changes the producer selected by an already-held endpoint grant.
    const pubViews = new Map(
      [...publishers].map(([id, s]) => [id, publicationView(s)]),
    );
    const endpointFrames = definition.endpoints.map((endpoint) =>
      endpoint.producers.map((id) => {
        const offer = pubViews
          .get(id)
          .offers.find(
            (d) => d.kind === "boundary" && d.endpoint === endpoint.id,
          );
        return offer ? frameById.get(offer.frame) : null;
      }),
    );
    const selections = egress.map((s, i) => egressView(s, endpointFrames[i]));
    const outputReady = definition.host.outputReady.residues.includes(
      cycle % definition.host.outputReady.period,
    );
    const transmitted = transmitterStep(transmitter, {
      frames: [...selections.map((s) => s.frame), null],
      outputReady,
    });
    const acceptedBySource = new Map(
      [...publishers.keys()].map((id) => [id, []]),
    );
    const arrivals = new Map();
    for (const [id, v] of pubViews)
      for (const d of v.offers) {
        if (
          d.kind === "capture" &&
          links.get(d.link).slots[d.captureSlot].owner === "free"
        ) {
          const key = creditKey(d.link, d.captureSlot);
          if (arrivals.has(key))
            throw new Error(`Multiple arrivals claim ${key}`);
          arrivals.set(key, d);
          acceptedBySource.get(id).push(d.recipient);
        }
      }
    const nextEgress = egress.map((s, i) => {
      const ready = transmitted.acceptedSource === i;
      const r = egressStep(s, {
        frames: endpointFrames[i],
        outputReady: ready,
      });
      if (r.acceptedSource !== null) {
        const id = definition.endpoints[i].producers[r.acceptedSource];
        const d = pubViews
          .get(id)
          .offers.find(
            (d) =>
              d.kind === "boundary" &&
              d.endpoint === definition.endpoints[i].id,
          );
        acceptedBySource.get(id).push(d.recipient);
        events.push({
          kind: "frame_transfer",
          id: d.frame,
          publication: publishers.get(id).batchId,
          cycle,
        });
      }
      return r.state;
    });
    // A complete ordinary command passes the generated ReceiveOrdered stage0
    // directly to the ingress register. The register cannot refill on last consume.
    const hostOffer = hostView(host, cycle, completed);
    const inputReady = !hostOffer.valid || !hostOffer.last || ingress === null;
    const hostResult = hostStep(host, { cycle, completed, ready: inputReady });
    let nextIngress = ingress
      ? { ...ingress, recipients: ingress.recipients.slice() }
      : null;
    if (hostResult.acceptedWord) {
      inputWords.push({ ...hostResult.acceptedWord, cycle });
      if (hostOffer.last)
        nextIngress = {
          id: hostOffer.command,
          recipients: commandById.get(hostOffer.command).recipients.slice(),
        };
    }
    const takes = new Map(),
      releases = new Map(),
      nextActors = new Map();
    for (const [id, def] of actorDefs) {
      const state = actorStates.get(id),
        view = ownerView(state.owner);
      if (state.owner.pending === null && !state.owner.action)
        return finish(
          "censored",
          { kind: "unknown_pending", actor: id },
          cycle,
        );
      const busyNumerical =
        state.owner.action && cycle <= state.owner.action.privateCycle;
      const options = {
        ownerBusy: Boolean(state.owner.action),
        internalPending: Boolean(state.owner.pending),
        enabled: !busyNumerical,
      };
      const eligible = inboxEligible(state.inbox, options);
      const heads = [];
      const values = new Map();
      const inbound = new Set(
        def.slots.filter((s) => s.kind === "capture").map((s) => s.link),
      );
      for (const link of inbound) {
        const l = links.get(link);
        const allowed = def.slots.flatMap((s, i) =>
          s.kind === "capture" && s.link === link && eligible.includes(i)
            ? [s.slot]
            : [],
        );
        const selected = pairSelect(l.order, allowed);
        if (selected !== null && l.slots[selected].owner === "full") {
          const slot = def.slots.findIndex(
            (s) =>
              s.kind === "capture" && s.link === link && s.slot === selected,
          );
          heads.push(slot);
          values.set(slot, l.slots[selected].value);
        }
      }
      def.slots.forEach((s, i) => {
        if (s.kind === "host" && ingress?.recipients.includes(id)) {
          heads.push(i);
          values.set(i, { id: ingress.id });
        } else if (s.kind === "startup" && s.pending) {
          heads.push(i);
          values.set(i, { id: s.id });
        }
      });
      const inbox = inboxView(state.inbox, { heads, ...options });
      const ready = view.internalReady || (view.inputReady && inbox.offered);
      const op = ready ? def.operations[state.position] : null;
      if (ready && !op)
        return finish(
          "censored",
          { kind: "recorded_work_tail", actor: id },
          cycle,
        );
      const accepted = ready && view.inputReady && inbox.offered;
      if (op) {
        const actual = accepted
          ? { slot: inbox.pick, id: values.get(inbox.pick)?.id }
          : null;
        if (
          Boolean(op.accepted) !== accepted ||
          (accepted &&
            (op.input.slot !== actual.slot ||
              (op.input.id && op.input.id !== actual.id)))
        )
          return finish("invalid", mismatch(id, op, actual, cycle), cycle);
      }
      // Known effect presence still permits an ordinary commit. Unknown
      // recipients matter when the old outbox reaches the publisher, not one
      // edge earlier while an independent final public word is being accepted.
      if (state.owner.outbox?.complete === false && pubViews.get(id).ready)
        return finish(
          "censored",
          {
            kind: "incomplete_effects",
            actor: id,
            batch: state.owner.outbox.id,
          },
          cycle,
        );
      const step = ownerStep(state.owner, {
        cycle,
        operation: op,
        extraLatency: op?.numerical && enabledActors.has(id) ? extraLatency : 0,
        batchReady: pubViews.get(id).ready,
      });
      const done = step.completed;
      const headDone = Boolean(done?.accepted);
      const received = inboxStep(state.inbox, {
        heads,
        ...options,
        accepted,
        headDone,
        dispatched: headDone && done.dispatched,
        directive: done?.directive ?? 0,
        phaseBoundary: done?.phaseBoundary ?? false,
      });
      step.events.forEach((e) => events.push({ ...e, actor: id }));
      for (const slot of received.output.take) {
        const d = def.slots[slot];
        if (d.kind === "capture") takes.set(creditKey(d.link, d.slot), true);
        else if (d.kind === "host")
          nextIngress.recipients = nextIngress.recipients.filter(
            (a) => a !== id,
          );
        else if (d.kind === "startup") d.pending = false;
      }
      for (const slot of received.output.release) {
        const d = def.slots[slot];
        if (d.kind === "capture") releases.set(creditKey(d.link, d.slot), true);
      }
      if (
        received.output.take.length ||
        received.output.release.length ||
        received.output.postpone.length ||
        accepted
      )
        controls.push({ cycle, actor: id, ...received.output });
      nextActors.set(id, {
        owner: step.state,
        inbox: received.state,
        position: state.position + (step.launched ? 1 : 0),
      });
    }
    if (nextIngress && !nextIngress.recipients.length) nextIngress = null;
    const nextLinks = new Map();
    for (const [id, l] of links) {
      let arrival = null,
        take = null;
      const slots = l.slots.map((s, i) => {
        const key = creditKey(id, i),
          d = arrivals.get(key) ?? null;
        if (d) {
          if (arrival !== null)
            throw new Error(`Multiple arrivals in sender pair ${id}`);
          arrival = i;
          events.push({ kind: "arrival", id: d.id, link: id, slot: i, cycle });
        }
        if (takes.has(key)) {
          if (take !== null)
            throw new Error(`Multiple takes in sender pair ${id}`);
          take = i;
        }
        return captureStep(s, {
          arrive: d,
          take: takes.has(key),
          release: releases.has(key),
        }).state;
      });
      nextLinks.set(id, {
        slots,
        order: pairStep(l.order, { arrive: arrival, take }),
      });
    }
    const nextPublishers = new Map();
    for (const [id, s] of publishers) {
      const p = publicationStep(s, {
        batch: actorStates.get(id).owner.outbox,
        acceptedRecipients: acceptedBySource.get(id),
      });
      nextPublishers.set(id, p.state);
    }
    if (transmitted.acceptedWord) {
      const w = { ...transmitted.acceptedWord, cycle };
      words.push(w);
      if (w.last) {
        completed[w.id] = cycle;
        events.push({ kind: "public", id: w.id, cycle });
      }
    }
    for (const [id, s] of nextActors) actorStates.set(id, s);
    links = nextLinks;
    publishers = nextPublishers;
    egress = nextEgress;
    transmitter = transmitted.state;
    ingress = nextIngress;
    host = hostResult.state;
    if (targets.every((id) => Object.hasOwn(completed, id))) {
      const completionCycle = Math.max(...targets.map((id) => completed[id]));
      result.completion = {
        cycle: completionCycle,
        elapsedCycles: completionCycle - (definition.start - 1),
      };
      return finish("conditional", null, cycle);
    }
  }
  return finish("censored", "clock_bound", endCycle);
}
