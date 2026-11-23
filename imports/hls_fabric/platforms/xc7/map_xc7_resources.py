#!/usr/bin/env python3
"""Map explicitly supplied RTL tops serially and retain their XC7 area inventories.

This optional external-tool driver does not emit application sources, select a
backend, pack/place/route, or program hardware. Supply the complete RTL/input
closure and the directory used by relative readmem paths. Outputs are fresh.
"""

import argparse
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time
from typing import Any

from xc7_resources import digest, report


def identifier(value: str) -> str:
    """Accept an ordinary Verilog identifier usable in an external tool command."""
    if not re.fullmatch(r"[A-Za-z_$][A-Za-z0-9_$]*", value):
        raise ValueError(f"invalid top identifier: {value!r}")
    return value


def quoted(path: Path) -> str:
    """Quote a literal filename for Yosys scripts, rejecting control characters."""
    value = str(path.resolve())
    if any(ord(char) < 32 for char in value):
        raise ValueError("control character in tool path")
    return json.dumps(value)


def script(sources: list[Path], top: str, directory: Path,
           includes: list[Path], defines: list[str]) -> str:
    """Generate one full-top map/check/SCC pass with no inferred package IO or clocks."""
    top = identifier(top)
    for define in defines:
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*(?:=[0-9]+)?", define):
            raise ValueError(f"invalid preprocessor definition: {define!r}")
    options = [*("-I" + quoted(path) for path in includes),
               *("-D" + define for define in defines)]
    return "\n".join([
        "read_verilog -sv " + " ".join([*options, *(quoted(path) for path in sources)]),
        f"synth_xilinx -flatten -abc9 -family xc7 -noiopad -noclkbuf -top {top}",
        "check -assert", "scc -expect 0",
        "write_json " + quoted(directory / "netlist.json"),
        "tee -o " + quoted(directory / "stat.json") + " stat -json", "",
    ])



def group_exists(group: int) -> bool:
    """Check the process group created by this driver, never an unrelated tool group."""
    try:
        os.killpg(group, 0)
        return True
    except ProcessLookupError:
        return False


def stop_group(process: subprocess.Popen, grace: float = 1.0) -> bool:
    """Retire the owned group, escalating after a bounded grace and reaping its leader."""
    for action in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(process.pid, action)
        except ProcessLookupError:
            break
        deadline = time.monotonic() + grace
        while group_exists(process.pid) and time.monotonic() < deadline:
            process.poll()
            time.sleep(0.02)
    process.wait(timeout=5)
    return not group_exists(process.pid)


