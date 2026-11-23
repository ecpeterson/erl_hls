import assert from "node:assert/strict";
import test from "node:test";
import { createSceneSelection } from "../web/scene-selection.js";

// Only the DOM behavior used by chooser lifecycle and keyboard focus. This is
// a controller witness, not a substitute for browser layout or GPU picking.
function controls(t) {
  const previous = globalThis.document,
    nodes = new Map();
  const element = (tagName = "div") => ({
    tagName,
    value: "",
    textContent: "",
    title: "",
    hidden: false,
    disabled: false,
    style: {},
    children: [],
    clientWidth: 800,
    clientHeight: 600,
    replaceChildren(...children) {
      this.children = children;
    },
    querySelector(selector) {
      return selector === "button"
        ? this.children.find((child) => child.tagName === "button")
        : null;
    },
    focus() {
      globalThis.document.activeElement = this;
      this.onfocus?.();
    },
    click() {
      this.onclick?.();
    },
  });
  const node = (id) => {
    if (!nodes.has(id)) {
      const value = element();
      if (id === "pick-mode") value.value = "sinks";
      if (id === "pick-chooser" || id === "tooltip") value.hidden = true;
      nodes.set(id, value);
    }
    return nodes.get(id);
  };
  globalThis.document = {
    getElementById: node,
    createElement: element,
    activeElement: null,
  };
  t.after(() => {
    globalThis.document = previous;
  });
  return node;
}
const project = ([x, y, depth]) => ({ x, y, depth, visible: true });
const scene = {
  project,
  projectSegment: (from, to) => [project(from), project(to)],
};
const pointer = { x: 10, y: 10 };
const sink = (i) => ({
  kind: "sink",
  id: `sink/${String(i).padStart(3, "0")}`,
  sinkKey: `data/${i}`,
  role: "data",
  pin: i,
  pinName: `cell_${i}/D`,
  cycle: 4,
  arrivalNs: 3,
  position: [10, 10, 0.5],
});
const event = (id, accessKind) => ({
  kind: "event",
  id,
  position: [10, 10, 0.1],
  event: {
    id,
    actor: "actor/0",
    operation: "state",
    cycle: 4,
    access: { kind: accessKind, resource: "state/0" },
  },
});
const storage = {
  kind: "storage",
  id: "version/0",
  from: [10, 0, 0.2],
  to: [10, 20, 0.8],
  segment: {
    kind: "hold",
    version: "version/0",
    fromCycle: 4,
    toCycle: 7,
    resource: "state/0",
  },
  point: { cell: "cell_0" },
};

test("reads and writes are explicit classes, and hover never chooses evidence", (t) => {
  const node = controls(t),
    chosen = [];
  let overlays = 0;
  const panel = createSceneSelection({
    onChoose: (target) => {
      chosen.push(target);
      return true;
    },
    onOverlay: () => overlays++,
  });
  const read = event("read/0", "read"),
    write = event("write/0", "write");
  const targets = [
    sink(0),
    storage,
    write,
    read,
    { ...read, position: [11, 10, 0.3] },
    event("result/0", "read_result"),
  ];
  node("pick-mode").value = "reads";
  panel.project(targets, scene);
  assert.match(node("pick-summary").textContent, /1 visible targets/);
  panel.hover(pointer);
  assert.match(node("tooltip").textContent, /^Read event/);
  assert.equal(node("tooltip").hidden, false);
  assert.equal(node("stack").style.cursor, "pointer");
  assert.equal(chosen.length, 0);
  assert.ok(overlays > 0);
  panel.click(pointer);
  assert.deepEqual(
    chosen.map((target) => target.id),
    ["read/0"],
  );
  assert.equal(
    node("pick-chooser").hidden,
    true,
    "physical copies still choose one event",
  );

  panel.invalidate();
  node("pick-mode").value = "writes";
  panel.hover(pointer);
  panel.click(pointer);
  assert.equal(
    chosen.length,
    1,
    "no old read target survives until reprojection",
  );
  panel.project(targets, scene);
  panel.hover(pointer);
  assert.match(node("tooltip").textContent, /^Write event/);
  assert.equal(chosen.length, 1);
  panel.click(pointer);
  assert.deepEqual(
    chosen.map((target) => target.id),
    ["read/0", "write/0"],
  );
});

