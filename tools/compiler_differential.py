#!/usr/bin/env python3
"""Generate, compare, replay, and shrink bounded Erlang/XLS programs."""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time

import compiler_differential_cases as cases

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ("interpreter_main", "ir_converter_main", "opt_main", "codegen_main")


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def execute(argv, stage, name, timeout):
    """Retain exact commands and kill the whole tool process group on timeout."""
    started = time.monotonic()
    with (stage / f"{name}.stdout").open("wb") as out, (stage / f"{name}.stderr").open("wb") as err:
        process = subprocess.Popen([str(a) for a in argv], cwd=ROOT, stdout=out, stderr=err,
                                   start_new_session=True)
        try:
            code = process.wait(timeout=timeout)
            timed_out = False
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            code = process.wait()
            timed_out = True
        except BaseException:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            raise
    result = {"argv": [str(a) for a in argv], "cwd": str(ROOT), "returncode": code,
              "timeout": timed_out, "seconds": round(time.monotonic() - started, 3)}
    write_json(stage / f"{name}.command.json", result)
    return result


def category(phase, log):
    if phase == "dslx" and ("assert_eq failed" in log or "were not equal" in log):
        return "result_mismatch"
    if phase == "rtl" and "DIFFERENTIAL MISMATCH" in log:
        return "result_mismatch"
    for diagnostic in ("TypeInferenceError", "TypeMismatchError", "ParseError", "ScanError",
                       "FailureError", "INVALID_ARGUMENT", "INTERNAL"):
        if diagnostic in log:
            return diagnostic
    return "tool_error"


