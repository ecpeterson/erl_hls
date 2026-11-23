/** Canvas selection controller. Target markers are an explicit screen overlay,
 * including targets behind opaque geometry; they are not electrical evidence.
 * All overlaps remain available in a paged chooser. Hover never rebuilds geometry.
 */
import { projectPickTargets, pickCandidates } from "./scene-picking.js";
const $ = (id) => document.getElementById(id);
const PAGE = 8;
const pickMode = () => $("pick-mode").value;
const category = (mode) =>
  ["reads", "writes"].includes(mode) ? "events" : mode;
const titles = {
  sinks: "Timing sinks",
  reads: "Read events",
  writes: "Write events",
  storage: "Storage spans",
  navigate: "Navigate only",
};

/** Describe the actual selection identity, not a nearby primitive or inferred owner. */
function describe(target) {
  if (target.kind === "sink")
    return `Timing sink · ${target.pinName} · ${target.role} · C${target.cycle} + ${target.arrivalNs.toFixed(3)} ns`;
  if (target.kind === "event") {
    const e = target.event;
    return `${e.access?.kind === "read" ? "Read" : "Write"} event · C${e.cycle} · ${e.actor} · ${e.operation} · ${e.access?.resource ?? e.id}`;
  }
  const s = target.segment;
  return `${s.kind === "write" ? "Load" : "Residence"} · C${s.fromCycle}→C${s.toCycle} · ${s.version} · ${target.point.cell ?? s.resource}`;
}
function eligible(target, mode) {
  if (mode === "reads" || mode === "writes")
    return (
      target.kind === "event" &&
      target.event.access?.kind === (mode === "reads" ? "read" : "write")
    );
  return (
    target.kind ===
    (mode === "sinks" ? "sink" : mode === "storage" ? "storage" : null)
  );
}

/** onChoose receives one explicit target and may reject stale identities.
 * onOverlay repaints only labels/selection marks. Projection is refreshed after
 * camera or scene changes; clear closes stale hover and chooser without changing
 * the selected evidence. No arbitrary wire click selects a sink.
 */
