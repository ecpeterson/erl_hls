/** Bounded reader for saved Vivado full-clock-expanded setup reports. The
 * ordered data pins describe a static timing path, never a sensitized execution
 * edge or the physical wire geometry between those pins. */
const NUMBER = "[-+]?(?:[0-9]+(?:\\.[0-9]+)?|\\.[0-9]+)";
const PIN_ROW = /\s([rf])\s+(\S+\/\S+)\s*$/;
const DELAY_ROW = new RegExp(
  `(?:^|\\s)(${NUMBER})\\s+(${NUMBER})\\s+[rf]\\s+\\S+\\s*$`,
);
const NET_ROW = new RegExp(
  `^\\s*(?:\\S+\\s+)?net \\(fo=(\\d+)(?:, routed)?\\)\\s+(${NUMBER})\\s+(${NUMBER})\\s+(\\S+)\\s*$`,
);

/** Fail closed on missing fields or unsupported report shapes. */
function requireValue(condition, message) {
  if (!condition) throw new Error(`Timing report: ${message}`);
}

/** A primitive pin is separated from its exact native cell name by the final
 * slash. This does not infer names from generated-register suffixes. */
function pinCell(pin) {
  const split = pin.lastIndexOf("/");
  requireValue(split > 0 && split < pin.length - 1, `invalid pin ${pin}`);
  return pin.slice(0, split);
}

/** Read a required scalar from a header, preserving report decimal units. */
function field(block, expression, name) {
  const found = block.match(expression);
  requireValue(found, `missing ${name}`);
  return found[1];
}

/** Reported numbers are finite; absent step delays remain null, never zero. */
function numeric(value, name) {
  const result = Number(value);
  requireValue(Number.isFinite(result), `invalid ${name}`);
  return result;
}

/** Read one ordered data section after the launch clock pin. Continuation
 * lines carrying cell delays are supported independently of the preceding
 * site/primitive descriptor, as emitted for long Vivado delay-type names. */
