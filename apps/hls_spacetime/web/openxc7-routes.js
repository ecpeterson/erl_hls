import { createNativeRouting, nativeConnection } from "./native-routes.js";

/** Index the selected nets only for their exact joined implementation and packed cell census. */
export function openxc7Routing(model, detail) {
  if (!detail) return null;
  const { implementation, checkpoint, nets } = detail;
  if (
    !model.catalogue ||
    typeof implementation !== "string" ||
    !implementation.length ||
    implementation !== model.bundle.build.implementation ||
    checkpoint !== model.catalogue.checkpoint ||
    !Array.isArray(nets)
  )
    throw Error("openXC7 route implementation or checkpoint mismatch");
  for (const net of nets)
    for (const ref of net.pin_attachments)
      if (
        ref.cell !== null &&
        (!model.cells.has(ref.cell) || ref.pin !== `${ref.cell}/${ref.port}`)
      )
        throw Error("openXC7 route pin outside packed cell census");
  const index = createNativeRouting(nets, { nets: 100000 });
  if (
    detail.packedNetCount !== undefined &&
    !(
      Number.isSafeInteger(detail.packedNetCount) &&
      detail.packedNetCount >= index.nets.size
    )
  )
    throw Error("openXC7 packed net count disagrees with captured routing");
  return { ...index, packedNetCount: detail.packedNetCount };
}

/** Show one sink at a time. Tile marks are footprints; ordered PIPs retain same-tile site routing. */
export function showOpenxc7Routes(panel, index) {
  panel.hidden = !index;
  if (!index) return;
  const netSelect = panel.querySelector("[data-net]"),
    sinkSelect = panel.querySelector("[data-sink]");
  const summary = panel.querySelector("output"),
    switches = panel.querySelector("ol");
  const canvas = panel.querySelector("canvas"),
    context = canvas.getContext("2d");
  panel.querySelector("[data-net-count]").textContent =
    index.packedNetCount === undefined
      ? `${index.nets.size} nets captured`
      : `${index.nets.size} of ${index.packedNetCount} packed nets captured`;
  function chooseSink() {
    switches.replaceChildren();
    context.clearRect(0, 0, canvas.width, canvas.height);
    const net = index.nets.get(netSelect.value).net;
    const driver = net.pin_attachments.find((pin) => pin.direction === "OUT");
    if (!driver || !sinkSelect.value) {
      summary.textContent = "No driver-to-sink branch supplied";
      return;
    }
    const route = nativeConnection(index, net.id, driver.pin, sinkSelect.value);
    summary.textContent = [
      `${driver.pin} → ${sinkSelect.value} · ${route.disposition}`,
      ...route.gaps.map((gap) => gap.reason),
    ].join(" · ");
    for (const pip of route.pips) {
      const row = document.createElement("li");
      row.textContent = pip.id;
      switches.append(row);
    }
    const dots = route.nodes
      .flatMap((node) => node.wires)
      .filter((w) => Number.isFinite(w.x) && Number.isFinite(w.y));
    if (!dots.length) return;
    let minX = Infinity,
      minY = Infinity,
      maxX = -Infinity,
      maxY = -Infinity;
    for (const { x, y } of dots) {
      minX = Math.min(minX, x);
      maxX = Math.max(maxX, x);
      minY = Math.min(minY, y);
      maxY = Math.max(maxY, y);
    }
    const scale = Math.min(
      (canvas.width - 16) / Math.max(1, maxX - minX),
      (canvas.height - 16) / Math.max(1, maxY - minY),
    );
    for (const [points, color, size] of [
      [dots, "#7199bf", 5],
      [route.pips, "#dd9f44", 3],
    ]) {
      context.fillStyle = color;
      for (const p of points)
        if (Number.isFinite(p.x) && Number.isFinite(p.y))
          context.fillRect(
            8 + (p.x - minX) * scale - size / 2,
            8 + (p.y - minY) * scale - size / 2,
            size,
            size,
          );
    }
  }
  function chooseNet() {
    const net = index.nets.get(netSelect.value).net;
    sinkSelect.replaceChildren();
    for (const p of net.pin_attachments)
      if (p.direction === "IN") sinkSelect.add(new Option(p.pin, p.pin));
    chooseSink();
  }
  netSelect.replaceChildren();
  for (const { net } of index.nets.values()) {
    const names = [net.id, ...net.aliases.filter((a) => a !== net.id)];
    netSelect.add(new Option(names.join(" / "), net.id));
  }
  netSelect.onchange = chooseNet;
  sinkSelect.onchange = chooseSink;
  if (netSelect.value) chooseNet();
}
