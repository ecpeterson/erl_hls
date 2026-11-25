"""Capture XC7 placement, selected routes and optional native timing for one Verilog top."""

import argparse
import hashlib
import json
import mmap
from pathlib import Path
import re
import resource
import shlex
import shutil
from openxc7_chipdb import ChipGrid
from openxc7_routes import build_routes
from openxc7_endpoints import qualify_selected
from openxc7_storage import qualify_words
import subprocess


DEFAULT_BYTES = 64 << 20
MAX_BYTES = 384 << 20
MAX_CELLS = 100_000
FILES = ("design.v", "design.xdc", "synth.json", "routed.json", "locations.json")
ROUTE_FILES = ("route-request.json", "native-pins.json", "fixed-routes.txt", "routes.json")
SYNTH = ("read_verilog -sv design.v; synth_xilinx -family xc7 -top top; "
         "select top; write_json -selected synth.json")


def write_json(path: Path, data: object) -> None:
    """Write one deterministic UTF-8 document; the manifest digest binds these bytes."""
    path.write_text(json.dumps(data, sort_keys=True, separators=(",", ":")) + "\n",
                    encoding="utf-8")


def identity(path: Path) -> dict:
    """Hash exact file bytes without loading an executable or chip database into memory."""
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1 << 20):
            digest.update(chunk)
    return {"bytes": path.stat().st_size, "sha256": digest.hexdigest()}


def package(root: Path, name: str) -> dict:
    """Identify both the Apio launcher and the native binary it runs."""
    return {"build": json.loads((root / "BUILD-INFO.json").read_bytes()),
            "launcher": identity(root / "bin" / name),
            "executable": identity(root / "libexec" / name)}


def run_tool(command: list, out: Path, log: str, byte_limit: int) -> None:
    """Bound each native output file and retain the console, including on tool failure."""
    def limit_files() -> None:
        """Apply the capture ceiling to files created by the child process."""
        resource.setrlimit(resource.RLIMIT_FSIZE, (byte_limit, byte_limit))

    with (out / log).open("xb") as stream:
        subprocess.run(command, cwd=out, stdout=stream, stderr=subprocess.STDOUT,
                       timeout=300, check=True, preexec_fn=limit_files)


def stage_rtl(paths: list[Path], out: Path, flatten: bool) -> tuple[str, tuple[str, ...]]:
    """Read an ordered, explicitly closed source list. Bind every member into the RTL identity."""
    if len(paths) == 1:
        shutil.copyfile(paths[0], out / "design.v")
        sources = ["design.v"]
        inventory = ()
    else:
        if not 2 <= len(paths) <= 64:
            raise ValueError("source list must contain 1..64 files")
        sources = [f"input-{i:02d}.sv" for i in range(len(paths))]
        for path, name in zip(paths, sources):
            shutil.copyfile(path, out / name)
        # This self-contained source index is itself the RTL build digest.
        (out / "design.v").write_text("".join(
            f'// sha256 {identity(out / name)["sha256"]}\n`include "{name}"\n' for name in sources))
        inventory = tuple(sources)
    script = SYNTH.replace("read_verilog -sv design.v", "read_verilog -sv " + " ".join(sources))
    if flatten:
        script = script.replace("-family xc7", "-family xc7 -flatten")
    return script, inventory


def check_source_reads(out: Path, staged: tuple[str, ...], library: Path) -> None:
    """Reject ordered builds whose Yosys dependency report names unstaged application inputs."""
    target, separator, inputs = (out / "sources.d").read_text().partition(":")
    if target != "synth.json" or not separator:
        raise ValueError("missing Yosys synthesis dependency report")
    paths = {(out / name).resolve() for name in shlex.split(inputs)}
    application = {path for path in paths if not path.is_relative_to(library.resolve())}
    if application != {(out / name).resolve() for name in staged}:
        raise ValueError("Yosys read application inputs outside the ordered RTL list")