function dataSection(lines, source, endpoint, cells, maxSteps) {
  const begin = lines.findIndex((line) => line.match(PIN_ROW)?.[2] === source);
  requireValue(begin >= 0, `missing launch clock row ${source}`);
  const steps = [],
    arcs = [],
    seen = new Set();
  let net = null,
    ended = false;
  for (const line of lines.slice(begin + 1)) {
    const nextNet = line.match(NET_ROW);
    if (nextNet) {
      requireValue(steps.length && !net, "unpaired data net");
      net = {
        net: nextNet[4],
        fanout: numeric(nextNet[1], "fanout"),
        delayNs: numeric(nextNet[2], "net delay"),
        arrivalNs: numeric(nextNet[3], "net arrival"),
      };
      continue;
    }
    // A malformed net record must not become a guessed internal logic arc.
    requireValue(!/\bnet\s*\(/.test(line), "unsupported net row");
    const pinRow = line.match(PIN_ROW);
    if (!pinRow) {
      requireValue(
        !/\(clock |required time|arrival time|slack\s/.test(line),
        `missing endpoint ${endpoint}`,
      );
      continue;
    }
    const pin = pinRow[2],
      cell = pinCell(pin),
      delay = line.match(DELAY_ROW);
    requireValue(cells.has(cell), `unknown cell ${cell}`);
    requireValue(!seen.has(pin), `repeated data pin ${pin}`);
    requireValue(steps.length < maxSteps, "data-pin limit exceeded");
    seen.add(pin);
    const step = {
      pin,
      cell,
      transition: pinRow[1],
      incrementNs: delay ? numeric(delay[1], "pin delay") : null,
      arrivalNs: delay ? numeric(delay[2], "pin arrival") : null,
    };
    if (!steps.length) {
      requireValue(
        cell === pinCell(source) && pin !== source,
        "data path does not start at launch cell output",
      );
      requireValue(delay, "missing clock-to-output delay");
    } else {
      const previous = steps.at(-1);
      if (net) {
        arcs.push({ kind: "net", source: previous.pin, target: pin, ...net });
        net = null;
      } else {
        requireValue(
          previous.cell === cell && delay,
          `missing interconnect or logic delay before ${pin}`,
        );
        arcs.push({
          kind: "logic",
          source: previous.pin,
          target: pin,
          delayNs: step.incrementNs,
          arrivalNs: step.arrivalNs,
        });
      }
    }
    steps.push(step);
    if (pin === endpoint) {
      ended = true;
      break;
    }
  }
  requireValue(
    ended && steps.length >= 2 && !net,
    `missing endpoint ${endpoint}`,
  );
  return { launchPin: steps[0].pin, steps, arcs };
}

/** Parse saved Vivado setup paths with exact native cell identities. Inputs are
 * a UTF-8 report string and the matching catalogue's cell array (or ID map).
 * Bounds default to 4 MiB, 100 paths and 512 pins per path. Unsupported/malformed
 * headers, missing endpoints/delays and unknown cells throw before rendering.
 *
 * Each result retains source clock pin, launch data pin, endpoint, static ns
 * summary, ordered steps and logic/net arcs. A step with no printed numeric
 * fields has nulls. Clock branches are excluded; the first step separately
 * retains clock-to-output delay. Connections have no routed polyline geometry.
 * Callers must authenticate report bytes and bind checkpoint/build identities;
 * this parser does not infer dynamic bit use, activation or electrical activity.
 */
export function parseTimingPaths(
  report,
  { cells, maxBytes = 4 * 1024 * 1024, maxPaths = 100, maxSteps = 512 } = {},
) {
  for (const bound of [maxBytes, maxPaths, maxSteps])
    requireValue(
      Number.isSafeInteger(bound) && bound > 0,
      "invalid parser bound",
    );
  requireValue(
    typeof report === "string" && Buffer.byteLength(report, "utf8") <= maxBytes,
    "report byte limit exceeded",
  );
  requireValue(
    cells instanceof Map || Array.isArray(cells),
    "missing cell catalogue",
  );
  const cellMap =
    cells instanceof Map
      ? cells
      : new Map(cells.map((cell) => [cell.id, cell]));
  requireValue(
    cells instanceof Map || cellMap.size === cells.length,
    "duplicate catalogue cell",
  );
  const text = report.replaceAll("\r\n", "\n");
  const blocks = text.split(/(?=^Slack \()/m).slice(1);
  if (!blocks.length) {
    requireValue(
      text.trim() === "No constrained timing paths returned for max.",
      "no setup path headers",
    );
    return [];
  }
  requireValue(blocks.length <= maxPaths, "path limit exceeded");
  return blocks.map((block, index) => {
    const source = field(block, /^\s*Source:\s+(\S+)\s*$/m, "source"),
      endpoint = field(block, /^\s*Destination:\s+(\S+)\s*$/m, "endpoint");
    requireValue(cellMap.has(pinCell(source)), `unknown source cell ${source}`);
    requireValue(
      cellMap.has(pinCell(endpoint)),
      `unknown endpoint cell ${endpoint}`,
    );
    requireValue(
      /^\s*Path Type:\s+Setup \(Max at [^)]+\)\s*$/m.test(block),
      "unsupported path type",
    );
    const summary = block.match(
      new RegExp(
        `Data Path Delay:\\s+(${NUMBER})ns\\s+\\(logic\\s+(${NUMBER})ns[^\\n]*?route\\s+(${NUMBER})ns`,
      ),
    );
    requireValue(summary, "missing data/logic/route delay summary");
    const body = dataSection(
      block.split("\n"),
      source,
      endpoint,
      cellMap,
      maxSteps,
    );
    const logicLevels = numeric(
      field(block, /^\s*Logic Levels:\s+(\d+)/m, "logic levels"),
      "logic levels",
    );
    requireValue(
      body.arcs.filter((arc) => arc.kind === "logic").length === logicLevels,
      "data-pin sequence disagrees with reported logic levels",
    );
    return {
      id: `max/${index}`,
      source,
      endpoint,
      slackNs: numeric(
        field(
          block,
          new RegExp(`^Slack \\([^)]*\\)\\s*:\\s*(${NUMBER})ns`, "m"),
          "slack",
        ),
        "slack",
      ),
      dataDelayNs: numeric(summary[1], "data delay"),
      logicDelayNs: numeric(summary[2], "logic delay"),
      routeDelayNs: numeric(summary[3], "route delay"),
      logicLevels,
      ...body,
    };
  });
}
