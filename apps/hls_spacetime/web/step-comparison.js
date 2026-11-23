/** Small whole-step companion view. Its summaries are independent of the scene
 * filter/window. Native STA and recorded/control-model timing stay separately
 * inspectable; table row ordering never creates a graph dependency. */
import { stepComparisonMetrics } from "./step-analysis.js";
export { installStepEvidence } from "./step-analysis.js";
const esc = (s) =>
  String(s ?? "").replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ],
  );
const ns = (n) => n.toFixed(3);
/** Construct one instance after its mount exists. Callbacks navigate existing
 * evidence; empty graph-anchor lists are disclosed and must not fabricate edges.
 * update accepts the active resolved clock selection, not a selected SDF cone. */
export function createStepComparison({
  element,
  onFocusBoundary,
  onTraceCompletion,
  onInspectClockPath,
}) {
  let model = null,
    comparison = null,
    key = null;
  element.onclick = (event) => {
    const button = event.target.closest("button");
    if (!button || !comparison) return;
    if (button.dataset.boundary)
      onFocusBoundary(comparison.nodes.get(button.dataset.boundary));
    if (button.dataset.trace)
      onTraceCompletion(comparison.nodes.get(button.dataset.trace));
    if (button.dataset.clockPath)
      onInspectClockPath(
        model.clockReference.limitingPaths.find(
          (p) => p.id === button.dataset.clockPath,
        ),
      );
  };
  return {
    reset() {
      model = null;
      comparison = null;
      key = null;
      element.hidden = true;
      element.replaceChildren();
    },
    update(next, { clockSelection }) {
      const nextComparison = next.stepComparison;
      if (!nextComparison) {
        this.reset();
        return;
      }
      const nextKey = JSON.stringify([
        nextComparison.id,
        nextComparison.current,
        clockSelection.mode,
        clockSelection.periodNs,
      ]);
      if (model === next && key === nextKey) return;
      model = next;
      comparison = nextComparison;
      key = nextKey;
      element.hidden = false;
      const metrics = stepComparisonMetrics(comparison, {
        mode: clockSelection.mode,
        manualPeriodNs: clockSelection.periodNs,
      });
      const max = Math.max(...metrics.rows.map((r) => r.elapsedNs));
      const path = model.clockReference.limitingPaths[0];
      const milestones = [
        comparison.start,
        ...comparison.milestones,
        comparison.end,
      ];
      const notes =
        metrics.mode === "auto"
          ? "Each implementation uses its own whole-design STA estimate."
          : "The selected target/manual period is an assumption, not demonstrated timing closure.";
      element.innerHTML = `<div class="step-heading"><div><span class="eyebrow">WHOLE APPLICATION STEP</span><h2>${esc(comparison.label)}</h2></div><span>Independent of scene filters</span></div>
      <p>Completion C${comparison.start.cycle} → C${comparison.end.cycle}: <b>${comparison.end.cycle - comparison.start.cycle} recorded clocks</b>. ${esc(notes)} Static path delay is not added to the clock-count product.</p>
      <table class="step-table"><thead><tr><th>Implementation</th><th>Clocks</th><th>Period ns</th><th>Step estimate µs</th></tr></thead><tbody>${metrics.rows.map((r) => `<tr class="${r.current ? "step-current" : ""}"><td>${esc(r.label)}${r.current ? " · shown" : ""}</td><td>${r.elapsedCycles}</td><td>${ns(r.periodNs)}</td><td>${(r.elapsedNs / 1000).toFixed(6)}</td></tr>`).join("")}</tbody></table>
      <div class="step-bars" aria-label="Step duration comparison on a common nanosecond scale">${metrics.rows.map((r) => `<div><span>${esc(r.label)}</span><div class="step-bar-track"><div class="step-bar" style="width:${(100 * r.elapsedNs) / max}%"></div></div><span>${ns(r.elapsedNs)} ns</span></div>`).join("")}</div>
      <p class="step-change">${metrics.change.percentReduction.toFixed(1)}% lower estimated duration · schedule contribution ${ns(metrics.change.cycleContributionNs)} ns · clock contribution ${ns(metrics.change.clockContributionNs)} ns.</p>
      <details class="step-detail"><summary>Why this step ends here</summary><p>Reviewed completion-tail milestones from the retained schedule. Intervals can overlap; their gaps are not summed as a new latency model. Available recorded ancestry can be inspected from anchored milestones; unresolved intervals remain explicit.</p>
      <ol class="step-milestones">${milestones.map((row) => `<li><button data-boundary="${esc(row.id)}"><b>C${row.cycle}</b> ${esc(row.label)}</button><span>${row.basis === "validated_control_replay" ? "validated control replay" : (row.basis ?? "recorded boundary")}${row.eventIds.length ? "" : " · no recorded graph anchor"}</span>${row.eventIds.length ? `<button class="step-trace" data-trace="${esc(row.id)}">Trace inputs</button>` : ""}</li>`).join("")}</ol>
      <ul>${comparison.links.map((link) => `<li>${esc(link.label)}: C${comparison.nodes.get(link.from).cycle} → C${comparison.nodes.get(link.to).cycle} (${comparison.nodes.get(link.to).cycle - comparison.nodes.get(link.from).cycle} elapsed clock intervals; ${esc(link.basis.replaceAll("_", " "))}).</li>`).join("")}</ul>
      ${comparison.unknowns.map((s) => `<p class="muted">${esc(s)}</p>`).join("")}</details>
      <details class="step-detail"><summary>What limits the clock</summary><p>The complete implementation's worst retained setup path has ${ns(path.slackNs)} ns slack against ${ns(model.clockReference.targetPeriodNs)} ns. It limits every clock, including clocks displaying another action.</p><p><code>${esc(path.source)}</code> → <code>${esc(path.endpoint)}</code></p><button data-clock-path="${esc(path.id)}">Inspect clock-limiting sink</button><p>The sink link opens its available circuitry; the SDF maximizing chain need not equal this native STA path. Filtering never changes the global period.</p></details>
      <details class="step-detail"><summary>Evidence and assumptions</summary><p>${comparison.assumptions.map(esc).join("<br>")}</p><pre>${esc(JSON.stringify({ start: comparison.start, end: comparison.end, variants: comparison.variants.map(({ reference, ...row }) => row), milestones: comparison.milestones, links: comparison.links }, null, 2))}</pre></details>`;
    },
  };
}