def focus_roots(requests: list[str], synth: dict, words: list[str] | None = None) -> list[str]:
    """Resolve exact LSB-first RTL bits to unique synthesis FDRE outputs before packing."""
    drivers = {}
    for name, cell in synth["cells"].items():
        for port, bits in cell["connections"].items():
            if cell["port_directions"][port] in ("output", "inout"):
                for bit in bits:
                    if isinstance(bit, int):
                        drivers.setdefault(bit, []).append((cell["type"], port, name))
    roots = set()
    for word in words or []:
        for bit in synth["netnames"][word]["bits"]:
            candidates = drivers.get(bit, [])
            if len(candidates) == 1 and candidates[0][:2] == ("FDRE", "Q"):
                roots.add(candidates[0][2])
    for request in requests:
        match = re.fullmatch(r"(.+)\[(\d+)\]", request)
        if not match:
            raise ValueError(f"invalid NET[BIT]: {request}")
        signal = synth["netnames"][match[1]]["bits"][int(match[2])]
        candidates = drivers.get(signal, [])
        if len(candidates) != 1 or candidates[0][:2] != ("FDRE", "Q"):
            raise ValueError(f"no unique FDRE output for {request}")
        roots.add(candidates[0][2])
    return sorted(roots)


def fanin_cells(cells: dict, roots: list[str]) -> set[str]:
    """Independently check the post-route cell closure using the serialized packed pin connections."""
    if not roots:
        return set(cells)
    drivers = {bit: name for name, cell in cells.items() for port, bits in cell["connections"].items()
               if cell["port_directions"][port] == "output" for bit in bits}
    seen = set(roots)
    todo = list(seen)
    targets = set(roots)
    while todo:
        name = todo.pop()
        cell = cells[name]
        if name not in targets and cell["type"] not in ("CARRY4", "INV", "SELMUX2_1", "SLICE_LUTX"):
            continue
        if {"X_LUT_AS_SRL", "X_LUT_AS_DRAM"} & cell["attributes"].keys():
            continue
        for port, bits in cell["connections"].items():
            if port in ("CK", "C") or cell["port_directions"][port] != "input":
                continue
            for bit in bits:
                driver = drivers.get(bit)
                if driver is not None and driver not in seen:
                    seen.add(driver)
                    todo.append(driver)
    return seen


