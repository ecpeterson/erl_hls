#!/usr/bin/env python3
"""Generate passive channel/FIFO queries from Yosys elaborated connectivity.

Resources describe physical handshakes and existing FIFO occupancy, not actor
continuations. Hierarchical port aliases are collapsed by connectivity; the
deepest endpoints name the observed boundary.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path
import re
import subprocess

import topology_debug_actors as actors


SCHEMA = 3
FIFO = re.compile(r"fifo_for_depth_(\d+)_ty_.*_with_bypass(?:_register_push)?(?:___\d+)?$")
PORT_PAIRS = (("_vld", "_rdy"), ("_valid", "_ready"), ("_tvalid", "_tready"))


def channel_ports(module):
    """Require a one-bit, oppositely directed handshake pair."""
    ports = module["ports"]
    for valid_name, valid in sorted(ports.items()):
        for valid_suffix, ready_suffix in PORT_PAIRS:
            if not valid_name.endswith(valid_suffix):
                continue
            stem = valid_name[:-len(valid_suffix)]
            ready_name = stem + ready_suffix
            if ready_name not in ports:
                raise ValueError(f"missing ready port for {valid_name}")
            ready = ports[ready_name]
            if len(valid["bits"]) != 1 or len(ready["bits"]) != 1:
                raise ValueError(f"handshake must be one bit: {stem}")
            if {valid["direction"], ready["direction"]} != {"input", "output"}:
                raise ValueError(f"handshake directions disagree: {stem}")
            yield stem, valid_name, ready_name, valid["direction"]
            break


def descendants(hierarchy, top):
    modules = hierarchy["modules"]

    def walk(name, path, ancestors):
        if name in ancestors:
            raise ValueError(f"recursive module hierarchy at {path}")
        module = modules[name]
        yield path, name, module
        for instance, cell in sorted(module.get("cells", {}).items()):
            if cell["type"] in modules:
                yield from walk(cell["type"], (*path, instance), (*ancestors, name))

    yield from walk(top, (), ())


def flat_bit(flat, path, name):
    key = ".".join((*path, name))
    try:
        bits = flat["netnames"][key]["bits"]
    except KeyError:
        raise ValueError(f"flattening lost probe {key}") from None
    if len(bits) != 1:
        raise ValueError(f"probe {key} has width {len(bits)}")
    return bits[0]


def deepest(endpoints):
    # Container ports forwarded into a child are aliases, not additional actors.
    return [endpoint for endpoint in endpoints if not any(
        other["path"][:len(endpoint["path"])] == endpoint["path"] and
        len(other["path"]) > len(endpoint["path"])
        for other in endpoints
    )]


def discover(hierarchy, flat_design, top, clock):
    flat = flat_design["modules"][top]
    root_clock = flat_bit(flat, (), clock)
    channels = defaultdict(list)
    for path, module_name, module in descendants(hierarchy, top):
        pairs = list(channel_ports(module))
        if not pairs:
            continue
        clocks = [name for name in ("clk", "aclk", "clock") if name in module["ports"]]
        if len(clocks) != 1 or flat_bit(flat, path, clocks[0]) != root_clock:
            raise ValueError(f"unsupported clock domain at {'.'.join(path) or top}")
        # Depth-zero XLS FIFOs are wires, not stateful graph vertices.
        if FIFO.fullmatch(module_name) and module_name.startswith("fifo_for_depth_0_"):
            continue
        for stem, valid_name, ready_name, direction in pairs:
            valid = flat_bit(flat, path, valid_name)
            ready = flat_bit(flat, path, ready_name)
            endpoint = {"path": list(path), "module": module_name, "port": stem,
                        "role": "producer" if direction == "output" else "consumer"}
            # At the application boundary, the external world has the opposite role.
            if not path:
                endpoint["role"] = "consumer" if direction == "output" else "producer"
                endpoint["external"] = True
            channels[valid, ready].append(endpoint)

    probes = []
    for (valid, ready), aliases in channels.items():
        # Constant inactive ports are explicitly retained in the manifest; they
        # can reveal tied-off connections and do not consume new application state.
        endpoints = []
        for role in ("producer", "consumer"):
            group = [entry for entry in aliases if entry["role"] == role]
            endpoints.extend([entry for entry in group if entry.get("external")])
            endpoints.extend(deepest([entry for entry in group if not entry.get("external")]))
        label = min("/".join((*entry["path"], entry["port"])) for entry in endpoints)
        probes.append({"name": label, "valid_bit": valid, "ready_bit": ready,
                       "endpoints": endpoints, "aliases": aliases,
                       "constant_handshake": isinstance(valid, str) or isinstance(ready, str)})
    probes.sort(key=lambda probe: probe["name"])
    for index, probe in enumerate(probes):
        probe["id"] = index
    if not probes:
        raise ValueError("no ready/valid channels discovered")
    return probes


def fifo_resources(hierarchy, flat_design, top, probes):
    """Read the existing XLS FIFO slots register; never count transfers again.

    This adapter deliberately supports only the checked, unregistered-pop XLS
    FIFO shape. A different implementation remains a handshake-only vertex.
    Validate the full comparator and register instead of trusting a name alone.
    """
    flat = flat_design["modules"][top]
    channel_ids = {(p["valid_bit"], p["ready_bit"]): p["id"] for p in probes}
    queues, unsupported = [], []
    for path, name, module in descendants(hierarchy, top):
        if not name.startswith("fifo_for_depth_"):
            continue
        match = FIFO.fullmatch(name)
        if not match:
            unsupported.append({"path": list(path), "module": name,
                                "reason": "unsupported XLS FIFO implementation"})
            continue
        capacity = int(match[1])
        if capacity == 0:
            continue
        nets = module["netnames"]
        slots = nets.get("slots", {}).get("bits", [])
        full = nets.get("is_full_bool", {}).get("bits", [])
        cells = list(module.get("cells", {}).values())
        registered = any(c["type"] == "$dff" and c["connections"]["Q"] == slots and
                         c["connections"]["CLK"] == module["ports"]["clk"]["bits"] and
                         int(c["parameters"]["CLK_POLARITY"], 2) == 1 for c in cells)
        compared = False
        for cell in cells:
            if cell["type"] != "$eq" or cell["connections"]["Y"] != full:
                continue
            a, b = cell["connections"]["A"], cell["connections"]["B"]
            if b == slots:
                a, b = b, a
            if a == slots and all(bit in ("0", "1") for bit in b):
                compared |= int("".join(reversed(b)), 2) == capacity
        if not (0 < len(slots) <= 32 and registered and compared):
            raise ValueError(f"unrecognized XLS FIFO occupancy at {'/'.join(path)}")
        occupancy = flat["netnames"][".".join((*path, "slots"))]["bits"]
        def channel(stem):
            pair = tuple(flat_bit(flat, path, stem + suffix) for suffix in ("_valid", "_ready"))
            return channel_ids[pair]
        queues.append({"kind": "fifo", "name": "/".join(path), "path": list(path),
                       "module": name, "capacity": capacity, "width": len(slots),
                       "bits": occupancy, "push": channel("push"), "pop": channel("pop")})
    return queues, unsupported


def resources_for(probes, queues):
    resources = [{"id": p["id"], "kind": "channel", "name": p["name"], "width": 2,
                  "bits": [p["valid_bit"], p["ready_bit"]]} for p in probes]
    for queue in sorted(queues, key=lambda q: q["name"]):
        resources.append(dict(queue, id=len(resources)))
    return resources


def export_probes(flat_design, top, resources, output_top, banks=()):
    """Only add an output alias. No cell, memory, or application port is edited."""
    module = flat_design["modules"][top]
    outputs = {"hls_probe_values": [bit for resource in resources for bit in
               resource["bits"] + ["0"]*(32-resource["width"])]}
    if banks:
        outputs["hls_actor_writes"] = [bit for bank in banks for bit in bank["taps"]]
    for name, bits in outputs.items():
        if name in module["ports"] or name in module["netnames"]:
            raise ValueError(f"reserved probe name already exists: {name}")
        module["ports"][name] = {"direction": "output", "bits": bits}
        module["netnames"][name] = {"hide_name": 0, "bits": bits, "attributes": {}}
    return {"creator": flat_design.get("creator", ""), "modules": {output_top: module}}


def quote(path):
    return '"' + str(path).replace('\\', '\\\\').replace('"', '\\"') + '"'


def yosys_run(yosys, script, stage, name):
    path = stage / f"{name}.ys"
    path.write_text(script)
    with (stage / f"{name}.log").open("w") as log:
        subprocess.run([yosys, "-Q", "-T", "-s", str(path)], stdout=log,
                       stderr=subprocess.STDOUT, check=True)


def debug_wrapper(ports, application_top, resources, channels, fingerprint, clock, reset, active_low, banks=()):
    debug = [("input", 32, "s_dbg_tdata"), ("input", 4, "s_dbg_tkeep"),
             ("input", 1, "s_dbg_tlast"), ("input", 1, "s_dbg_tvalid"),
             ("output", 1, "s_dbg_tready"), ("output", 32, "m_dbg_tdata"),
             ("output", 4, "m_dbg_tkeep"), ("output", 1, "m_dbg_tlast"),
             ("output", 1, "m_dbg_tvalid"), ("input", 1, "m_dbg_tready")]
    if any(name in ports for _, _, name in debug):
        raise ValueError("application already exposes the reserved debug interface")
    declarations = [(port["direction"], len(port["bits"]), name) for name, port in ports.items()]
    def declaration(direction, width, name):
        return f"    {direction} wire [{width-1}:0] \\{name} "
    connections = [f".\\{name} (\\{name} )" for name in ports]
    actor_count = sum(bank["slots"] for bank in banks)
    physical_count = resources - actor_count
    taps_width = sum(len(bank["taps"]) for bank in banks)
    tap_wire = f"wire [{taps_width-1}:0] actor_writes;\n" if banks else ""
    tap_port = ", .hls_actor_writes(actor_writes)" if banks else ""
    hash_literal = int.from_bytes(bytes.fromhex(fingerprint), "little")
    return ("// Generated passive topology debug wrapper. Application ports are unchanged.\n"
            "module hls_debug_application (\n" +
            ",\n".join(declaration(*port) for port in declarations + debug) + "\n);\n" +
            f"wire [{32*resources-1}:0] probe_values;\n" + tap_wire +
            f"{application_top} application (" + ", ".join(connections) +
            f", .hls_probe_values(probe_values[0 +: {32*physical_count}])" + tap_port + ");\n" +
            actors.wrapper(banks, physical_count, clock, reset, active_low) +
            "wire [31:0] request_data, response_data;\n"
            "wire [3:0] request_keep, response_keep;\n"
            "wire request_last, request_valid, request_ready;\n"
            "wire response_last, response_valid, response_ready;\n"
            "hls_debug_route #(.ENDPOINT(2)) route (\n"
            f"    .clk(\\{clock} ), .reset({'!' if active_low else ''}\\{reset} ),\n"
            "    .s_data(s_dbg_tdata), .s_keep(s_dbg_tkeep), .s_last(s_dbg_tlast),\n"
            "    .s_valid(s_dbg_tvalid), .s_ready(s_dbg_tready),\n"
            "    .m_data(m_dbg_tdata), .m_keep(m_dbg_tkeep), .m_last(m_dbg_tlast),\n"
            "    .m_valid(m_dbg_tvalid), .m_ready(m_dbg_tready),\n"
            "    .request_data(request_data), .request_keep(request_keep), .request_last(request_last),\n"
            "    .request_valid(request_valid), .request_ready(request_ready),\n"
            "    .response_data(response_data), .response_keep(response_keep), .response_last(response_last),\n"
            "    .response_valid(response_valid), .response_ready(response_ready));\n" +
            f"hls_topology_debug #(.RESOURCES({resources}), .CHANNELS({channels}), .ACTORS({actor_count}),\n" +
            f"    .FINGERPRINT(256'h{hash_literal:064x})) debug (\n" +
            f"    .clk(\\{clock} ), .reset({'!' if active_low else ''}\\{reset} ), .probe_values(probe_values),\n"
            "    .s_data(request_data), .s_keep(request_keep), .s_last(request_last),\n"
            "    .s_valid(request_valid), .s_ready(request_ready),\n"
            "    .m_data(response_data), .m_keep(response_keep), .m_last(response_last),\n"
            "    .m_valid(response_valid), .m_ready(response_ready));\nendmodule\n")


def instrument(args):
    for identifier in (args.top, args.clock, args.reset, args.output_top):
        if not re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_$]*", identifier):
            raise ValueError(f"invalid RTL identifier: {identifier}")
    stage = args.stage.resolve()
    stage.mkdir(parents=True, exist_ok=True)
    files = [path.resolve() for path in args.rtl]
    yosys_run(args.yosys, "read_verilog -sv " + " ".join(map(quote, files)) +
              f"\nhierarchy -check -top {args.top}\nproc\n" +
              f"write_json {quote(stage / 'hierarchy.json')}\nflatten\n" +
              f"write_json {quote(stage / 'flat.json')}\n", stage, "elaborate")
    hierarchy = json.loads((stage / "hierarchy.json").read_text())
    flat = json.loads((stage / "flat.json").read_text())
    probes = discover(hierarchy, flat, args.top, args.clock)
    queues, unsupported = fifo_resources(hierarchy, flat, args.top, probes)
    resources = resources_for(probes, queues)
    physical = list(resources)
    banks, projection = [], None
    if getattr(args, "actor_projection", None):
        projection = json.loads(args.actor_projection.read_text())
        root = args.actor_root.split(".") if args.actor_root else []
        banks = actors.discover(projection, root, hierarchy, flat["modules"][args.top],
                                args.top, flat_bit(flat["modules"][args.top], (), args.clock))
        resources.extend(actors.resources(banks, len(resources)))
    ports = dict(flat["modules"][args.top]["ports"])
    for control in (args.clock, args.reset):
        if control not in ports or ports[control]["direction"] != "input" or len(ports[control]["bits"]) != 1:
            raise ValueError(f"expected one-bit input {control}")
    manifest = {"schema": SCHEMA, "top": args.top, "clock": args.clock,
                "reset": args.reset, "reset_active_low": args.reset_active_low,
                "resources": resources, "unsupported_queues": unsupported,
                "sources": [{"name": path.name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
                            for path in files], "probes": probes}
    if banks:
        manifest["actor_projection"] = projection
        manifest["actor_root"] = root
    canonical = json.dumps(manifest, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()
    manifest["fingerprint"] = hashlib.sha256(canonical).hexdigest()
    (stage / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (stage / "debug_top.v").write_text(debug_wrapper(
        ports, args.output_top, len(resources), len(probes), manifest["fingerprint"],
        args.clock, args.reset, args.reset_active_low, banks))
    exported = export_probes(flat, args.top, physical, args.output_top, banks)
    (stage / "instrumented.json").write_text(json.dumps(exported))
    yosys_run(args.yosys, f"read_json {quote(stage / 'instrumented.json')}\n" +
              f"opt_clean -purge\nwrite_verilog -noattr {quote(stage / 'instrumented.v')}\n", stage, "export")
    print(f"Exported {len(probes)} channels, {len(queues)} FIFO occupancies, {len(resources)-len(physical)} actors; manifest {manifest['fingerprint']}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("rtl", type=Path, nargs="+")
    parser.add_argument("--top", required=True)
    parser.add_argument("--clock", default="clk")
    parser.add_argument("--output-top", default="hls_instrumented_application")
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--reset", default="reset")
    parser.add_argument("--reset-active-low", action="store_true")
    parser.add_argument("--yosys", default="yosys")
    parser.add_argument("--actor-projection", type=Path)
    parser.add_argument("--actor-root", default="", help="instance path of the shell containing scheduler RAMs")
    instrument(parser.parse_args())


if __name__ == "__main__":
    main()