def run_tool(command: list[str], cwd: Path, console: Path,
             timeout: float) -> dict[str, Any]:
    """Run one tool in a new session; retain timeout/exit and retire all its descendants."""
    started = time.monotonic()
    timed_out = False
    with console.open("w") as log:
        process = subprocess.Popen(command, cwd=cwd, stdout=log, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        try:
            process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
        finally:
            gone = stop_group(process)
    return {"pid": process.pid, "process_group": process.pid,
            "returncode": process.returncode, "timed_out": timed_out,
            "owned_group_gone": gone, "elapsed_seconds": time.monotonic() - started}


def build(yosys: Path, sources: list[Path], tops: list[str], output: Path, cwd: Path,
          includes: list[Path], defines: list[str], extra_inputs: list[Path],
          limits: dict[str, int] | None, groups: dict[str, str] | None,
          timeout: int) -> dict[str, Any]:
    """Run each selected top once, retaining failed logs and all declared input hashes."""
    if not sources or not tops or len(set(tops)) != len(tops) or timeout <= 0:
        raise ValueError("need sources, distinct tops and a positive per-top timeout")
    for top in tops:
        identifier(top)
    helper = Path(__file__).resolve()
    paths = [yosys.resolve(), helper, helper.with_name("xc7_resources.py"),
             *(path.resolve() for path in sources + extra_inputs)]
    inputs = {str(path): digest(path) for path in paths}
    output.mkdir(parents=True, exist_ok=False)
    record: dict[str, Any] = {
        "schema": "hls_xc7_mapping_v1", "inputs": inputs,
        "sources": [str(path.resolve()) for path in sources],
        "extra_inputs": [str(path.resolve()) for path in extra_inputs],
        "cwd": str(cwd.resolve()), "include_directories": [str(path.resolve()) for path in includes],
        "defines": defines, "bounds": limits, "groups": groups,
        "tops": {}, "timing_qualified": False, "hardware_qualified": False,
        "limits": "Mapped area only; included files/readmem data must be declared as inputs.",
    }
    try:
        for top in tops:
            directory = output / top
            directory.mkdir()
            commands = directory / "map.ys"
            commands.write_text(script(sources, top, directory, includes, defines))
            execution = run_tool(
                [str(yosys.resolve()), "-Q", "-T", "-l", str((directory / "yosys.log").resolve()),
                 "-s", str(commands.resolve())], cwd, directory / "console.log", timeout)
            record["tops"][top] = {"execution": execution, "script_sha256": digest(commands)}
            if execution["timed_out"] or execution["returncode"] != 0 or not execution["owned_group_gone"]:
                raise ValueError(f"mapping failed for {top}: {execution}")
            netlist = directory / "netlist.json"
            result = report(json.loads(netlist.read_text()), top, groups, limits)
            result["mapping_seconds"] = execution["elapsed_seconds"]
            result["netlist_sha256"] = digest(netlist)
            (directory / "resources.json").write_text(json.dumps(result, indent=2) + "\n")
            record["tops"][top].update({"resources_sha256": digest(directory / "resources.json"),
                                         "netlist_sha256": digest(netlist),
                                         "mapping_seconds": result["mapping_seconds"]})
            if not result["mapped"]["complete"]:
                raise ValueError(f"unclassified mapped primitives in {top}; see resources.json")
            if result["bounds"] is not None and not result["bounds"]["passes"]:
                raise ValueError(f"mapped resource ceiling exceeded by {top}; see resources.json")
        record["status"] = "passed"
    except BaseException as error:
        record["status"] = "failed"
        record["error"] = f"{type(error).__name__}: {error}"
        raise
    finally:
        observed, failures = {}, {}
        for name in inputs:
            try:
                observed[name] = digest(Path(name))
            except OSError as error:
                observed[name] = None
                failures[name] = str(error)
        record["post_inputs"] = observed
        record["post_input_errors"] = failures
        record["changed_inputs"] = [name for name in inputs if observed[name] != inputs[name]]
        if record["changed_inputs"]:
            record["status"] = "failed"
        (output / "manifest.json").write_text(json.dumps(record, indent=2) + "\n")
    if record["changed_inputs"]:
        raise ValueError(f"inputs changed during mapping: {record['changed_inputs']}")
    return record


def main() -> None:
    """Select explicit RTL, input closure, tops and optional preregistered area ceilings."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--yosys", type=Path, required=True)
    parser.add_argument("--source", type=Path, action="append", required=True)
    parser.add_argument("--top", action="append", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cwd", type=Path, default=Path.cwd())
    parser.add_argument("--include", type=Path, action="append", default=[])
    parser.add_argument("--define", action="append", default=[])
    parser.add_argument("--input", type=Path, action="append", default=[],
                        help="Additional input, including RTL includes and readmem data")
    parser.add_argument("--bounds", type=Path)
    parser.add_argument("--groups", type=Path)
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()
    limits = json.loads(args.bounds.read_text()) if args.bounds else None
    groups = json.loads(args.groups.read_text()) if args.groups else None
    metadata = [path for path in (args.bounds, args.groups) if path is not None]
    build(args.yosys, args.source, args.top, args.output.resolve(), args.cwd.resolve(),
          args.include, args.define, [*args.input, *metadata], limits, groups, args.timeout)


if __name__ == "__main__":
    main()
