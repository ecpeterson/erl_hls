/** Match a global STA endpoint to retained prepared circuitry using exact pin
 * identity and explicit write-to-cone associations, never hierarchy guesses.
 */
export function clockSink(index, endpoint, { firstCycle, endCycle } = {}) {
  if (!index?.prepared)
    return {
      status: "unavailable",
      reason: "Prepared circuitry is not loaded.",
    };
  const pins = [];
  index.pinGeometry.forEach((pin, id) => {
    if (pin[3] === endpoint) pins.push(id);
  });
  if (pins.length !== 1)
    return {
      status: "unavailable",
      reason: pins.length
        ? "The exact endpoint has ambiguous retained pin identities."
        : "The exact STA endpoint is absent from retained pin geometry.",
    };
  const pin = pins[0];
  const cones = new Map();
  index.cones.forEach((cone, id) => {
    if (cone.rootPins.includes(pin)) cones.set(id, cone);
  });
  const candidates = [];
  for (const [id, write] of index.writes) {
    const event = index.model.events.get(id);
    for (const coneId of write.cones) {
      const cone = cones.get(coneId);
      if (!cone) continue;
      candidates.push({
        event,
        pin,
        role: cone.role,
        key: `${cone.role}/${pin}`,
        withinStep: event.cycle >= firstCycle && event.cycle < endCycle,
      });
    }
  }
  const roleRank = { data: 0, enable: 1, reset: 2 };
  candidates.sort(
    (a, b) =>
      Number(b.withinStep) - Number(a.withinStep) ||
      a.event.cycle - b.event.cycle ||
      roleRank[a.role] - roleRank[b.role] ||
      a.event.id.localeCompare(b.event.id),
  );
  return candidates.length
    ? { status: "available", ...candidates[0] }
    : {
        status: "unavailable",
        reason: "No recorded write is associated with this exact root pin.",
      };
}