def capture(args: argparse.Namespace) -> None:
    """Run one file-top implementation and publish a complete inventory only after checking it."""
    out = args.output
    out.mkdir()
    limits = {"cells": args.max_cells, "bytes": args.max_bytes}
    manifest = {"format": "openxc7_placement", "schema": 1, "complete": False, "limits": limits}
    write_json(out / "manifest.json", manifest)
    if not (0 < args.max_cells <= MAX_CELLS and 0 < args.max_bytes <= MAX_BYTES):
        raise ValueError("export limits outside supported range")
    if not args.source_id or not args.observation_id:
        raise ValueError("source and observation identities must be nonempty")
    if not 0 < args.max_route_objects <= 100_000:
        raise ValueError("route object limit outside supported range")
    if args.storage_word and not args.timing_tools:
        raise ValueError("storage qualification needs native packed-port provenance")
    if sum(p.stat().st_size for p in args.rtl) + args.xdc.stat().st_size > args.max_bytes:
        raise ValueError("input byte limit")
    synth_script, sources = stage_rtl(args.rtl, out, args.flatten)
    shutil.copyfile(args.xdc, out / "design.xdc")
    packages = args.apio_home.resolve() / "packages"
    yosys, nextpnr = packages / "oss-cad-suite", packages / "openxc7"
    chipdb = args.chipdb.resolve()
    tools = {"yosys": package(yosys, "yosys"), "nextpnr": package(nextpnr, "nextpnr-xilinx")}
    tools["yosys"]["xc7-bram-map"] = identity(yosys / "share/yosys/xilinx/brams_xc6v_map.v")
    database = identity(chipdb)
    if args.chipdb_manifest:
        with args.chipdb_manifest.open("rb") as stream:
            overlay = stream.read((1 << 20) + 1)
        if len(overlay) > 1 << 20:
            raise ValueError("chipdb overlay manifest limit")
        part_stamp, package_hash, overlay_hash = Path(str(chipdb) + ".toolchain").read_text().split()
        if (hashlib.sha256(overlay).hexdigest() != overlay_hash or
                identity(nextpnr / "BUILD-INFO.json")["sha256"] != package_hash):
            raise ValueError("chipdb package/overlay stamp mismatch")
        meta = json.loads(overlay)
        if meta["part"] != part_stamp:
            raise ValueError("chipdb overlay part mismatch")
        database["overlay"] = {"sha256": overlay_hash, "part": part_stamp, "reference": meta["reference"],
                               "inputs": meta["database_sha256"], "outputs": meta["outputs_sha256"]}
    route = ["--xdc", "design.xdc", "--json", "synth.json", "--write", "routed.json",
             "--seed", str(args.seed), "--freq", str(args.freq), "--placer", "heap",
             "--router", "router2"]
    inventory = FILES + sources
    if sources:
        manifest["source_files"] = list(sources)
    focused = bool(args.focus_bit or args.focus_word)
    if (focused or args.sta) and not args.timing_tools:
        raise ValueError("scoped timing and STA require the native observer")
    router = nextpnr / "bin/nextpnr-xilinx"
    if args.timing_tools:
        if not 0 < args.max_timing_objects <= (650_000 if focused else 100_000):
            raise ValueError("timing object limit outside supported range")
        router = args.timing_tools.resolve() / "bin/nextpnr-spacetime"
        build = json.loads(router.with_name("spacetime-build.json").read_bytes())
        binary = identity(router)
        if build["sha256"][router.name] != binary["sha256"]:
            raise ValueError("timing backend differs from its build receipt")
        tools["nextpnr"] = {"build": build, "launcher": binary, "executable": binary}
        limits["timing_objects"] = args.max_timing_objects
        inventory += ("timing.json",)
        route.extend(["--spacetime-timing", "timing.json", "--spacetime-objects", str(args.max_timing_objects)])
    if args.sta_endpoints and (not args.sta or not 1 <= args.sta_endpoints <= 100):
        raise ValueError("ranked endpoint count requires --sta and a limit of 1 to 100")
    if args.sta:
        route.extend(["--spacetime-sta", "sta.json"])
        if args.sta_endpoints:
            route.extend(["--spacetime-sta-endpoints", str(args.sta_endpoints)])
        manifest["sta"] = {"unit": "ps", "model": "nextpnr-xilinx"}
        inventory += ("sta.json",)
    if focused:
        route.extend(["--spacetime-roots", "roots.json"])
        inventory += ("roots.json",)
    if args.allow_timing_fail:
        route.append("--timing-allow-fail")
    capture_routes = args.route_all or bool(args.route_net) or args.route_root_data or args.route_sta or bool(args.route_bit)
    if args.route_sta and not args.sta:
        raise ValueError("STA routes require --sta")
    if (args.route_root_data or args.route_bit) and not focused:
        raise ValueError("root-data routes require --focus-bit")
    if capture_routes:
        limits["route_objects"] = args.max_route_objects
        request = {"nets": args.route_net, "max_objects": args.max_route_objects}
        if args.route_checkpoint:
            if not re.fullmatch("[a-f0-9]{64}", args.route_checkpoint):
                raise ValueError("invalid frozen route digest")
            request["expected_checkpoint"] = args.route_checkpoint
        if args.route_sta:
            request["sta_nets"] = True
        if args.route_root_data:
            request["root_data"] = True
        if args.route_all:
            request["all"] = True
        write_json(out / "route-request.json", request)
        if args.timing_tools:
            route.extend(["--spacetime-route-request", "route-request.json"])
        else:
            shutil.copyfile(Path(__file__).with_name("openxc7_pins.py"), out / "openxc7_pins.py")
            route.extend(["--post-route", "openxc7_pins.py"])
            inventory += ("openxc7_pins.py",)
        route.extend(["--write-fixed-routes", "fixed-routes.txt"])
        inventory += ROUTE_FILES
    write_json(out / "manifest.json", manifest)
    dependency_args = ["-E", "sources.d"] if sources else []
    run_tool([yosys / "bin/yosys", "-Q", *dependency_args, "-p", synth_script], out, "yosys.log", args.max_bytes)
    if sources:
        check_source_reads(out, sources, yosys / "share/yosys")
    roots = []
    if focused:
        synth = json.loads((out / "synth.json").read_bytes())["modules"]["top"]
        roots = focus_roots(args.focus_bit, synth, args.focus_word)
        if not roots:
            raise ValueError("focus contains no unique FDRE outputs")
        if args.route_bit:
            request["data_roots"] = focus_roots(args.route_bit, synth)
            if not set(request["data_roots"]) <= set(roots):
                raise ValueError("data route outside selected scope")
            write_json(out / "route-request.json", request)
        write_json(out / "roots.json", roots)
    run_tool([router, "--chipdb", chipdb, *route], out,
             "nextpnr.log", args.max_bytes)
    size = sum((out / file).stat().st_size for file in inventory if (out / file).exists())
    if size > args.max_bytes:
        raise ValueError("export byte limit")
    if args.route_checkpoint and identity(out / "routed.json")["sha256"] != args.route_checkpoint:
        raise ValueError("route demand belongs to a different implementation checkpoint")
    top = json.loads((out / "routed.json").read_bytes())["modules"]["top"]
    if int(top["settings"].get("route", "0"), 2) != 1:
        raise ValueError("missing completed route")
    cells = top["cells"]
    if len(cells) > args.max_cells:
        raise ValueError("export cell limit")
    if args.timing_tools:
        timing = json.loads((out / "timing.json").read_bytes())
        observed = set(timing["cells"])
        valid = observed == fanin_cells(cells, roots)
        if (not valid or sorted(timing.get("roots", [])) != roots or timing["objects"] > args.max_timing_objects
                or timing["unit"] != "ps"):
            raise ValueError("timing census differs from implementation")
        missing = sum(s["delay_ps"] is None for s in timing["sinks"]) + sum(
            arc["delay_ps"] is None for c in timing["cells"].values() for arc in c["arcs"])
        manifest["timing"] = {"objects": timing["objects"], "unresolved_delays": missing,
                              "model": "nextpnr-xilinx single structural estimate", "unit": "ps",
                              "clock_model": "compiled setup, hold and clock-to-Q constants",
                              "database_origin": "per-entry characterization/borrowing unverified"}
        if roots:
            manifest["timing"]["focus_bits"] = args.focus_bit
            manifest["timing"]["focus_words"] = args.focus_word
            manifest["timing"]["cells"] = len(observed)
        if args.storage_word:
            synth = json.loads((out / "synth.json").read_bytes())["modules"]["top"]
            words = qualify_words(args.storage_word, synth, cells, timing, args.max_timing_objects)
            write_json(out / "storage.json", words)
            inventory += ("storage.json",)
            manifest["storage"] = {"words": len(words), "bits": sum(len(w["bits"]) for w in words),
                                   "unknown": sum(b["status"] == "unknown" for w in words for b in w["bits"])}
        if capture_routes:
            write_json(out / "native-pins.json", timing["selected_routes"])
    bels = [cell["attributes"].get("NEXTPNR_BEL", "") for cell in cells.values()]
    prefixes = [bel.split("/", 1)[0] for bel in bels]
    with chipdb.open("rb") as stream, mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as data:
        grid = ChipGrid(data)
        part = grid.part
        locations = {p: grid.location(p) for p in set(prefixes) if p in grid.owners}
        if capture_routes:
            native = json.loads((out / "native-pins.json").read_bytes())
            if args.route_all and native.keys() != top["netnames"].keys():
                raise ValueError("whole-design route net census differs from routed JSON")
            graph = build_routes(grid, out / "fixed-routes.txt", native, args.max_route_objects)
            qualify_selected(grid, top, graph)
            write_json(out / "routes.json", graph)
            manifest["routing"] = {"objects": graph["objects"], "unresolved": graph["unresolved"]}
    if args.timing_tools and part == "xc7z030sbg485-1":
        lut_delay_patch = "nextpnr-xc7-lut-route-delay.patch"
        if lut_delay_patch in build["sha256"]:
            manifest["timing"]["lut_route_delay_patch_sha256"] = build["sha256"][lut_delay_patch]
        if "nextpnr-spacetime-carry.patch" in build["sha256"]:
            manifest["timing"]["carry_di_model"] = "maximum of available chipdb CARRY4 variants at the placed site"
        if "registered_dsp.inc" in build["sha256"]:
            manifest["timing"]["registered_dsp_model_sha256"] = build["sha256"]["registered_dsp.inc"]
        if "xc7_bram_model.inc" in build["sha256"]:
            manifest["timing"]["bram_model_sha256"] = build["sha256"]["xc7_bram_model.inc"]
    write_json(out / "locations.json", locations)
    files = {file: identity(out / file) for file in inventory}
    size = sum(entry["bytes"] for entry in files.values())
    if size > args.max_bytes:
        raise ValueError("export byte limit")
    if identity(chipdb)["sha256"] != database["sha256"] or (
            "overlay" in database and part != database["overlay"]["part"]):
        raise ValueError("chipdb changed during capture")
    manifest.update(complete=True, part=part, chipdb=database, tools=tools,
                    source=args.source_id, observation=args.observation_id, synth=synth_script,
                    nextpnr_args=route, files=files, bytes=size, cells=len(cells),
                    unresolved=sum(prefix not in locations for prefix in prefixes))
    write_json(out / "manifest.tmp", manifest)
    if (out / "manifest.tmp").stat().st_size > 1 << 20:
        raise ValueError("implementation manifest limit")
    build = {"source": args.source_id, "rtl": files["design.v"]["sha256"],
             "observation": args.observation_id,
             "implementation": identity(out / "manifest.tmp")["sha256"]}
    # Hex binary literals also preserve UTF-8 labels containing quotes, newlines or backslashes.
    fields = [f"{key} => <<{','.join(map(str, value.encode()))}>>" for key, value in build.items()]
    checkpoint = files["routed.json"]["sha256"]
    (out / "identity.term").write_text("#{build => #{" + ", ".join(fields) +
                                       '}, checkpoint => <<"' + checkpoint + '">>}.\n')
    (out / "manifest.tmp").replace(out / "manifest.json")