class Runner:
    def __init__(self, xls, stage, timeout=90):
        self.xls, self.stage, self.timeout = xls.resolve(), stage.resolve(), timeout
        self.library = self.stage / "lib"

    def prepare(self, compile=True):
        self.stage.mkdir(parents=True, exist_ok=True)
        for tool in TOOLS:
            if not (self.xls / tool).is_file():
                raise ValueError(f"missing XLS tool: {self.xls / tool}")
        if compile:
            result = execute(["rebar3", "as", "test", "compile"], self.stage, "compile", 180)
            if result["returncode"]:
                raise RuntimeError(f"rebar3 failed; see {self.stage / 'compile.stderr'}")
        shutil.copytree(ROOT / "priv/xls/lib", self.library, dirs_exist_ok=True)
        files = [*self.library.glob("*.x"), *self.xls.glob("xls/dslx/stdlib/**/*.x"),
                 *ROOT.glob("_build/test/lib/erl_hls/ebin/*.beam"),
                 ROOT / "_build/test/lib/erl_hls/test/xls_differential_worker.beam",
                 Path(__file__), Path(cases.__file__), ROOT / "test/xls_differential_worker.erl"]
        version = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True,
                                 capture_output=True, check=True).stdout.strip()
        write_json(self.stage / "provenance.json", {"git_head": version,
            "files": {str(p): digest(p) for p in files},
            "xls": {str(self.xls / t): digest(self.xls / t) for t in TOOLS},
            "python": sys.version})

    def run(self, programs, name, rtl=False):
        stage = self.stage / name
        stage.mkdir(parents=True)  # Never mix fresh evidence with an earlier run.
        write_json(stage / "cases.json", programs)
        source = stage / "xls_differential_fixture.erl"
        source.write_text(cases.source(programs))
        request = {"source": str(source), "dslx": str(stage / "probe.x"),
                   "output": str(stage / "oracle.json"), "cases": []}
        for i, p in enumerate(programs):
            width, signed = cases.TYPES[p["type"]]
            request["cases"].append({"name": f"probe_{i}", "width": width,
                                      "signed": signed, "inputs": p["inputs"]})
        write_json(stage / "request.json", request)
        commands = [
            ("lower", ["erl", "-noshell", "-pa", ROOT / "_build/test/lib/erl_hls/ebin",
                       ROOT / "_build/test/lib/erl_hls/test", "-s", "xls_differential_worker", "main",
                       "-extra", stage / "request.json"]),
            ("dslx", [self.xls / "interpreter_main", "--compare=jit", *self.options(), stage / "probe.x"])]
        result = {"status": "ok", "stage": str(stage), "programs": len(programs),
                  "vectors": sum(len(p["inputs"]) for p in programs), "rtl": rtl}
        for phase, command in commands:
            failure = self.command(phase, command, stage)
            if failure:
                return self.finish(stage, {**result, **failure})
            if phase == "lower":
                oracle = json.loads((stage / "oracle.json").read_text())
                if oracle["status"] != "ok":
                    # Keep the structured Erlang reason so reducer predicates do not
                    # confuse unsupported source with a generated invalid program.
                    reason = re.match(r"[a-z_]+|\{([a-z_]+)", oracle.get("reason", ""))
                    return self.finish(stage, {**result, "status": "failed", "phase": "lower",
                        "category": oracle["status"], "reason": reason.group(0) if reason else "unknown",
                        "location": oracle.get("location")})
                result["outcomes"] = dict(sorted(Counter(
                    value >> 32 for c in oracle["cases"] for value in c["expected"]).items()))
                if any(p.get("total") and any(v >> 32 for v in reference["expected"])
                       for p, reference in zip(programs, oracle["cases"])):
                    return self.finish(stage, {**result, "status": "failed", "phase": "oracle",
                                               "category": "invalid_total_program"})
        log = (stage / "dslx.stderr").read_text()
        if not re.search(rf"\b{len(programs)} test\(s\) ran", log):
            return self.finish(stage, {**result, "status": "failed", "phase": "dslx",
                                       "category": "missing_tests"})
        # Conversion in interpreter_main stays in memory. Always cross the text
        # IR boundary, even in campaigns that sample only a few RTL batches.
        pipeline = [
            ("convert", [self.xls / "ir_converter_main", "--top=probe", *self.options(), stage / "probe.x"], "probe.ir"),
            ("optimize", [self.xls / "opt_main", stage / "probe.ir"], "probe.opt.ir")]
        if rtl:
            self.testbench(stage, programs, oracle["cases"])
            pipeline += [
                ("codegen", [self.xls / "codegen_main", "--generator=combinational",
                             "--module_name=probe", "--use_system_verilog=false", stage / "probe.opt.ir"], "probe.v"),
                ("iverilog", ["iverilog", "-g2012", "-s", "differential_tb", "-o", stage / "probe.vvp",
                              stage / "probe.v", stage / "probe_tb.sv"], None),
                ("rtl", ["vvp", stage / "probe.vvp"], None),
            ]
        for phase, command, output in pipeline:
            failure = self.command(phase, command, stage)
            if failure:
                return self.finish(stage, {**result, **failure})
            if output:
                shutil.copyfile(stage / f"{phase}.stdout", stage / output)
        if rtl:
            if f"PASS: {result['vectors']} differential RTL vectors" not in (stage / "rtl.stdout").read_text():
                return self.finish(stage, {**result, "status": "failed", "phase": "rtl",
                                           "category": "missing_tests"})
        return self.finish(stage, result)

    def options(self):
        return ["--warnings_as_errors=false", f"--dslx_path={self.library}",
                f"--dslx_stdlib_path={self.xls / 'xls/dslx/stdlib'}"]

    def command(self, phase, argv, stage):
        result = execute(argv, stage, phase, self.timeout)
        if result["returncode"] or result["timeout"]:
            log = (stage / f"{phase}.stdout").read_text(errors="replace") + (stage / f"{phase}.stderr").read_text(errors="replace")
            return {"status": "failed", "phase": phase,
                    "category": "timeout" if result["timeout"] else category(phase, log)}
        return None

    @staticmethod
    def finish(stage, result):
        write_json(stage / "result.json", result)
        return result

    @staticmethod
    def testbench(stage, programs, oracle):
        rows = []
        for mode, (p, reference) in enumerate(zip(programs, oracle)):
            for inputs, expected in zip(p["inputs"], reference["expected"]):
                row = mode
                for value in inputs:
                    row = (row << 32) | value
                rows.append((row << 36) | expected)
        vectors = stage / "vectors.hex"
        vectors.write_text("".join(f"{row:057x}\n" for row in rows))
        (stage / "probe_tb.sv").write_text(f'''module differential_tb;
  reg [31:0] mode, x, y, a, b, c;
  wire [35:0] out;
  reg [35:0] expected;
  reg [227:0] vectors [0:{len(rows) - 1}];
  integer i;
  probe dut(.mode(mode), .x(x), .y(y), .a(a), .b(b), .c(c), .out(out));
  initial begin
    $readmemh({json.dumps(str(vectors))}, vectors);
    for (i = 0; i < {len(rows)}; i = i + 1) begin
      {{mode, x, y, a, b, c, expected}} = vectors[i]; #1;
      if (out !== expected)
        $fatal(1, "DIFFERENTIAL MISMATCH row=%0d mode=%0d expected=%h actual=%h", i, mode, expected, out);
    end
    $display("PASS: {len(rows)} differential RTL vectors");
    $finish;
  end
endmodule
''')


def signature(result):
    return result.get("phase"), result.get("category"), result.get("reason"), result.get("location")


