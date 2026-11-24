/** Project native post-route setup checks, keeping the backend's ps increments and exact pin order. */
export function openxc7Paths(report, top) {
  const check = (condition) => {
    if (!condition) throw Error("Inconsistent nextpnr critical path");
  };
  check(
    report.schema === 1 &&
      report.unit === "ps" &&
      Array.isArray(report.paths) &&
      report.paths.length <= 100,
  );
  const ranked = report.ranked_endpoints;
  if (ranked !== undefined) {
    check(
      Array.isArray(ranked) &&
        Number.isSafeInteger(report.endpoint_limit) &&
        report.endpoint_limit > 0 &&
        report.endpoint_limit <= 100 &&
        Number.isSafeInteger(report.eligible_endpoints) &&
        report.eligible_endpoints >= 0 &&
        ranked.length ===
          Math.min(report.endpoint_limit, report.eligible_endpoints),
    );
  }
  const fanout = new Map();
  for (const cell of Object.values(top.cells)) {
    for (const [p, bits] of Object.entries(cell.connections)) {
      if (cell.port_directions[p] !== "input") continue;
      for (const bit of bits) fanout.set(bit, (fanout.get(bit) ?? 0) + 1);
    }
  }
  const paths = [],
    unchecked = [];
  const seen = new Set();
  let priorSlack = -Infinity;
  for (const [index, path] of report.paths.concat(ranked ?? []).entries()) {
    const rank = index - report.paths.length;
    const points = path.points;
    check(Array.isArray(points) && points.length && points.length <= 513);
    let total = 0;
    for (const p of points) {
      check(
        Number.isSafeInteger(p.delay_ps) &&
          p.delay_ps >= 0 &&
          (total += p.delay_ps) === p.arrival_ps &&
          Object.hasOwn(top.cells[p.cell]?.connections ?? {}, p.port),
      );
    }
    if (path.required_ps === null && path.slack_ps === null) {
      unchecked.push({
        launch: path.launch_clock,
        capture: path.capture_clock,
        arrivalPs: total,
      });
      continue;
    }
    const setup = points.at(-1);
    check(
      points[0].kind === "clock_to_q" &&
        setup.kind === "setup" &&
        typeof path.launch_clock === "string" &&
        path.launch_clock.length > 0 &&
        ["rising", "falling"].includes(path.launch_edge) &&
        path.launch_clock === path.capture_clock &&
        path.launch_edge === path.capture_edge &&
        Number.isSafeInteger(path.required_ps) &&
        path.required_ps > 0 &&
        total === path.path_delay_ps &&
        path.required_ps - total === path.slack_ps,
    );
    const steps = [],
      arcs = [];
    let routePs = 0;
    for (const [i, p] of points.slice(0, -1).entries()) {
      const step = {
        cell: p.cell,
        pin: p.cell + "/" + p.port,
        transition: null,
        incrementNs: p.delay_ps / 1000,
        arrivalNs: p.arrival_ps / 1000,
      };
      if (i) {
        const source = points[i - 1];
        const arc = {
          kind: p.kind,
          source: steps[i - 1].pin,
          target: step.pin,
          delayNs: step.incrementNs,
          arrivalNs: step.arrivalNs,
        };
        if (p.kind === "net") {
          const [wire] = top.netnames[p.net]?.bits ?? [];
          check(
            wire !== undefined &&
              top.cells[p.cell].connections[p.port][0] === wire &&
              top.cells[source.cell].connections[source.port][0] === wire &&
              fanout.has(wire),
          );
          Object.assign(arc, { net: p.net, fanout: fanout.get(wire) });
          routePs += p.delay_ps;
        } else check(p.kind === "logic" && p.cell === source.cell);
        arcs.push(arc);
      }
      steps.push(step);
    }
    check(steps.at(-1).pin === setup.cell + "/" + setup.port);
    if (ranked && rank < 0) continue;
    if (ranked) {
      const endpoint = steps.at(-1).pin;
      check(!seen.has(endpoint) && path.slack_ps >= priorSlack);
      seen.add(endpoint);
      priorSlack = path.slack_ps;
    }
    const dataPs = total - setup.delay_ps;
    paths.push({
      id: `setup/${ranked ? rank : index}`,
      ...(ranked && { rank: rank + 1 }),
      source: steps[0].pin,
      launchPin: steps[0].pin,
      endpoint: steps.at(-1).pin,
      dataDelayNs: dataPs / 1000,
      logicDelayNs: (dataPs - routePs) / 1000,
      routeDelayNs: routePs / 1000,
      setupNs: setup.delay_ps / 1000,
      requiredNs: path.required_ps / 1000,
      slackNs: path.slack_ps / 1000,
      clock: path.launch_clock,
      clockEdge: path.launch_edge,
      logicLevels: arcs.filter((a) => a.kind === "logic").length,
      steps,
      arcs,
    });
  }
  const ranking = ranked && {
    selection: "least_slack_per_capture_pin",
    eligible: report.eligible_endpoints,
    limit: report.endpoint_limit,
    retained: ranked.length,
  };
  return { paths, unchecked, ranking };
}