def main() -> None:
    """Capture a fresh bounded directory for offline import with an explicit tool installation."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rtl", type=Path, required=True, action="append", help="ordered self-contained source file (repeatable)")
    parser.add_argument("--flatten", action="store_true")
    parser.add_argument("--focus-bit", action="append", default=[], metavar="NET[BIT]")
    parser.add_argument("--focus-word", action="append", default=[], metavar="NET", help="include every unique FDRE bit of the named word")
    parser.add_argument("--route-bit", action="append", default=[], metavar="NET[BIT]", help="capture this selected FF data branch")
    parser.add_argument("--route-root-data", action="store_true", help="export the data nets of selected FDREs")
    parser.add_argument("--route-checkpoint", help="require the exact routed JSON digest for a saved demand")
    parser.add_argument("--route-sta", action="store_true", help="capture nets on the reported STA paths of this route")
    parser.add_argument("--sta", action="store_true", help="export ordered native critical paths")
    parser.add_argument("--sta-endpoints", type=int, default=0, help="also retain up to N distinct single-clock setup endpoints, ordered by slack (1–100)")
    parser.add_argument("--allow-timing-fail", action="store_true", help="retain a routed measurement when the clock target fails")
    for key in ("xdc", "apio-home", "chipdb"):
        parser.add_argument("--" + key, type=Path, required=True)
    for key in ("source-id", "observation-id"):
        parser.add_argument("--" + key, required=True)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--chipdb-manifest", type=Path, help="package overlay manifest bound by the chipdb toolchain stamp")
    parser.add_argument("--freq", type=int, default=25, help="target frequency in MHz")
    parser.add_argument("--max-cells", type=int, default=MAX_CELLS)
    selection = parser.add_mutually_exclusive_group()
    selection.add_argument("--route-net", action="append", default=[], help="retain routes for this net or alias")
    selection.add_argument("--route-all", action="store_true", help="retain every packed net within the route budget")
    parser.add_argument("--max-route-objects", type=int, default=100_000)
    parser.add_argument("--timing-tools", type=Path, help="pinned build_spacetime.sh output directory")
    parser.add_argument("--max-timing-objects", type=int, default=100_000)
    parser.add_argument("--storage-word", action="append", default=[], metavar="RESOURCE=RTL_NET",
                        help="qualify the LSB-first bits of an explicitly associated synthesis net")
    parser.add_argument("--max-bytes", type=int, default=DEFAULT_BYTES)
    parser.add_argument("output", type=Path)
    capture(parser.parse_args())


if __name__ == "__main__":
    main()
