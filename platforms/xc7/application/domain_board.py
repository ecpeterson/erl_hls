#!/usr/bin/env python3
"""Qualify one frozen domain-board image with offline external tools only.

This driver consumes ordinary source-build/compiled releases; it never emits
application sources, runs XLS, downloads tools, programs boards or retries a
failed phase. Invoke prepare, map, route and assemble separately so the complete
connected area gates are reviewable before the sole route attempt. Every phase
needs the parent campaign's serial physical-footprint guard.
"""

import argparse
from collections import Counter
import json
from pathlib import Path
import re
import subprocess
import sys
import time
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from xc7_resources import counts, digest, report
from map_xc7_resources import quoted, stop_group
from application.link_board import inspect
from application import domain_board_clocks
from gtx.assemble import assemble
from gtx.clock_cascades import PINS as CLOCK_DONORS
from gtx.prepare import audit_database
from lut_legality.check import check as check_luts

TOP = "te0715_domain_link_top"
BOUNDS = {"lut_site_upper_bound": 70740, "ff": 141480,
          "bram18_equivalents": 476, "dsp": 360, "latches": 0}
LINK_BOUNDS = {"lut_site_upper_bound": 8000, "ff": 11000}
GROUPS = {
    "domain": "application.network.role_unit.local_domain.",
    "endpoints": "application.network.role_unit.endpoint_",
    "packet_router": "application.network.packets_unit.",
    "endpoint_management": "application.network.management_unit.",
    "board_control": "application.host_control.",
    "carrier": "framing.",
    "host_dma": "transport.",
    "mac": "packets.",
}
PHYSICAL = ["zynq_ps_probe.v", "dma/zynq_dma_mailbox.v", "dma/zynq_dma_pair.v",
            "gtx/te0715_gtx_channel.v", "gtx/gtx_probe_control.v",
            *[f"ethernet/{name}.v" for name in
              ("frame_store", "clock_pair", "gtx_clocks", "dma_endpoint", "cdc_slot", "dma_packets")],
            "application/domain_link_packets.v", "application/te0715_domain_link_top.v"]
LOG_LIMIT = 32 * 1024 * 1024


def save(path: Path, value: Any) -> None:
    """Write one small evidence record; callers exclusively own their phase files."""
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def file_input(row: dict[str, str], inputs: dict[str, str]) -> Path:
    """Require an explicitly frozen file, including external executables."""
    path = Path(row["path"]).resolve(strict=True)
    if not path.is_file() or digest(path) != row["sha256"]:
        raise ValueError(f"changed input: {path}")
    previous = inputs.setdefault(str(path), row["sha256"])
    if previous != row["sha256"]:
        raise ValueError(f"conflicting input identity: {path}")
    return path


def bundle(row: dict[str, Any], inputs: dict[str, str]) -> tuple[Path, list[Path]]:
    """Validate an ordinary compiled release and select only its explicit RTL units."""
    root = Path(row["root"]).resolve(strict=True)
    manifest = file_input({"path": str(root / "source-build.json"),
                           "sha256": row["source_build_sha256"]}, inputs)
    compiled = file_input({"path": str(root / "compiled.json"),
                           "sha256": row["compiled_sha256"]}, inputs)
    source, release = json.loads(manifest.read_text()), json.loads(compiled.read_text())
    if release["source_build_sha256"] != row["source_build_sha256"]:
        raise ValueError("compiled release belongs to another source build")
    for member in source["inputs"] + [m for rows in release["rtl"].values() for m in rows]:
        path = (root / member["file"]).resolve(strict=True)
        if not path.is_relative_to(root):
            raise ValueError("compiled member escapes its release")
        file_input({"path": str(path), "sha256": member["sha256"]}, inputs)
    selected = set(row["modules"])
    units = [u for u in source["units"] if u["module"] in selected]
    if len(units) != len(selected) or len(selected) != len(row["modules"]):
        raise ValueError("missing/duplicate selected compiled unit")
    for unit in units:
        receipts = [r for r in release["units"]
                    if (r["role"], r["directory"]) == (unit["role"], unit["directory"])]
        if len(receipts) != 1 or any(c["exit"] != 0 for c in receipts[0]["commands"]):
            raise ValueError("selected unit has no unique successful compiler receipt")
        generated = [c for c in receipts[0]["commands"] if c["stage"] == "codegen"]
        if len(generated) != 1 or generated[0]["output"] != unit["output"]:
            raise ValueError("selected unit has no unique matching codegen output")
        generated_path = (root / generated[0]["output"]).resolve(strict=True)
        if inputs.get(str(generated_path)) != generated[0]["sha256"]:
            raise ValueError("selected codegen output is not the checked RTL")
    paths = [(root / name).resolve(strict=True)
             for name in [*(name for u in units for name in u["rtl"]), *row.get("extra_rtl", [])]]
    if any(not path.is_relative_to(root) or str(path) not in inputs for path in paths):
        raise ValueError("selected RTL is not a checked bundle member")
    return root, paths


