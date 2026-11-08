import test from "node:test";
import assert from "node:assert/strict";
import { createSinkInspector } from "../web/sink-inspector.js";

// Minimal DOM surface for controller transitions, not a rendering substitute.
function controls(t) {
  const previous = globalThis.document,
    nodes = new Map();
  const node = (id) => {
    if (!nodes.has(id))
      nodes.set(id, {
        value:
          id === "sink-margin" ? "0.5" : id === "sink-mode" ? "selected" : "",
        innerHTML: "",
        textContent: "",
        disabled: false,
        hidden: false,
        replaceChildren() {
          this.innerHTML = "";
        },
        checkValidity() {
          return this.value !== "" && Number(this.value) >= 0;
        },
        reportValidity() {
          this.reported = true;
          return false;
        },
        closest() {
          return this;
        },
      });
    return nodes.get(id);
  };
  globalThis.document = { getElementById: node, querySelectorAll: () => [] };
  t.after(() => {
    globalThis.document = previous;
  });
  return node;
}
const empty = () => ({
  cones: [],
  pinGeometry: [],
  arcGeometry: [],
  writes: new Map(),
  model: { events: new Map() },
});
test("hidden sink inspector cannot retain focus or filter another layout", (t) => {
  controls(t);
  const panel = createSinkInspector(() => {}),
    index = empty(),
    layers = [];
  panel.update(index, layers, { enabled: true, scope: "registered" });
  assert.equal(panel.focused, true);
  assert.ok(panel.selection instanceof Map);
  panel.update(index, layers, { enabled: false, scope: "registered" });
  assert.equal(panel.focused, false);
  assert.equal(panel.selection, null);
  assert.equal(panel.activeArc, null);
  panel.update(index, layers, { enabled: true, scope: "registered" });
  assert.equal(panel.focused, true);
  assert.ok(panel.selection instanceof Map);
});
test("invalid margin cannot break a subsequent filter or scope update", (t) => {
  const node = controls(t);
  let updates = 0;
  const panel = createSinkInspector(() => updates++),
    index = empty();
  node("sink-mode").value = "near";
  panel.update(index, [], { enabled: true, scope: "registered" });
  node("sink-margin").value = "-1";
  node("sink-margin").onchange();
  assert.equal(node("sink-margin").reported, true);
  assert.equal(updates, 0);
  assert.doesNotThrow(() =>
    panel.update(index, [], { enabled: true, scope: "static" }),
  );
  node("sink-margin").value = "2";
  node("sink-margin").onchange();
  assert.equal(updates, 1);
  assert.doesNotThrow(() =>
    panel.update(index, [], { enabled: true, scope: "static" }),
  );
});