def minimize(runner, programs, failure, budget):
    """Greedy reductions preserve phase/category, scope, and strict cost descent."""
    target = signature(failure)
    attempts = 0
    history = []
    seen = set()

    def accepts(candidate):
        nonlocal attempts
        key = cases.canonical(candidate)
        if attempts >= budget or key in seen:
            return False
        seen.add(key)
        result = runner.run(candidate, f"shrink/{attempts:04d}", rtl=failure["rtl"])
        attempts += 1
        same = result["status"] == "failed" and signature(result) == target
        history.append({"stage": result["stage"], "accepted": same, "signature": signature(result)})
        return same

    # First isolate a program; a batching-only failure must retain the batch.
    selected = programs
    if len(programs) > 1:
        for program in programs:
            if accepts([program]):
                selected = [program]
                break
    if len(selected) == 1:
        program = selected[0]
        inputs = program["inputs"]
        while len(inputs) > 1 and attempts < budget:
            middle = len(inputs) // 2
            halves = [inputs[:middle], inputs[middle:]]
            accepted = next((h for h in halves if accepts([{**program, "inputs": h}])), None)
            if accepted is None:
                break
            inputs = accepted
            program = {**program, "inputs": inputs}
        while attempts < budget:
            small = next((p for p in cases.program_reductions(program) if accepts([p])), None)
            if small is None:
                break
            program = small
        # Canonicalize the remaining concrete input without increasing any word.
        for i, row in enumerate(program["inputs"]):
            for j in range(len(row)):
                value = program["inputs"][i][j]
                for smaller in dict.fromkeys([0, 1, 2, 3, value // 2]):
                    if smaller >= value:
                        continue
                    inputs = [r[:] for r in program["inputs"]]
                    inputs[i][j] = smaller
                    candidate = {**program, "inputs": inputs}
                    if accepts([candidate]):
                        program = candidate
                        break
        selected = [program]
    write_json(runner.stage / "minimized.json", selected)
    write_json(runner.stage / "shrink.json", {"signature": target, "attempts": attempts,
        "budget": budget, "exhausted": attempts >= budget, "history": history})
    return selected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xls_root", type=Path)
    parser.add_argument("--stage", type=Path, default=ROOT / "_build/compiler-differential")
    parser.add_argument("--seed", type=int, default=20260915)
    parser.add_argument("--start", type=int, default=0)
    parser.add_argument("--count", type=int, default=32)
    parser.add_argument("--depth", type=int, default=3)
    parser.add_argument("--inputs", type=int, default=20)
    parser.add_argument("--batch-size", type=int, default=8)
    parser.add_argument("--rtl-batches", type=int, default=1)
    parser.add_argument("--timeout", type=float, default=90)
    parser.add_argument("--shrink-budget", type=int, default=120)
    parser.add_argument("--replay", type=Path, help="replay a saved cases.json or minimized.json")
    parser.add_argument("--skip-compile", action="store_true")
    args = parser.parse_args()
    if min(args.count, args.depth, args.inputs, args.batch_size, args.timeout) <= 0:
        parser.error("count, depth, inputs, batch size, and timeout must be positive")
    if min(args.start, args.rtl_batches, args.shrink_budget) < 0:
        parser.error("start, RTL batches, and shrink budget must be nonnegative")
    if args.stage.exists():
        parser.error(f"stage already exists; choose a fresh directory: {args.stage}")
    runner = Runner(args.xls_root, args.stage, args.timeout)
    runner.prepare(compile=not args.skip_compile)
    programs = json.loads(args.replay.read_text()) if args.replay else [
        cases.generate(args.seed, i, args.depth, args.inputs) for i in range(args.start, args.start + args.count)]
    if not programs or any(not p.get("inputs") for p in programs):
        parser.error("a campaign must contain programs with input vectors")
    write_json(runner.stage / "campaign.json", {"arguments": {k: str(v) if isinstance(v, Path) else v for k, v in vars(args).items()},
        "coverage": cases.coverage(programs), "programs": len(programs),
        "vectors": sum(len(p["inputs"]) for p in programs)})
    results = []
    started = time.monotonic()
    for n, offset in enumerate(range(0, len(programs), args.batch_size)):
        batch = programs[offset:offset + args.batch_size]
        result = runner.run(batch, f"batch-{n:04d}", rtl=n < args.rtl_batches)
        results.append(result)
        print(f"{result['status']}: batch {n}, {len(batch)} programs, {result['vectors']} vectors"
              f"{', RTL' if result['rtl'] else ''}: {signature(result)}", flush=True)
        if result["status"] != "ok":
            if args.shrink_budget and result["category"] not in ("timeout", "tool_error", "missing_tests", "invalid_source"):
                minimize(runner, batch, result, args.shrink_budget)
            break
    completed = [r for r in results if r["status"] == "ok"]
    summary = {"results": results, "seconds": round(time.monotonic() - started, 3),
               "completed_programs": sum(r["programs"] for r in completed),
               "completed_vectors": sum(r["vectors"] for r in completed),
               "completed_rtl_vectors": sum(r["vectors"] for r in completed if r["rtl"]),
               "status": "ok" if all(r["status"] == "ok" for r in results) else "failed"}
    write_json(runner.stage / "summary.json", summary)
    print(f"{summary['status']}: {runner.stage / 'summary.json'}", flush=True)
    return 0 if summary["status"] == "ok" else 1


if __name__ == "__main__":
    sys.exit(main())
