#!/usr/bin/env python3
"""Compare configurable decoder profiles with BEAM and stalled RTL execution."""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
CASES = {
    "d3": (3, 3, "xz", 3),
    "board-sized": (2, 1, "xz", 1),
    "small-both": (2, 2, "xz", 2),
    "small-x": (2, 2, "x", 2),
    "rectangle-z": (2, 3, "z", 2),
}


def command(argv, cwd, log, timeout=1200):
    with log.open("w") as output:
        with subprocess.Popen(list(map(str, argv)), cwd=cwd, stdout=output,
                              stderr=subprocess.STDOUT) as process:
            try:
                code = process.wait(timeout=timeout)
            except BaseException:
                # Let the XLS driver's signal handler clean up its compiler
                # process group before resorting to an unconditional kill.
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
                raise
            if code:
                raise RuntimeError(f"command exited {code}; see {log}")


def sequences(rows):
    result = defaultdict(list)
    for plane, x, y, step, kind, value in rows:
        result[plane, x, y].append((step, kind, value))
    return dict(result)


def rtl_events(path):
    result = []
    tags = {0x0300000b: "phi_correction", 0x03000011: "phi_status"}
    for line in path.read_text().splitlines():
        p, x, y, step, encoded = line.split()
        frame = int(encoded, 16)
        result.append([int(p), int(x), int(y), int(step), tags[frame >> 96], (frame >> 64) & 0xffffffff])
    return result


def exercise(name, config, args):
    width, height, planes, shards = config
    stage = args.stage / name
    stage.mkdir(parents=True, exist_ok=True)
    (stage / "validation.json").unlink(missing_ok=True)
    (stage / "config.term").write_text(
        f"#{{shape => [{width},{height}], planes => [{','.join(planes)}], shards => {shards}}}.\n")
    erl = ["erl", "-noshell", "-pa", ROOT / "_build/test/lib/erl_hls/ebin", ROOT / "_build/test/lib/erl_hls/test"]
    command([*erl, "-eval", "[Stage] = init:get_plain_arguments(), phi_decoder_profile_fixture:write(Stage), "
             "phi_decoder_profile_fixture:oracle(Stage), halt().", "-extra", stage], ROOT, stage / "prepare.log", 120)
    for directory in (ROOT / "priv/xls/lib", ROOT / "priv/xls/fabric"):
        for path in directory.glob("*.x"):
            shutil.copyfile(path, stage / path.name)
    for path in (ROOT / "src/examples/phi_decoder/phi_field.x", ROOT / "priv/rtl/hls_1r1w_ram.v",
                 ROOT / "tools/phi_scheduler_rams.sh"):
        shutil.copyfile(path, stage / path.name)
    command(["iverilog", "-g2012", "-tnull", "-i", stage / "phi_decoder_profile_top.v",
             stage / "hls_1r1w_ram.v"], stage, stage / "shell-check.log")
    command(["bash", ROOT / "tools/compile_phi_decoder_profile.sh", stage, args.xls_root,
             "20m", shards, 2, 1], ROOT, stage / "compile.log", 3700)
    compiled = (stage / "compiled").resolve()
    expected = sequences(json.loads((stage / "oracle.json").read_text()))
    samples = []
    for stalled in (0, 1):
        run = stage / f"stalled-{stalled}"
        run.mkdir(exist_ok=True)
        (run / "phi_decoder_profile.events").unlink(missing_ok=True)
        parameters = dict(WIDTH=width, HEIGHT=height, X_ENABLED=int("x" in planes),
                          Z_ENABLED=int("z" in planes), STALL_OUTPUTS=stalled)
        command(["iverilog", "-g2012", "-s", "phi_decoder_profile_tb", "-o", run / "sim.vvp",
                 *[f"-Pphi_decoder_profile_tb.{key}={value}" for key, value in parameters.items()],
                 ROOT / "test/rtl/phi_decoder_profile_tb.sv",
                 *[compiled / file for file in ("phi_decoder_profile.v", "phi_decoder_profile_top.v", "hls_1r1w_ram.v")]],
                run, run / "compile.log")
        command(["vvp", run / "sim.vvp"], run, run / "simulation.log")
        actual = sequences(rtl_events(run / "phi_decoder_profile.events"))
        if actual != expected:
            differing = [key for key in expected.keys() | actual.keys() if actual.get(key) != expected.get(key)]
            raise AssertionError(f"{name}/stalled-{stalled}: BEAM/RTL mismatch at {differing}")
        log = (run / "simulation.log").read_text()
        if "PASS: decoder-only" not in log:
            raise AssertionError(f"{name}: missing completion")
        samples.append({"stalled": bool(stalled), "events": sum(map(len, actual.values())),
                        "metrics": [line for line in log.splitlines() if line.startswith("PROFILE_")]})
    summary = {"configuration": json.loads((compiled / "phi_decoder_profile.json").read_text()), "samples": samples}
    if args.trace:
        for helper in ("compile_xls.py", "compile_phi_decoder_profile.py", "compile_phi_decoder_profile.sh"):
            shutil.copyfile(ROOT / "tools" / helper, stage / helper)
        for source in ("phi_decoder_profile_tb.sv", "phi_profile_trace.c"):
            shutil.copyfile(ROOT / "test/rtl" / source, stage / source)
        command(["env", "ERL_HLS_PHI_PROFILE_TRACE=1", "bash", ROOT / "tools/phi_decoder_profile_stage.sh",
                 stage, args.xls_root, "20m", shards, 2, 1], ROOT, stage / "profile.log", 3700)
        command(["python3", ROOT / "tools/phi_profile_timeline.py", stage / "phi_decoder_profile.trace.csv",
                 stage / "timeline.svg", "--topology", compiled / "sources/phi_decoder_profile_topology.x",
                 "--scheduler", "phi_0", "--occurrence", 100, "--pipeline-stages", 2], ROOT, stage / "trace.log")
        summary["trace"] = (stage / "trace.log").read_text().splitlines()
    (stage / "validation.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(f"PASS: {name}: BEAM and both RTL readiness patterns agree", flush=True)
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xls_root", type=Path)
    parser.add_argument("--stage", type=Path, default=ROOT / "_build/decoder-profiles")
    parser.add_argument("--cases", nargs="+", choices=CASES,
                        default=["board-sized", "small-both", "small-x", "rectangle-z"])
    parser.add_argument("--trace", action="store_true", help="also check optional inter-proc traces and the profile shell runner")
    args = parser.parse_args()
    args.stage, args.xls_root = args.stage.resolve(), args.xls_root.resolve()
    args.stage.mkdir(parents=True, exist_ok=True)
    (args.stage / "results.json").unlink(missing_ok=True)
    command(["rebar3", "as", "test", "compile"], ROOT, args.stage / "erlang.log")
    results = {name: exercise(name, CASES[name], args) for name in args.cases}
    # Plane removal preserves the exact event stream, including the seed block.
    if {"small-both", "small-x"} <= results.keys():
        both = sequences(json.loads((args.stage / "small-both/oracle.json").read_text()))
        single = sequences(json.loads((args.stage / "small-x/oracle.json").read_text()))
        assert single == {key: values for key, values in both.items() if key[0] == 0}
    (args.stage / "results.json").write_text(json.dumps(results, indent=2) + "\n")


if __name__ == "__main__":
    main()