export function createSceneSelection({ onChoose, onOverlay }) {
  let projected = [],
    hovered = null,
    choices = [],
    page = 0,
    generation = 0,
    pointerPosition = null,
    selected = {};
  const clear = () => {
    generation++;
    pointerPosition = null;
    $("pick-choices").replaceChildren();
    hovered = null;
    choices = [];
    $("tooltip").hidden = true;
    $("pick-chooser").hidden = true;
    $("stack").style.cursor = pickMode() === "navigate" ? "grab" : "crosshair";
  };
  const candidates = (pointer) => {
    if (pickMode() === "navigate") return [];
    // A multi-bit event has several positions but still selects one event.
    // Sink IDs retain role/cycle/arrival, so distinct timing representations remain.
    const seen = new Set();
    return pickCandidates(projected, pointer, {
      mode: category(pickMode()),
    }).filter(({ target }) => {
      if (seen.has(target.id)) return false;
      seen.add(target.id);
      return true;
    });
  };
  const choose = (hit) => {
    const description = describe(hit.target);
    clear();
    const accepted = onChoose(hit.target);
    $("pick-notice").textContent = accepted
      ? `Selected ${description}.${hit.target.kind === "sink" ? " Its path is shown in Paths to sinks." : ""}`
      : "That target is no longer in the current view. Select a visible target.";
    onOverlay();
  };
  function renderChoices() {
    const pages = Math.max(1, Math.ceil(choices.length / PAGE));
    page = Math.max(0, Math.min(page, pages - 1));
    $("pick-heading").textContent =
      `${choices.length} targets at cursor · ${titles[pickMode()]}`;
    $("pick-page").textContent = `${page + 1} / ${pages}`;
    $("pick-prev").disabled = page === 0;
    $("pick-next").disabled = page === pages - 1;
    hovered = choices[page * PAGE] ?? null;
    const current = ++generation;
    $("pick-choices").replaceChildren(
      ...choices.slice(page * PAGE, (page + 1) * PAGE).map((hit) => {
        const button = document.createElement("button");
        button.type = "button";
        button.textContent = describe(hit.target);
        button.title = button.textContent;
        button.onmouseenter = button.onfocus = () => {
          if (current !== generation) return;
          hovered = hit;
          onOverlay();
        };
        button.onclick = () => {
          if (current === generation) choose(hit);
        };
        return button;
      }),
    );
  }
  $("pick-close").onclick = () => {
    clear();
    onOverlay();
    $("stack").focus({ preventScroll: true });
  };
  $("pick-prev").onclick = () => {
    page--;
    renderChoices();
    onOverlay();
  };
  $("pick-next").onclick = () => {
    page++;
    renderChoices();
    onOverlay();
  };
  $("pick-chooser").onkeydown = (e) => {
    if (e.key === "Escape") {
      e.preventDefault();
      $("pick-close").click();
    }
  };
  return {
    clear,
    invalidate() {
      clear();
      projected = [];
    },
    reset() {
      clear();
      projected = [];
      $("pick-notice").textContent = "";
    },
    project(targets, scene, selection = {}) {
      selected = selection;
      const mode = pickMode();
      projected = projectPickTargets(
        targets.filter((target) => eligible(target, mode)),
        {
          project: (point) => scene.project(point),
          projectSegment: (from, to) => scene.projectSegment(from, to),
        },
      );
      $("pick-summary").textContent =
        mode === "navigate"
          ? "Drag to orbit; Shift-drag to pan. Clicks do not select."
          : `${new Set(projected.map((hit) => hit.target.id)).size.toLocaleString()} visible targets · ${mode === "sinks" ? "hover to reveal diamonds" : mode === "storage" ? "hover a storage span" : "hover to reveal circles"} · overlaps open a chooser`;
      $("pick-summary").title =
        "Targets are screen overlays, including those behind opaque geometry. Zoom in to separate nearby targets. Only the selected target class receives clicks.";
    },
    hover(pointer) {
      if (choices.length) return;
      pointerPosition = pointer;
      const hits = candidates(pointer);
      hovered = hits[0] ?? null;
      $("tooltip").hidden = !hovered;
      $("stack").style.cursor = hovered
        ? "pointer"
        : pickMode() === "navigate"
          ? "grab"
          : "crosshair";
      if (hovered) {
        $("tooltip").textContent =
          `${describe(hovered.target)}${hits.length > 1 ? ` · Click to choose from ${hits.length} targets` : " · Click to select"}`;
        $("tooltip").style.left =
          `${Math.max(4, Math.min(pointer.x + 14, $("stack").clientWidth - 330))}px`;
        $("tooltip").style.top =
          `${Math.max(4, Math.min(pointer.y + 14, $("stack").clientHeight - 95))}px`;
      }
      onOverlay();
    },
    click(pointer) {
      const hits = candidates(pointer);
      if (hits.length === 1) return choose(hits[0]);
      clear();
      if (!hits.length) {
        $("pick-notice").textContent =
          pickMode() === "navigate"
            ? "Navigate only: selection is disabled."
            : `No ${titles[pickMode()].toLowerCase()} at the cursor. Hover a marked target, zoom in, or use the list.`;
      } else {
        choices = hits;
        page = 0;
        hovered = hits[0];
        renderChoices();
        $("pick-chooser").hidden = false;
        $("pick-choices")
          .querySelector("button")
          .focus({ preventScroll: true });
      }
      onOverlay();
    },
    leave() {
      if (!choices.length) {
        pointerPosition = null;
        hovered = null;
        $("tooltip").hidden = true;
        onOverlay();
      }
    },
    draw(ctx) {
      ctx.save();
      const sink = pickMode() === "sinks";
      // Coalesce only marker paint at the same screen pixel, never candidate identities.
      const painted = new Set();
      const isSelected = (target) =>
        target.kind === "sink"
          ? target.sinkKey === selected.sinkKey
          : target.event?.id === selected.eventId;
      const targets = projected.filter(
        (hit) =>
          hit.shape === "point" &&
          ($("pick-all").checked ||
            isSelected(hit.target) ||
            (pointerPosition &&
              Math.hypot(
                hit.point.x - pointerPosition.x,
                hit.point.y - pointerPosition.y,
              ) <= 40)),
      );
      // Paint selected markers first so coalescing cannot replace their highlight.
      targets.sort(
        (a, b) => Number(isSelected(b.target)) - Number(isSelected(a.target)),
      );
      for (const hit of targets) {
        const { x, y } = hit.point;
        const key = `${Math.round(x)}/${Math.round(y)}`;
        if (painted.has(key)) continue;
        painted.add(key);
        ctx.beginPath();
        if (sink) {
          ctx.moveTo(x, y - 3);
          ctx.lineTo(x + 3, y);
          ctx.lineTo(x, y + 3);
          ctx.lineTo(x - 3, y);
          ctx.closePath();
        } else ctx.arc(x, y, 2.5, 0, Math.PI * 2);
        ctx.fillStyle = "#101b26";
        ctx.fill();
        ctx.lineWidth = 1;
        ctx.strokeStyle = isSelected(hit.target) ? "#ffe4a4" : "#b5c4cc";
        ctx.stroke();
      }
      if (hovered) {
        ctx.beginPath();
        if (hovered.shape === "segment") {
          ctx.moveTo(hovered.from.x, hovered.from.y);
          ctx.lineTo(hovered.to.x, hovered.to.y);
        } else ctx.arc(hovered.closest.x, hovered.closest.y, 8, 0, Math.PI * 2);
        ctx.strokeStyle = "#17212b";
        ctx.lineWidth = 5;
        ctx.stroke();
        ctx.strokeStyle = "#ffe4a4";
        ctx.lineWidth = 2;
        ctx.stroke();
      }
      ctx.restore();
    },
  };
}
