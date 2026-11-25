"""Stage the archived four-Phi 50 MHz reference, replay its RTL and capture a matched XC7 checkpoint."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile

from replay import require

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
PREFIX = Path("erl-hls-vivado-20260921/bundle")
INPUT = PREFIX / "inputs/phi"
VENDOR = PREFIX / "results/phi-20.0ns"
ARCHIVE = "e465bba8b1effdf82450ec5147ccfeab43de85c6af7d5c83ef5f318c4a5f6bc3"
RTL = [
    "hls_1r1w_ram.v",
    "phi_decoder_profile.v",
    "phi_decoder_profile_top.v",
    "phi_timing_harness.v",
]
REPORTS = [
    "routed.dcp",
    "routed.v",
    "hard-primitives.rpt",
    "setup-paths.rpt",
    "effective.xdc",
]
XDC = ROOT / "platforms/xc7/xc7z030sbg485.xdc"
BRAM_MAP = Path("share/yosys/xilinx/brams_xc6v_map.v")
sys.path.insert(0, str(ROOT / "platforms/xc7/bram"))
from check_yosys import audit_library

SHARED_FILES = [
    *(INPUT / n for n in RTL),
    *(VENDOR / n for n in REPORTS),
    *(
        Path("native") / n
        for n in (
            "map.ys",
            "lower.ys",
            "synth.json",
            "lowered.json",
        )
    ),
    Path("replay.vvp"),
    Path("trace.txt"),
]


def native_files(mode: str) -> list[Path]:
    """Select the checkpoint and evidence that the requested implementation stage actually emits."""
    require(mode in ("placed", "routed"), "unsupported native checkpoint stage")
    names = (
        ["placed.json", "placement.log"]
        if mode == "placed"
        else ["routed.json", "routing.log", "report.json"]
    )
    return [Path("native") / n for n in names]


def capture_files(mode: str, core_harness: bool, geometry: bool = False) -> list[Path]:
    """Identify all replay, mapping and implementation files required by the selected capture."""
    files = SHARED_FILES + native_files(mode)
    if core_harness:
        require(mode == "routed", "core/harness capture requires a routed checkpoint")
        files.remove(Path("native/map.ys"))
        files.extend(
            Path("native") / n
            for n in (
                "map-core.ys",
                "map-core.log",
                "core-interface.ys",
                "map-harness.ys",
                "mapping.json",
            )
        )
    if geometry:
        require(mode == "routed", "switches and post-route SDF require a route")
        files.extend(Path("native") / n for n in ("fixed-routes.txt", "routed.sdf"))
    return files


def digest(path: Path) -> str:
    """Hash exact file bytes without allocating a checkpoint-sized buffer."""
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def stage(archive: Path, run: Path) -> None:
    """Extract only named regular members from the authenticated reference archive into a fresh run."""
    require(digest(archive) == ARCHIVE, "four-Phi archive mismatch")
    run.mkdir()
    wanted = {INPUT / n for n in RTL} | {VENDOR / n for n in REPORTS}
    with tarfile.open(archive, "r|gz") as source:
        for member in source:
            name = Path(member.name)
            if name in wanted:
                require(
                    member.isfile() and member.size <= 64 << 20,
                    "vendor member type or limit",
                )
                dest = run / name
                dest.parent.mkdir(parents=True, exist_ok=True)
                with dest.open("xb") as target:
                    shutil.copyfileobj(source.extractfile(member), target)
                wanted.remove(name)
    require(not wanted, "missing vendor inputs")
    (run / "native").mkdir()


def simulate(run: Path) -> None:
    """Run four-state RTL with the passive 4,096-edge monitor, keeping compiler and replay outputs."""
    program = run / "replay.vvp"
    subprocess.run(
        [
            "iverilog",
            "-g2012",
            "-s",
            "transaction_tb",
            "-o",
            program,
            *(run / INPUT / n for n in RTL),
            HERE / "transaction_tb.sv",
        ],
        check=True,
    )
    with (run / "trace.txt").open("x") as stream:
        subprocess.run(["vvp", program], stdout=stream, check=True, timeout=600)


def implement(
    run: Path,
    yosys: Path,
    router: Path,
    chipdb: Path,
    mode: str,
    core_harness: bool = False,
) -> None:
    """Preserve origin IDs from the same frontend and implement the unchanged two-pin harness."""
    native = run / "native"
    # Match the core frontend's read order so the lowered multiply has the same Yosys origin ID.
    order = (
        [
            "phi_decoder_profile.v",
            "phi_decoder_profile_top.v",
            "hls_1r1w_ram.v",
            "phi_timing_harness.v",
        ]
        if core_harness
        else RTL
    )
    read = "read_verilog -sv " + " ".join(f'"{run / INPUT / n}"' for n in order)
    common = read + "\nhierarchy -check -top phi_timing_harness\n"
    recipes = {
        "lower": "proc\nflatten\nwrite_json lowered.json",
        "map": "synth_xilinx -flatten -abc9 -family xc7 -top phi_timing_harness\n"
        "check -assert\nscc -expect 0\nwrite_json synth.json",
    }
    if core_harness:
        sys.path.insert(0, str(ROOT / "platforms/xc7"))
        import phi_timing

        require(
            digest(run / INPUT / "phi_timing_harness.v")
            == digest(phi_timing.HERE / "phi_timing_harness.v"),
            "harness RTL identity",
        )
        phi_timing.map_design(
            argparse.Namespace(stage=native, rtl=run / INPUT), {"yosys": yosys}
        )
        os.link(native / "mapped.json", native / "synth.json")
        del recipes["map"]
    for name, recipe in recipes.items():
        (native / f"{name}.ys").write_text(common + recipe + "\n")
        with (native / f"{name}.log").open("x") as stream:
            subprocess.run(
                [yosys, "-Q", "-s", f"{name}.ys"],
                cwd=native,
                stdout=stream,
                check=True,
                timeout=1200,
            )
    check_mapping_log(
        native / ("map-core.log" if core_harness else "map.log"),
        yosys.parent.parent / BRAM_MAP,
    )
    place_or_route(native, router, chipdb, mode)


def check_mapping_log(log: Path, library: Path) -> None:
    """Require synthesis to have read the same BRAM map that the capture identifies."""
    opened = {
        Path(path).resolve()
        for path in re.findall(
            r"Executing Verilog-2005 frontend: (.*brams_xc6v_map\.v)$",
            log.read_text(),
            re.M,
        )
    }
    require(
        opened == {library.resolve()}, "effective Yosys BRAM map differs from capture"
    )


def place_or_route(native: Path, router: Path, chipdb: Path, mode: str) -> None:
    """Write a placed or routed checkpoint under the same seed, placer, pin and clock constraints."""
    checkpoint, log, *reports = native_files(mode)
    stage_args = ["--report", reports[0].name] if reports else ["--no-route"]
    if mode == "routed":
        stage_args.extend(
            ["--sdf", "routed.sdf", "--write-fixed-routes", "fixed-routes.txt"]
        )
    subprocess.run(
        [
            router,
            "--chipdb",
            chipdb,
            "--json",
            "synth.json",
            "--xdc",
            XDC,
            "--freq",
            "50",
            "--seed",
            "1",
            "--placer",
            "heap",
            "--router",
            "router2",
            "--timing-allow-fail",
            *stage_args,
            "--write",
            checkpoint.name,
            "--log",
            log.name,
        ],
        cwd=native,
        check=True,
        timeout=3600,
    )


def identities(
    run: Path,
    yosys: Path,
    router: Path,
    chipdb: Path,
    mode: str,
    core_harness: bool = False,
    *,
    seed: int = 1,
) -> dict:
    """Record the requested seed and content identities for replay, native implementation and vendor reports."""
    build = json.loads(router.with_name("spacetime-build.json").read_text())["sha256"]
    require(digest(router) == build["nextpnr-spacetime"], "nextpnr build mismatch")
    lut_patch = "nextpnr-xc7-lut-route-delay.patch"
    for model in (
        lut_patch,
        "nextpnr-spacetime-fixed-srl.patch",
        "nextpnr-spacetime-wire-delays.patch",
        "fixed_srl.inc",
        "nextpnr-spacetime-registered-dsp.patch",
        "registered_dsp.inc",
    ):
        if model in build:
            require(build[model] == digest(ROOT / "platforms/xc7/timing_coverage" / model), model)
    tools = {
        "yosys": yosys,
        "yosys-executable": yosys.parent.parent / "libexec/yosys",
        "xc7-bram-map": yosys.parent.parent / BRAM_MAP,
        "abc": yosys.parent.parent / "libexec/yosys-abc",
        "nextpnr": router,
        "chipdb": chipdb,
        "iverilog": Path(shutil.which("iverilog")),
        "vvp": Path(shutil.which("vvp")),
    }
    return {
        "archive": ARCHIVE,
        "part": "xc7z030sbg485-1",
        "periodNs": 20,
        "seed": seed,
        "nativeStage": mode,
        **({"routedLutTiming": True} if mode == "routed" and lut_patch in build else {}),
        "pins": {"clock": "Y14", "activity": "V13"},
        "constraints": digest(XDC),
        "testbench": digest(HERE / "transaction_tb.sv"),
        "tools": {n: digest(p) for n, p in tools.items()},
        **({"coreHarness": True} if core_harness else {}),
        **({"routedGeometry": True} if mode == "routed" else {}),
        "files": {
            str(p): digest(run / p)
            for p in capture_files(mode, core_harness, mode == "routed")
        },
    }


def main() -> None:
    """Run the matched witness in a fresh directory under the caller's serial resource guard."""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("archive", "yosys", "router", "chipdb", "output"):
        parser.add_argument(name, type=Path)
    parser.add_argument(
        "--native-stage", choices=["placed", "routed"], default="placed"
    )
    parser.add_argument(
        "--core-harness",
        action="store_true",
        help="map the core separately and save routed geometry and SDF",
    )
    args = parser.parse_args()
    if args.core_harness and args.native_stage != "routed":
        parser.error("--core-harness requires --native-stage routed")
    run = args.output.resolve()
    tools = [args.yosys.resolve(), args.router.resolve(), args.chipdb.resolve()]
    audit_library((tools[0].parent.parent / BRAM_MAP).read_text())
    stage(args.archive, run)
    inputs = {p: digest(run / p) for p in SHARED_FILES if p.is_relative_to(PREFIX)}
    simulate(run)
    implement(run, *tools, args.native_stage, args.core_harness)
    require(
        all(digest(run / p) == sha for p, sha in inputs.items()),
        "implementation inputs changed",
    )
    (run / "capture.json").write_text(
        json.dumps(
            identities(run, *tools, args.native_stage, args.core_harness), indent=2
        )
        + "\n"
    )


if __name__ == "__main__":
    main()