def readmem_inputs(sources: list[Path], cwd: Path, inputs: dict[str, str]) -> None:
    """Require every explicit RTL readmem call to name a checked local file literally."""
    for source in sources:
        text = re.sub(r"/\*.*?\*/|//[^\n]*", "", source.read_text(), flags=re.S)
        calls = re.findall(r"\$readmem[hb]\s*\(\s*([^,]+),", text)
        if len(calls) != len(re.findall(r"\$readmem[hb]\b", text)):
            raise ValueError(f"unparsed readmem call: {source}")
        for argument in calls:
            literal = re.fullmatch(r'"([A-Za-z0-9_.-]+)"', argument.strip())
            if literal is None:
                raise ValueError(f"dynamic or escaping readmem filename: {source}")
            path = (cwd / literal[1]).resolve(strict=True)
            if path.parent != cwd or str(path) not in inputs:
                raise ValueError(f"readmem file is not a checked input: {path}")


def prepare(manifest: Path, output: Path) -> None:
    """Freeze exact sources, roles, tools, database and offline donor evidence."""
    config = json.loads(manifest.read_text())
    if config["schema"] != "hls_domain_board_image_v1" or config["role"] not in (1, 2):
        raise ValueError("invalid domain-board image declaration")
    output.mkdir(parents=True, exist_ok=False)
    inputs = {str(manifest.resolve()): digest(manifest)}
    roots, sources = [], []
    for row in config["bundles"]:
        root, rtl = bundle(row, inputs)
        roots.append(root)
        sources.extend(rtl)
    for row in config.get("extra_inputs", []):
        file_input(row, inputs)
    board = roots[config["board_bundle"]] / "board_control/interface.json"
    if str(board) not in inputs:
        raise ValueError("board metadata is not a hashed source-build input")
    metadata = json.loads(board.read_text())
    if (metadata["kind"], metadata["role"], metadata["domain_index"], metadata["wire_version"],
            metadata["top_module"], metadata["state_bit_budget"]) != (
            "domain_board_control", config["role"], config["domain_index"], 1, "domain_board", 768):
        raise ValueError("physical role or generated board interface mismatch")
    mac = Path(config["mac_directory"]).resolve(strict=True)
    mac_files = [file_input(row, inputs) for row in config["mac_inputs"]]
    if any(path.parent != mac for path in mac_files):
        raise ValueError("MAC readmem/source inputs must share the explicit working directory")
    for name in ("liteeth_packet_core.v", "liteeth_pcs_gearbox.v"):
        path = mac / name
        if path not in mac_files:
            raise ValueError(f"missing generated MAC source: {name}")
        sources.append(path)
    if not any(path.suffix == ".init" for path in mac_files):
        raise ValueError("missing generated MAC readmem initialization")
    for name in PHYSICAL:
        sources.append(file_input({"path": str(ROOT / name),
            "sha256": config["platform_inputs"][name]}, inputs))
    readmem_inputs(sources, mac, inputs)
    constraints = file_input({"path": str(ROOT / "ethernet/te0715_ethernet.xdc"),
        "sha256": config["platform_inputs"]["ethernet/te0715_ethernet.xdc"]}, inputs)
    tool_paths = {name: str(file_input(config[name], inputs))
                  for name in ("yosys", "nextpnr", "chipdb", "reference", "backend_result")}
    backend = json.loads(Path(tool_paths["backend_result"]).read_text())
    if not backend["success"] or backend["binary_sha256"] != config["nextpnr"]["sha256"]:
        raise ValueError("nextpnr is not the successful corrected offline build")
    backend_root = Path(tool_paths["backend_result"]).parent
    recipe_path = file_input({"path": str(backend_root / "recipe.json"),
                              "sha256": backend["recipe_sha256"]}, inputs)
    file_input({"path": str(backend_root / "build-script.py"),
                "sha256": backend["script_sha256"]}, inputs)
    recipe = json.loads(recipe_path.read_text())
    if recipe["schema"] != "hls-native-gtx-offline-build-v1" or not any(
            p["name"] == "nextpnr-ramb36-sdp72.patch" and
            p["sha256"] == "b7cb3f7d8226fa66b2aabcd6f733724234e6955443750acffe75db2e4456ec15"
            for p in recipe["patches"]):
        raise ValueError("corrected SDP72 native recipe is missing")
    database = Path(config["database"]["root"]).resolve(strict=True)
    files = {str(path.relative_to(database)): path for path in database.rglob("*") if path.is_file()}
    for name in ("xc7z030/tilegrid.json", "xc7z030sbg485-1/part.yaml"):
        files[name] = database / name
    if files.keys() != config["database"]["files"].keys():
        raise ValueError("database file closure differs from its frozen inventory")
    for name, path in files.items():
        file_input({"path": str(path), "sha256": config["database"]["files"][name]}, inputs)
    donor_root = (database / "segbits_clk_hrow_bot_r.db").resolve().parent.parent
    for name, sha in CLOCK_DONORS.items():
        file_input({"path": str(donor_root / name), "sha256": sha}, inputs)
    cache = Path(config["donor_cache"]).resolve(strict=True)
    pins = json.loads((ROOT / "gtx/configuration.lock.json").read_text())
    if {p.name for p in cache.iterdir() if p.is_file()} != {p["sha256"] for p in pins.values()}:
        raise ValueError("offline GTX donor cache must contain exactly the pinned files")
    for pin in pins.values():
        file_input({"path": str(cache / pin["sha256"]), "sha256": pin["sha256"]}, inputs)
    tools = Path(config["assembly_tools"]["root"]).resolve(strict=True)
    for name in ("bitread", "fasm2frames", "xc7frames2bit"):
        file_input({"path": str(tools / name), "sha256": config["assembly_tools"][name]}, inputs)
    helpers = [Path(__file__).resolve(), ROOT / "xc7_resources.py", ROOT / "map_xc7_resources.py",
               ROOT / "application/link_board.py", ROOT / "application/domain_board_clocks.py",
               ROOT / "lut_legality/check.py",
               ROOT / "check_zynq7030_bitstream.py", ROOT / "prepare_zynq7030.py",
               ROOT / "boot/reference-images.json", ROOT / "gtx/LICENSE.prjxray",
               *ROOT.joinpath("gtx").glob("*.py"), *ROOT.joinpath("gtx").glob("*.json"),
               *ROOT.joinpath("ethernet").glob("*.py"), *ROOT.joinpath("ethernet").glob("*.json"),
               *ROOT.joinpath("vivado").glob("*.py")]
    for path in helpers:
        inputs[str(path.resolve())] = digest(path)
    frozen = {"schema": config["schema"], "role": config["role"], "domain_index": config["domain_index"],
              "sources": list(dict.fromkeys(str(path) for path in sources)), "cwd": str(mac),
              "constraints": str(constraints), "inputs": inputs, **tool_paths,
              "database": str(database), "donor_cache": str(cache), "assembly_tools": str(tools),
              "bounds": BOUNDS, "link_bounds": LINK_BOUNDS, "groups": GROUPS,
              "seed": 1, "router": "router2", "timing_qualified": False, "hardware_qualified": False,
              "limits": "Partial native timing model: no BRAM sequential, generated-clock relationship or full CDC settling signoff."}
    save(output / "inputs.json", frozen)


