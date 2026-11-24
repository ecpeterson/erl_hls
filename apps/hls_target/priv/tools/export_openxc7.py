"""Capture XC7 placement, selected routes and optional native timing for one Verilog top."""

import argparse
import hashlib
import json
import mmap
from pathlib import Path
import resource
import shutil
from openxc7_chipdb import ChipGrid
from openxc7_routes import build_routes
from openxc7_storage import qualify_words
import subprocess


MAX_BYTES = 64 << 20
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
    if args.rtl.stat().st_size + args.xdc.stat().st_size > args.max_bytes:
        raise ValueError("input byte limit")
    shutil.copyfile(args.rtl, out / "design.v")
    shutil.copyfile(args.xdc, out / "design.xdc")
    packages = args.apio_home.resolve() / "packages"
    yosys, nextpnr = packages / "oss-cad-suite", packages / "openxc7"
    chipdb = args.chipdb.resolve()
    tools = {"yosys": package(yosys, "yosys"), "nextpnr": package(nextpnr, "nextpnr-xilinx")}
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
    inventory = FILES
    router = nextpnr / "bin/nextpnr-xilinx"
    if args.timing_tools:
        if not 0 < args.max_timing_objects <= 100_000:
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
    if args.route_net:
        limits["route_objects"] = args.max_route_objects
        write_json(out / "route-request.json", {"nets": args.route_net, "max_objects": args.max_route_objects})
        if args.timing_tools:
            route.extend(["--spacetime-route-request", "route-request.json"])
        else:
            shutil.copyfile(Path(__file__).with_name("openxc7_pins.py"), out / "openxc7_pins.py")
            route.extend(["--post-route", "openxc7_pins.py"])
            inventory += ("openxc7_pins.py",)
        route.extend(["--write-fixed-routes", "fixed-routes.txt"])
        inventory += ROUTE_FILES
    write_json(out / "manifest.json", manifest)
    run_tool([yosys / "bin/yosys", "-Q", "-p", SYNTH], out, "yosys.log", args.max_bytes)
    run_tool([router, "--chipdb", chipdb, *route], out,
             "nextpnr.log", args.max_bytes)
    size = sum((out / file).stat().st_size for file in inventory if (out / file).exists())
    if size > args.max_bytes:
        raise ValueError("export byte limit")
    top = json.loads((out / "routed.json").read_bytes())["modules"]["top"]
    if int(top["settings"].get("route", "0"), 2) != 1:
        raise ValueError("missing completed route")
    cells = top["cells"]
    if len(cells) > args.max_cells:
        raise ValueError("export cell limit")
    if args.timing_tools:
        timing = json.loads((out / "timing.json").read_bytes())
        if (set(cells) != set(timing["cells"]) or timing["objects"] > args.max_timing_objects
                or timing["unit"] != "ps"):
            raise ValueError("timing census differs from implementation")
        missing = sum(s["delay_ps"] is None for s in timing["sinks"]) + sum(
            arc["delay_ps"] is None for c in timing["cells"].values() for arc in c["arcs"])
        manifest["timing"] = {"objects": timing["objects"], "unresolved_delays": missing,
                              "model": "nextpnr-xilinx single structural estimate", "unit": "ps",
                              "clock_model": "compiled setup, hold and clock-to-Q constants",
                              "database_origin": "per-entry characterization/borrowing unverified"}
        if args.storage_word:
            synth = json.loads((out / "synth.json").read_bytes())["modules"]["top"]
            words = qualify_words(args.storage_word, synth, cells, timing, args.max_timing_objects)
            write_json(out / "storage.json", words)
            inventory += ("storage.json",)
            manifest["storage"] = {"words": len(words), "bits": sum(len(w["bits"]) for w in words),
                                   "unknown": sum(b["status"] == "unknown" for w in words for b in w["bits"])}
        if args.route_net:
            write_json(out / "native-pins.json", timing["selected_routes"])
    bels = [cell["attributes"].get("NEXTPNR_BEL", "") for cell in cells.values()]
    prefixes = [bel.split("/", 1)[0] for bel in bels]
    with chipdb.open("rb") as stream, mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as data:
        grid = ChipGrid(data)
        part = grid.part
        locations = {p: grid.location(p) for p in set(prefixes) if p in grid.owners}
        if args.route_net:
            graph = build_routes(grid, out / "fixed-routes.txt",
                                 json.loads((out / "native-pins.json").read_bytes()), args.max_route_objects)
            write_json(out / "routes.json", graph)
            manifest["routing"] = {"objects": graph["objects"], "unresolved": graph["unresolved"]}
    write_json(out / "locations.json", locations)
    files = {file: identity(out / file) for file in inventory}
    size = sum(entry["bytes"] for entry in files.values())
    if size > args.max_bytes:
        raise ValueError("export byte limit")
    if identity(chipdb)["sha256"] != database["sha256"] or (
            "overlay" in database and part != database["overlay"]["part"]):
        raise ValueError("chipdb changed during capture")
    manifest.update(complete=True, part=part, chipdb=database, tools=tools,
                    source=args.source_id, observation=args.observation_id, synth=SYNTH,
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
    for key in ("rtl", "xdc", "apio-home", "chipdb"):
        parser.add_argument("--" + key, type=Path, required=True)
    for key in ("source-id", "observation-id"):
        parser.add_argument("--" + key, required=True)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--chipdb-manifest", type=Path, help="package overlay manifest bound by the chipdb toolchain stamp")
    parser.add_argument("--freq", type=int, default=25, help="target frequency in MHz")
    parser.add_argument("--max-cells", type=int, default=MAX_CELLS)
    parser.add_argument("--route-net", action="append", default=[], help="retain routes for this net or alias")
    parser.add_argument("--max-route-objects", type=int, default=100_000)
    parser.add_argument("--timing-tools", type=Path, help="pinned build_spacetime.sh output directory")
    parser.add_argument("--max-timing-objects", type=int, default=100_000)
    parser.add_argument("--storage-word", action="append", default=[], metavar="RESOURCE=RTL_NET",
                        help="qualify the LSB-first bits of an explicitly associated synthesis net")
    parser.add_argument("--max-bytes", type=int, default=MAX_BYTES)
    parser.add_argument("output", type=Path)
    capture(parser.parse_args())


if __name__ == "__main__":
    main()
