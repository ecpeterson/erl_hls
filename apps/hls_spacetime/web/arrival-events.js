/** Event clocks alone do not locate an operation within a clock. This module
 * qualifies only sampled scalar-register boundaries; native propagation keeps
 * its independently derived arrival heights. No operation name implies time.
 */
import { eventCoordinate } from "./arrival-layout.js";

/** Preserve an untimed event as evidence without assigning a display phase. */
function unknown(reason) {
  return { kind: "unknown", coordinate: null, reason };
}

/** Locate an event only when its explicit storage semantics supply a boundary.
 * Zero-latency, read-first/forbidden register requests, their matching results
 * and register holds anchor sampled Q at B_C. A register write anchors capture
 * at B_(C+1) only with a following sample in this incarnation. These are reference boundaries, not measured
 * switching times or a claim that the associated computation takes no time.
 * Semantic operations, forwarded reads and RAM responses remain untimed.
 * The input is a validated model event; neither it nor its resource is changed.
 */
export function arrivalEventAnchor(model, event) {
  const access = event.access;
  if (!access) return unknown("operation_has_no_boundary_anchor");
  const resource = model.resources.get(access.resource);
  if (!["ff", "register"].includes(resource?.kind) || resource.depth !== 1)
    return unknown("resource_has_no_scalar_register_anchor");
  if (access.kind === "write") {
    const epoch = model.epochs.get(event.incarnation);
    if (!epoch || event.cycle + 1 >= epoch.end_cycle)
      return unknown("no_following_sample_in_incarnation");
    return { kind: "register_capture", coordinate: eventCoordinate(event) };
  }
  if (access.kind === "read_result") {
    const request = model.events?.get(access.request);
    if (
      resource.read_latency !== 0 ||
      request?.access?.kind !== "read_request" ||
      request.cycle !== event.cycle ||
      request.incarnation !== event.incarnation ||
      ["resource", "address", "port", "version", "read_mask"].some(
        (key) => request.access[key] !== access[key],
      )
    )
      return unknown("response_has_no_sampled_q_request");
    return arrivalEventAnchor(model, request);
  }
  if (
    access.kind === "hold" ||
    (access.kind === "read_request" &&
      resource.read_latency === 0 &&
      ["read_first", "forbidden"].includes(resource.collision))
  )
    return { kind: "register_q_sample", coordinate: eventCoordinate(event) };
  return unknown("access_has_no_sampled_q_anchor");
}

/** A recorded dependency may join qualified boundaries, but cannot give an
 * untimed endpoint a phase. Same-cycle forwarding and reset crossings never
 * become backward or cross-incarnation arrival geometry. This function does
 * not invent a combinational path or infer delay between the boundaries.
 */
export function arrivalEventConnection(model, from, to) {
  const source = arrivalEventAnchor(model, from);
  const target = arrivalEventAnchor(model, to);
  if (
    source.coordinate === null ||
    target.coordinate === null ||
    from.incarnation !== to.incarnation ||
    source.coordinate > target.coordinate
  )
    return null;
  return { from: source.coordinate, to: target.coordinate };
}