def unchanged(frozen: dict[str, Any]) -> None:
    """Every physical phase consumes the exact same frozen bytes."""
    for name, expected in frozen["inputs"].items():
        if digest(Path(name)) != expected:
            raise ValueError(f"frozen input changed: {name}")


def command(argv: list[str], cwd: Path, directory: Path, seconds: int) -> dict[str, Any]:
    """Run one bounded process group and cap all tool logs; never retry its command."""
    started = time.monotonic()
    guard = None
    primary_error = None
    cleanup_error = None
    group_snapshot = None
    gone = None
    with (directory / "console.log").open("w") as log:
        process = subprocess.Popen(argv, cwd=cwd, stdout=log, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        try:
            while process.poll() is None:
                logs = [p.stat().st_size for p in directory.rglob("*.log") if p.is_file()]
                if any(size > LOG_LIMIT for size in logs) or sum(logs) > 4 * LOG_LIMIT:
                    guard = "log_size"
                    break
                if time.monotonic() - started > seconds:
                    guard = "time"
                    break
                time.sleep(0.2)
        except BaseException as error:
            primary_error = error
        finally:
            try:
                gone = stop_group(process)
            except Exception as error:
                cleanup_error = f"{type(error).__name__}: {error}"
                try:
                    process.wait(timeout=5)
                    if isinstance(error, PermissionError):
                        group_snapshot = snapshot_group(process.pid, directory)
                        gone = group_snapshot["owned_group_gone"]
                except Exception as reap_error:
                    cleanup_error += f"; reap: {type(reap_error).__name__}: {reap_error}"
    record = {"command": argv, "pid": process.pid, "group": process.pid,
              "returncode": process.returncode, "guard": guard, "owned_group_gone": gone,
              "primary_error": None if primary_error is None else f"{type(primary_error).__name__}: {primary_error}",
              "cleanup_error": cleanup_error, "group_snapshot": group_snapshot,
              "elapsed_seconds": time.monotonic() - started}
    save(directory / "execution.json", record)
    if primary_error is not None:
        raise primary_error
    if guard or process.returncode or not gone:
        raise ValueError(f"external phase failed; preserved {directory}")
    return record


def snapshot_group(group: int, directory: Path) -> dict[str, Any]:
    """Resolve a denied group probe only from a complete bounded process-table snapshot."""
    path = directory / "group-status.txt"
    result: dict[str, Any] = {"method": "ps pid,pgid after leader reaped",
                              "owned_group_gone": None}
    try:
        with path.open("w") as stream:
            observed = subprocess.run(["/bin/ps", "-axo", "pid=,pgid="], stdout=stream,
                                      stderr=subprocess.PIPE, timeout=5, check=False)
        result["returncode"] = observed.returncode
        if observed.returncode != 0 or path.stat().st_size > 1024 * 1024:
            raise ValueError("process snapshot failed or exceeded its read limit")
        rows = [line.split() for line in path.read_text().splitlines() if line.strip()]
        if not rows or any(len(row) != 2 or not all(value.isdecimal() for value in row) for row in rows):
            raise ValueError("incomplete process snapshot")
        result["members"] = [int(pid) for pid, pgid in rows if int(pgid) == group]
        result["owned_group_gone"] = not result["members"]
        result["sha256"] = digest(path)
    except Exception as error:
        result["error"] = f"{type(error).__name__}: {error}"
    return result


def map_image(frozen: dict[str, Any], directory: Path) -> dict[str, Any]:
    """Map the full physical image once and enforce whole plus connected-link gates."""
    netlist = directory / "netlist.json"
    script = directory / "map.ys"
    script.write_text("\n".join([
        "read_verilog -sv " + " ".join(quoted(Path(p)) for p in frozen["sources"]),
        f"chparam -set ROLE {frozen['role']} {TOP}",
        f"synth_xilinx -flatten -abc9 -family xc7 -top {TOP}",
        "write_json " + quoted(directory / "raw-mapped.json"),
        "tee -q bufnorm -conn", "check -assert", "scc -expect 0",
        "write_json " + quoted(netlist), "tee -o " + quoted(directory / "stat.json") + " stat -json", ""]))
    command([frozen["yosys"], "-Q", "-T", "-l", str(directory / "yosys.log"), "-s", str(script)],
            Path(frozen["cwd"]), directory, 3600)
    area = report(json.loads(netlist.read_text()), TOP, GROUPS, BOUNDS)
    save(directory / "resources.json", area)
    physical = inspect(netlist, str(frozen["role"]), False, False, False, top=TOP)
    physical.pop("debug_observation")
    save(directory / "physical.json", physical)
    populations = Counter()
    missing = [name for name in ("domain", "endpoints", "packet_router", "endpoint_management",
                               "board_control", "carrier")
               if not area["mapped"]["groups"][name]["primitive_counts"]]
    for name in ("endpoints", "packet_router", "endpoint_management", "carrier", "unattributed"):
        populations.update(area["mapped"]["groups"][name]["primitive_counts"])
    link = counts(populations)
    resource = link["resources"]
    passed = not missing and link["complete"] and all(
        resource[key] <= maximum for key, maximum in LINK_BOUNDS.items())
    screen = {"mapped": link, "bounds": LINK_BOUNDS, "passes": passed,
              "included_groups": ["endpoints", "packet_router", "endpoint_management", "carrier", "unattributed"],
              "attribution": "Conservative connected instance-name association, including inherited carrier CDC and ALL unattributed cells. Shared/merged logic is not treated as free; this is not isolated causal cost.",
              "missing_groups": missing,
              "unattributed": area["mapped"]["groups"]["unattributed"]}
    save(directory / "link-screen.json", screen)
    admitted = area["mapped"]["complete"] and area["bounds"]["passes"] and passed
    return {"netlist_sha256": digest(netlist), "resources_sha256": digest(directory / "resources.json"),
            "link_screen_sha256": digest(directory / "link-screen.json"), "physical": physical,
            "whole_image_passes": area["mapped"]["complete"] and area["bounds"]["passes"],
            "component_screen_passes": passed, "route_admitted": admitted}


def route_image(frozen: dict[str, Any], directory: Path) -> dict[str, Any]:
    """Require packed clock coverage before one route, retaining actual routed coverage separately."""
    mapped = directory.parent / "map"
    result = json.loads((mapped / "result.json").read_text())
    if result["input_manifest_sha256"] != digest(directory.parent / "inputs.json"):
        raise ValueError("mapping belongs to another frozen input manifest")
    if not result["success"] or not result["route_admitted"]:
        raise ValueError("area/component screen blocks routing; no implicit budget exception")
    netlist = mapped / "netlist.json"
    for path, key in ((netlist, "netlist_sha256"), (mapped / "resources.json", "resources_sha256"),
                      (mapped / "link-screen.json", "link_screen_sha256")):
        if digest(path) != result[key]:
            raise ValueError("mapped gate evidence changed")
    constraints = directory / "constraints.xdc"
    mapped_clocks = domain_board_clocks.project(json.loads(netlist.read_text())["modules"][TOP])
    constraints.write_text(domain_board_clocks.render(mapped_clocks, Path(frozen["constraints"]).read_text()))
    common = [frozen["nextpnr"], "--chipdb", frozen["chipdb"], "--json", str(netlist),
              "--xdc", str(constraints)]
    packed = directory / "packed.json"
    pack = directory / "pack"
    pack.mkdir()
    command([*common, "--pack-only", "--write", str(packed),
             "--report", str(pack / "timing.json"), "--log", str(pack / "nextpnr.log")],
            Path(frozen["cwd"]), pack, 600)
    packed_clocks = domain_board_clocks.validate_pack(
        domain_board_clocks.project(json.loads(packed.read_text())["modules"][TOP]),
        (pack / "nextpnr.log").read_text(), json.loads((pack / "timing.json").read_text()))
    save(pack / "clock-coverage.json", packed_clocks)
    run = directory / "implementation"
    run.mkdir()
    fasm, routed, timing = (directory / name for name in ("image.fasm", "routed.json", "timing.json"))
    command([*common, "--fasm", str(fasm), "--report", str(timing), "--write", str(routed),
             "--log", str(run / "nextpnr.log"), "--freq", "125", "--seed", "1",
             "--router", "router2", "--timing-allow-fail"], Path(frozen["cwd"]), run, 3600)
    log = (run / "nextpnr.log").read_text()
    if "failed to find a route using dedicated resources" in log:
        raise ValueError("clock routing fell back to fabric")
    if re.search(r"(?m)^\s*(?:ERROR|FATAL):", log):
        raise ValueError("native route reported a fatal error")
    partial = json.loads(timing.read_text())
    routed_clocks = domain_board_clocks.validate_routed(
        domain_board_clocks.project(json.loads(routed.read_text())["modules"][TOP]), log, partial)
    coverage = {"constraints_sha256": digest(constraints), "packed": packed_clocks, "routed": routed_clocks}
    save(directory / "clock-coverage.json", coverage)
    lut_check = check_luts(packed, routed, fasm, Path(frozen["database"]) / "xc7z030/tilegrid.json")
    save(directory / "lut-check.json", lut_check)
    return {"fasm_sha256": digest(fasm), "packed_sha256": digest(packed), "routed_sha256": digest(routed),
            "timing_sha256": digest(timing), "lut_check": lut_check,
            "constraints_sha256": digest(constraints),
            "clock_coverage_sha256": digest(directory / "clock-coverage.json"),
            "modeled_targets_met": routed_clocks["modeled_targets_met"],
            "partial_timing": partial, "database_audit": audit_database(Path(frozen["database"]), fasm)}


def assemble_image(frozen: dict[str, Any], directory: Path) -> dict[str, Any]:
    """Require retained complete clock coverage and modeled timing before offline assembly."""
    routed = directory.parent / "route"
    result = json.loads((routed / "result.json").read_text())
    if result["input_manifest_sha256"] != digest(directory.parent / "inputs.json"):
        raise ValueError("route belongs to another frozen input manifest")
    fasm = routed / "image.fasm"
    if not result["success"] or digest(fasm) != result["fasm_sha256"] or not result["modeled_targets_met"]:
        raise ValueError("changed route or failed modeled timing blocks assembly")
    coverage_path = routed / "clock-coverage.json"
    if (digest(coverage_path) != result["clock_coverage_sha256"] or
            digest(routed / "constraints.xdc") != result["constraints_sha256"] or
            digest(routed / "timing.json") != result["timing_sha256"]):
        raise ValueError("changed clock evidence blocks assembly")
    coverage = json.loads(coverage_path.read_text())
    if (coverage["constraints_sha256"] != result["constraints_sha256"] or
            coverage["packed"]["clock_coverage_complete"] is not True or
            coverage["routed"]["clock_coverage_complete"] is not True or
            coverage["routed"]["modeled_targets_met"] is not True):
        raise ValueError("incomplete clock coverage blocks assembly")
    command([sys.executable, str(Path(__file__).resolve()), "assembly-worker", str(directory.parent)],
            Path(frozen["cwd"]), directory, 1200)
    return json.loads((directory / "image/result.json").read_text())


def assembly_worker(output: Path) -> None:
    """Run inherited assembly inside the parent's bounded, wholly retired process group."""
    frozen = json.loads((output / "inputs.json").read_text())
    assemble(Path(frozen["database"]), output / "route/image.fasm", Path(frozen["reference"]),
             "ethernet-external", Path(frozen["assembly_tools"]), output / "assemble/image",
             Path(frozen["donor_cache"]), offline=True)


def phase(output: Path, name: str) -> None:
    """Run a fresh phase once; retained failure directories forbid accidental restart."""
    frozen = json.loads((output / "inputs.json").read_text())
    unchanged(frozen)
    directory = output / name
    directory.mkdir(exist_ok=False)
    result = {"success": False, "timing_qualified": False, "hardware_qualified": False,
              "input_manifest_sha256": digest(output / "inputs.json"), "limits": frozen["limits"]}
    save(directory / "started.json", result)
    started = time.monotonic()
    try:
        operation = {"map": map_image, "route": route_image, "assemble": assemble_image}[name]
        result.update(operation(frozen, directory))
        unchanged(frozen)
        result["success"] = True
    except BaseException as error:
        result["error"] = f"{type(error).__name__}: {error}"
        raise
    finally:
        result["elapsed_seconds"] = time.monotonic() - started
        changed = []
        for path, expected in frozen["inputs"].items():
            try:
                actual = digest(Path(path))
            except OSError:
                actual = None
            if actual != expected:
                changed.append(path)
        result["changed_inputs"] = changed
        if changed:
            result["success"] = False
        save(directory / "result.json", result)
    if not result["success"]:
        raise ValueError("phase input verification failed")


def main() -> None:
    """Select one explicitly authorized serial phase; output directories are never replaced."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=("prepare", "map", "route", "assemble", "assembly-worker"))
    parser.add_argument("output", type=Path)
    parser.add_argument("--manifest", type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    if args.phase == "assembly-worker":
        assembly_worker(output)
    elif args.phase == "prepare":
        if args.manifest is None:
            parser.error("prepare requires --manifest")
        prepare(args.manifest.resolve(strict=True), output)
    else:
        if args.manifest is not None:
            parser.error("later phases use the frozen inputs.json")
        phase(output, args.phase)
    print(json.dumps({"phase": args.phase, "output": str(output), "completed": True}))


if __name__ == "__main__":
    main()
