/** Optional counterfactual UI. Model assumptions are user inputs; native timing
 * and observed execution remain immutable. No scenario changes the 3D recording. */
import {
  validateLatencyProfile,
  recordedScenario,
} from "./recorded-scenario.js";
import { periodSensitivity } from "./latency-scenario.js";
import { scenarioPhysical } from "./scenario-physical.js";
const $ = (id) => document.getElementById(id);
const esc = (value) =>
  String(value ?? "").replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ],
  );
const number = (value) =>
  typeof value === "number" ? value.toFixed(3) : "unknown";

/** Lazy hash-checked profile loading avoids any analysis on initial page load.
 * A new capture invalidates pending reads and results. Deliberate Run evaluates
 * two declared gap policies over the complete step, independent of scene filters. */
export function createScenarioControls() {
  let model = null,
    options = null,
    profile = null,
    index = null,
    cut = null,
    generation = 0;
  const status = (text) => {
    $("scenario-status").textContent = text;
  };
  $("scenario-load").onclick = async () => {
    const ticket = generation,
      entry = options?.entry;
    if (!entry || !model) return;
    $("scenario-load").disabled = true;
    try {
      if (
        !/^[a-zA-Z0-9_-]+(?:\/[a-zA-Z0-9_-]+)*\.json$/.test(entry.file) ||
        !Number.isSafeInteger(entry.bytes) ||
        entry.bytes <= 0 ||
        entry.bytes > 4 * 1024 * 1024 ||
        !/^[0-9a-f]{64}$/.test(entry.sha256)
      )
        throw Error("Invalid scenario descriptor");
      const response = await fetch(new URL(entry.file, options.baseUrl));
      if (!response.ok) throw Error(`Profile HTTP ${response.status}`);
      const bytes = await response.arrayBuffer();
      if (bytes.byteLength !== entry.bytes)
        throw Error("Profile size mismatch");
      const hash = [
        ...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)),
      ]
        .map((n) => n.toString(16).padStart(2, "0"))
        .join("");
      if (hash !== entry.sha256) throw Error("Profile hash mismatch");
      if (ticket !== generation) return;
      profile = validateLatencyProfile(
        model,
        JSON.parse(new TextDecoder().decode(bytes)),
        options.recording,
      );
      $("scenario-choice").replaceChildren(
        ...profile.choices.map((c) => new Option(c.label, c.id)),
      );
      $("scenario-content").hidden = false;
      $("scenario-run").disabled = false;
      status(
        `${profile.label}. Source obligations are bound to this exact recording.`,
      );
    } catch (e) {
      if (ticket === generation) {
        status(e.message);
        $("scenario-load").disabled = false;
      }
    }
  };
  $("scenario-run").onclick = () => {
    try {
      if (!profile || !model) throw Error("Load a source-bound profile first");
      for (const id of [
        "scenario-latency",
        "scenario-before",
        "scenario-after",
      ]) {
        if (!$(id).checkValidity() || !$(id).value) {
          $(id).reportValidity();
          return;
        }
      }
      const selection = model.document.selection;
      if (
        !Number.isSafeInteger(selection?.previousCompletionCycle) ||
        !Number.isSafeInteger(selection?.completionCycle)
      )
        throw Error("No explicit saved step boundary");
      const startCycle = selection.previousCompletionCycle,
        endCycle = selection.completionCycle;
      const targets = [
        ...new Set(
          (model.document.annotations?.public ?? [])
            .filter(
              (a) =>
                a.dependency_endpoint &&
                a.cycle > startCycle &&
                a.cycle <= endCycle,
            )
            .flatMap((a) => a.graph_events),
        ),
      ];
      if (
        Math.max(...targets.map((id) => model.events.get(id)?.cycle ?? -1)) !==
        endCycle
      )
        throw Error("Saved step lacks its terminal completion anchor");
      if (!targets.length)
        throw Error("Saved step lacks accepted public output anchors");
      const choice = $("scenario-choice").value,
        extraLatency = Number($("scenario-latency").value);
      const baselinePeriodNs = Number($("scenario-before").value),
        candidatePeriodNs = Number($("scenario-after").value);
      const reports = ["absorb_gaps", "preserve_gaps"].map((policy) => {
        const result = recordedScenario(model, profile, {
          choice,
          extraLatency,
          startCycle,
          targets,
          policy,
          recording: options.recording,
        });
        return {
          policy,
          result,
          time: periodSensitivity(result, {
            baselinePeriodNs,
            candidatePeriodNs,
          }),
        };
      });
      const selected = profile.choices.find((c) => c.id === choice),
        chosen = new Set(selected.groups);
      const changedResources = [
        ...new Set(
          profile.groups
            .filter((g) => chosen.has(g.id))
            .flatMap((g) => g.members)
            .map((id) => model.events.get(id)?.access?.resource)
            .filter(Boolean),
        ),
      ];
      const physical = index
        ? scenarioPhysical(index, { changedResources, cut, candidatePeriodNs })
        : null;
      $("scenario-results").innerHTML =
        `<p>Saved step (${startCycle}, ${endCycle}]: ${endCycle - startCycle} clocks. ${targets.length} public output anchors. Added latency applies to each selected coupled action, once.</p><table><thead><tr><th>Assumption</th><th>Clocks</th><th>Break-even period</th><th>Assumed improvement</th></tr></thead><tbody>${reports.map(({ policy, result, time }) => `<tr><td>${policy === "absorb_gaps" ? "Allow recorded gaps to absorb delay" : "Preserve every recorded dependency gap"}</td><td>${result.candidate ? result.candidate.elapsedCycles : esc(result.status)}</td><td>${number(time.breakEvenCandidatePeriodNs)} ns</td><td>${number(time.improvementPercent)}%</td></tr>`).join("")}</tbody></table><p>Baseline period ${number(baselinePeriodNs)} ns and candidate ${number(candidatePeriodNs)} ns are assumptions. Static path costs are not added again to elapsed time.</p>${reports.map(({ policy, result, time }) => `<p>${policy === "absorb_gaps" ? "Gap absorption" : "Gap preservation"}: ${esc(result.status)}; ${result.intervention.groups} affected groups. ${result.candidate ? `Change: +${result.candidate.deltaCycles} clocks.` : esc(result.reason)} ${time.candidateElapsedNs !== undefined && time.candidateElapsedNs !== null ? `Assumed duration ${number(time.candidateElapsedNs)} ns.` : ""}</p>`).join("")}<p>These are two fixed-work, fixed-order scenarios, not bounds on a resynthesized design. Unknown operand histories, contention and changed branch decisions can invalidate the prediction.</p>`;
      const untouched = physical?.groups?.notTargeted;
      $("scenario-physical").textContent = untouched
        ? `Not targeted by this change: ${untouched.counts.aboveCandidatePeriod} known recorded target bounds exceed the assumed ${candidatePeriodNs} ns period. Largest: ${untouched.largestKnown?.pinName ?? "unknown"}, ${number(untouched.largestKnown?.delayNs)} ns. These are saved independent SDF envelopes, not a global clock forecast; ${physical.coverage.writeBitOccurrences.unknown.toLocaleString()} requested write-bit occurrences are unmapped; unrecorded paths and new placement remain unknown.`
        : "Complete prepared physical evidence unavailable; no clock feasibility assessment.";
      $("scenario-evidence").innerHTML =
        `<p>${profile.unknowns.map((row) => esc(typeof row === "string" ? row : `${row.kind}: ${row.disposition ?? JSON.stringify(row)}`)).join("<br>")}<br>Selected ancestry root versions: ${esc(JSON.stringify(reports[0].result.rootCoverage?.counts ?? {}))}</p><ul>${profile.evidence.map((e) => `<li>${esc(e.description)}<br><code>${esc(e.path)}</code></li>`).join("")}</ul>`;
      $("scenario-results").dataset.status = reports.every(
        (r) => r.result.candidate,
      )
        ? "conditional"
        : "unavailable";
      status(
        "Scenario computed. The measured recording and displayed routes are unchanged.",
      );
    } catch (e) {
      $("scenario-results").textContent = e.message;
      status("Scenario unavailable; no prediction was accepted.");
    }
  };
  for (const id of [
    "scenario-choice",
    "scenario-latency",
    "scenario-before",
    "scenario-after",
  ])
    $(id).oninput = $(id).onchange = () => {
      $("scenario-results").textContent =
        "Inputs changed. Run again to update the scenario.";
      $("scenario-physical").textContent = "";
      $("scenario-results").dataset.status = "stale";
    };
  return {
    configure(nextModel = null, nextOptions = null) {
      generation++;
      model = nextModel;
      options = nextOptions;
      profile = null;
      index = null;
      cut = null;
      $("scenario-content").hidden = true;
      $("scenario-load").disabled = !options?.entry;
      $("scenario-results").textContent = "";
      $("scenario-physical").textContent = "";
      status(
        options?.entry
          ? "Load optional source-bound latency scenarios for this recording."
          : "No source-bound latency profile is supplied for this capture.",
      );
    },
    update(nextIndex, nextCut) {
      index = nextIndex;
      cut = nextCut;
    },
  };
}