test("overlapping sinks offer every target through paging without selecting on hover or focus", (t) => {
  const node = controls(t),
    chosen = [];
  const panel = createSceneSelection({
    onChoose: (target) => {
      chosen.push(target);
      return true;
    },
    onOverlay: () => {},
  });
  const targets = Array.from({ length: 19 }, (_, i) => sink(i));
  panel.project([...targets].reverse(), scene);
  panel.hover(pointer);
  assert.match(node("tooltip").textContent, /Click to choose from 19 targets/);
  assert.equal(chosen.length, 0);
  panel.click(pointer);
  assert.equal(node("pick-chooser").hidden, false);
  assert.match(node("pick-heading").textContent, /^19 targets at cursor/);
  assert.equal(node("pick-choices").children.length, 8);
  assert.equal(
    globalThis.document.activeElement,
    node("pick-choices").children[0],
  );
  const firstPageButton = node("pick-choices").children[0],
    labels = [];
  let lastButton;
  for (;;) {
    for (const button of node("pick-choices").children) {
      labels.push(button.textContent);
      button.onmouseenter();
      button.focus();
      lastButton = button;
    }
    assert.equal(chosen.length, 0);
    if (node("pick-next").disabled) break;
    node("pick-next").click();
  }
  assert.equal(labels.length, 19);
  assert.equal(new Set(labels).size, 19);
  assert.equal(node("pick-page").textContent, "3 / 3");
  assert.equal(node("pick-choices").children.length, 3);
  firstPageButton.click();
  assert.equal(
    chosen.length,
    0,
    "an obsolete page cannot choose a hidden entry",
  );
  lastButton.click();
  assert.equal(chosen[0], targets[18]);
  assert.match(
    node("pick-notice").textContent,
    /Selected Timing sink.*cell_18\/D/,
  );
  assert.equal(node("pick-chooser").hidden, true);
});

test("clear closes choices, while invalidation and reset also discard projected targets", (t) => {
  const node = controls(t),
    chosen = [];
  let overlays = 0;
  const panel = createSceneSelection({
    onChoose: (target) => {
      chosen.push(target);
      return true;
    },
    onOverlay: () => overlays++,
  });
  panel.project([sink(0), sink(1)], scene);
  panel.click(pointer);
  const closed = node("pick-choices").children[0];
  panel.clear();
  const afterClear = overlays;
  assert.equal(node("pick-chooser").hidden, true);
  assert.equal(node("tooltip").hidden, true);
  assert.equal(node("pick-choices").children.length, 0);
  closed.click();
  closed.focus();
  closed.onmouseenter();
  assert.equal(chosen.length, 0);
  assert.equal(overlays, afterClear, "closed callbacks cannot restore hover");

  panel.click(pointer);
  assert.equal(
    node("pick-chooser").hidden,
    false,
    "clear retains current projected evidence",
  );
  const retired = node("pick-choices").children[0];
  panel.reset();
  retired.click();
  retired.focus();
  panel.click(pointer);
  assert.equal(chosen.length, 0);
  assert.equal(node("pick-chooser").hidden, true);
  assert.match(node("pick-notice").textContent, /No timing sinks/);
  panel.project([sink(2)], scene);
  panel.invalidate();
  panel.click(pointer);
  assert.equal(chosen.length, 0);
  panel.project([sink(3)], scene);
  panel.click(pointer);
  assert.deepEqual(
    chosen.map((target) => target.sinkKey),
    ["data/3"],
  );
  panel.reset();
  assert.equal(node("pick-notice").textContent, "");
});

test("rejected stale identities produce a failure notice and retire their chooser", (t) => {
  const node = controls(t),
    attempts = [];
  const panel = createSceneSelection({
    onChoose: (target) => {
      attempts.push(target.id);
      return false;
    },
    onOverlay: () => {},
  });
  panel.project([sink(0), sink(1)], scene);
  panel.click(pointer);
  const button = node("pick-choices").children[0];
  button.click();
  assert.deepEqual(attempts, ["sink/000"]);
  assert.match(
    node("pick-notice").textContent,
    /no longer in the current view/,
  );
  assert.doesNotMatch(node("pick-notice").textContent, /^Selected/);
  assert.equal(node("pick-chooser").hidden, true);
  assert.equal(node("tooltip").hidden, true);
  button.click();
  assert.equal(attempts.length, 1);
});

test("storage has its own line target, and navigate mode never selects", (t) => {
  const node = controls(t),
    chosen = [];
  const panel = createSceneSelection({
    onChoose: (target) => {
      chosen.push(target);
      return true;
    },
    onOverlay: () => {},
  });
  const targets = [storage, sink(0), event("write/0", "write")];
  node("pick-mode").value = "storage";
  panel.project(targets, scene);
  panel.hover(pointer);
  assert.match(node("tooltip").textContent, /^Residence.*version\/0/);
  panel.click(pointer);
  assert.equal(chosen[0], storage);
  panel.invalidate();
  node("pick-mode").value = "navigate";
  panel.project(targets, scene);
  panel.hover(pointer);
  assert.equal(node("tooltip").hidden, true);
  assert.equal(node("stack").style.cursor, "grab");
  panel.click(pointer);
  assert.equal(chosen.length, 1);
  assert.match(node("pick-notice").textContent, /selection is disabled/);
});
