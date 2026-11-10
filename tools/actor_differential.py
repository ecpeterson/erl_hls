#!/usr/bin/env python3
"""Compare finite BEAM actors with their generated RTL owners; retain and shrink failures."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import shutil
from typing import Any

import actor_differential_cases as cases
import compiler_differential as differential

ROOT = Path(__file__).resolve().parents[1]
Result = dict[str, Any]


def observation(word: int) -> dict[str, Any]:
    """Decode only the test observation word, never the generated owner's opaque state."""
    return {"phase": (word >> 47) & 255, "value": (word >> 39) & 255,
            "occupied": (word >> 31) & 255, "postponed": (word >> 23) & 255,
            "failure": (word >> 19) & 15, "pending": (word >> 18) & 1,
            "accepted": (word >> 17) & 1, "event": ((word >> 8) & 255, word & 255)
            if (word >> 16) & 1 else None}


def compare(program: cases.Program, oracle: dict[str, Any], log: str) -> Result | None:
    """Compare every drained prefix and ordered effects; keep semantic mismatches distinct."""
    if len(oracle["segments"]) != len(program["segments"]):
        return {"category": "invalid_oracle", "reason": "segment_count"}
    rows: dict[int, list[dict[str, Any]]] = {}
    for segment, cycle, word in re.findall(r'^ACTOR (\d+) (\d+) ([0-9a-f]+)$', log, re.M):
        values = rows.setdefault(int(segment), [])
        if int(cycle) != len(values):
            return {"category": "invalid_trace", "reason": "cycle_order"}
        values.append(observation(int(word, 16)))
    if len(rows) != len(program["segments"]) or "PASS: actor trace complete" not in log:
        return {"category": "missing_tests"}
    failed = None
    for index, (segment, expected) in enumerate(zip(program["segments"], oracle["segments"])):
        cycles = rows.get(index, [])
        if len(cycles) != cases.HORIZON:
            return {"category": "invalid_trace", "reason": "horizon", "segment": index}
        if segment["reset"]:
            failed = None
        previous = None
        for clock, row in enumerate(cycles):
            if failed is not None:
                if any(row[k] != failed[k] for k in ("failure", "phase", "value")) or row["event"] or row["accepted"]:
                    return {"category": "result_mismatch", "reason": "failure_latch", "segment": index}
            elif row["failure"]:
                failed = row
            ready = clock >= 16 or (segment["ready"] >> clock) & 1
            if not ready and row["event"] is not None:
                return {"category": "result_mismatch", "reason": "stalled_output", "segment": index}
            if previous and previous["pending"] and not ready:
                # This grammar has at least two infallible effects per entry.
                # A blocked entry cannot publish its tentative state early.
                if any(row[key] != previous[key] for key in ("phase", "value", "pending")):
                    return {"category": "result_mismatch", "reason": "stalled_commit", "segment": index}
            previous = row
        last = cycles[-1]
        checks = ["failure", "phase", "value"]
        if not expected["failure"]:
            checks += ["postponed"]
        for field in checks:
            if last[field] != expected[field]:
                return {"category": "result_mismatch", "reason": field, "segment": index,
                        "expected": expected[field], "actual": last[field]}
        events = [list(row["event"]) for row in cycles if row["event"] is not None]
        if events != expected["events"]:
            return {"category": "result_mismatch", "reason": "ordered_events", "segment": index,
                    "expected": expected["events"], "actual": events}
        if not expected["failure"]:
            accepted = sum(row["accepted"] for row in cycles)
            if accepted != len(segment["commands"]) or last["pending"] or last["occupied"] != last["postponed"]:
                return {"category": "incomplete_tail", "segment": index,
                        "accepted": accepted, "offered": len(segment["commands"]), "last": last}
    return None


def testbench(program: cases.Program, width: int) -> str:
    """Drive framed inputs only when admitted; the generated owner handles all scheduling."""
    segments = []
    for i, s in enumerate(program["segments"]):
        setup = "\n".join(f"    commands[{j}] = 16'h{kind:02x}{value:02x};"
                          for j, (kind, value) in enumerate(s["commands"]))
        segments.append(f'''    segment = {i}; count = {len(s['commands'])}; cursor = 0;
    calendar = 16'h{s['ready']:04x};
{setup}
    if ({int(s['reset'])}) begin
      reset = 1; valid = 0; ready = 0; #1;
      machine = out[{width + 63}:64]; reset = 0;
    end
    for (cycle = 0; cycle < {cases.HORIZON}; cycle = cycle + 1) begin
      valid = cursor < count;
      {{kind, value}} = valid ? commands[cursor] : 16'b0;
      ready = cycle < 16 ? calendar[cycle] : 1'b1;
      #1;
      observed = out[63:0];
      $display("ACTOR %0d %0d %016h", segment, cycle, observed);
      machine = out[{width + 63}:64];
      if (observed[17]) cursor = cursor + 1;
    end
''')
    return f'''module actor_differential_tb;
  reg [{width - 1}:0] machine = 0;
  reg [7:0] kind = 0, value = 0;
  reg valid = 0, ready = 0, reset = 0;
  wire [{width + 63}:0] out;
  reg [63:0] observed;
  reg [15:0] commands [0:7];
  reg [15:0] calendar;
  integer segment, count, cursor, cycle;
  differential_step dut(.machine(machine), .kind(kind), .value(value),
      .valid(valid), .ready(ready), .reset(reset), .out(out));
  initial begin
{''.join(segments)}
    $display("PASS: actor trace complete");
    $finish;
  end
endmodule
'''


class Runner(differential.Runner):
    """Reuse bounded tool execution and provenance while compiling real stateful actor steps."""

    def prepare(self, compile: bool = True) -> None:
        """Prepare the shared compiler tools and bind every actor-harness source to the run."""
        super().prepare(compile)
        path = self.stage / "provenance.json"
        provenance = json.loads(path.read_text())
        for file in (Path(__file__), Path(cases.__file__),
                     ROOT / "tools/test_actor_differential.py",
                     ROOT / "test/xls_actor_differential_worker.erl",
                     ROOT / "test_data/xls_actor_differential.inc.x",
                     ROOT / "_build/test/lib/erl_hls/test/xls_actor_differential_worker.beam"):
            provenance["files"][str(file)] = differential.digest(file)
        differential.write_json(path, provenance)

    def run_actor(self, program: cases.Program, name: str) -> Result:
        """Retain one source, actual BEAM observations, optimized RTL and its finite trace."""
        if not cases.valid(program):
            raise ValueError("invalid replay actor")
        stage = self.stage / name
        stage.mkdir(parents=True)
        differential.write_json(stage / "case.json", program)
        source = stage / "xls_actor_differential_fixture.erl"
        source.write_text(cases.source(program))
        differential.write_json(stage / "request.json", {
            "source": str(source), "dslx": str(stage / "actor.x"),
            "output": str(stage / "oracle.json"), "program": program})
        result: Result = {"status": "ok", "stage": str(stage), "segments": len(program["segments"]),
                          "clocks": len(program["segments"]) * cases.HORIZON}
        failure = self.command("oracle", ["erl", "-noshell", "-pa",
            ROOT / "_build/test/lib/erl_hls/ebin", ROOT / "_build/test/lib/hls_runtime/ebin",
            ROOT / "_build/test/lib/erl_hls/test", "-s", "xls_actor_differential_worker", "main",
            "-extra", stage / "request.json"], stage)
        if failure:
            return self.finish(stage, {**result, **failure})
        oracle = json.loads((stage / "oracle.json").read_text())
        if oracle["status"] != "ok":
            return self.finish(stage, {**result, "status": "failed", "phase": "oracle",
                "category": oracle["status"], "reason": oracle.get("reason")})
        source = stage / "actor.x"
        source.write_text(source.read_text() + (ROOT / "test_data/xls_actor_differential.inc.x").read_text())
        self.inject(source)
        pipeline = [
            ("convert", [self.xls / "ir_converter_main", "--top=differential_step", *self.options(), source], "actor.ir"),
            ("optimize", [self.xls / "opt_main", stage / "actor.ir"], "actor.opt.ir"),
            ("codegen", [self.xls / "codegen_main", "--generator=combinational",
                         "--module_name=differential_step", "--use_system_verilog=false",
                         stage / "actor.opt.ir"], "actor.v")]
        for phase, command, output in pipeline:
            failure = self.command(phase, command, stage)
            if failure:
                return self.finish(stage, {**result, **failure})
            shutil.copyfile(stage / f"{phase}.stdout", stage / output)
        verilog = (stage / "actor.v").read_text()
        port = re.search(r'input\s+wire\s+\[(\d+):0\]\s+machine\b', verilog)
        output = re.search(r'output\s+wire\s+\[(\d+):0\]\s+out\b', verilog)
        if not port or not output or int(output[1]) != int(port[1]) + 64:
            return self.finish(stage, {**result, "status": "failed", "phase": "codegen",
                                      "category": "unexpected_probe_interface"})
        (stage / "actor_tb.sv").write_text(testbench(program, int(port[1]) + 1))
        for phase, command in [
            ("iverilog", ["iverilog", "-g2012", "-s", "actor_differential_tb", "-o",
                          stage / "actor.vvp", stage / "actor.v", stage / "actor_tb.sv"]),
            ("rtl", ["vvp", stage / "actor.vvp"])]:
            failure = self.command(phase, command, stage)
            if failure:
                return self.finish(stage, {**result, **failure})
        mismatch = compare(program, oracle, (stage / "rtl.stdout").read_text())
        if mismatch:
            return self.finish(stage, {**result, "status": "failed", "phase": "rtl", **mismatch})
        return self.finish(stage, result)

    def inject(self, source: Path) -> None:
        """Leave production runs untouched; the detector self-test overrides this hook."""


def signature(result: Result) -> tuple[Any, Any, Any]:
    """Keep minimization within one failure phase/category/observable, not a specific row."""
    return result.get("phase"), result.get("category"), result.get("reason")


def minimize(runner: Runner, program: cases.Program, failure: Result, budget: int) -> cases.Program:
    """Greedily shrink finite schedules, retaining exact actor code and mismatch class."""
    selected = program
    target = signature(failure)
    history: list[dict[str, Any]] = []
    seen: set[str] = set()
    while len(history) < budget:
        improved = False
        for candidate in cases.reductions(selected):
            key = json.dumps(candidate, sort_keys=True)
            if key in seen:
                continue
            seen.add(key)
            result = runner.run_actor(candidate, f"shrink/{len(history):04d}")
            accepted = result["status"] == "failed" and signature(result) == target
            history.append({"accepted": accepted, "signature": signature(result), "stage": result["stage"]})
            if accepted:
                selected, improved = candidate, True
                break
            if len(history) >= budget:
                break
        if not improved:
            break
    differential.write_json(runner.stage / "minimized.json", selected)
    differential.write_json(runner.stage / "shrink.json", {"signature": target, "budget": budget,
        "attempts": len(history), "exhausted": len(history) >= budget, "history": history})
    return selected


def main() -> None:
    """Run a fresh bounded campaign or replay one complete saved source/schedule descriptor."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xls_root", type=Path)
    parser.add_argument("--stage", type=Path, default=ROOT / "_build/actor-differential")
    parser.add_argument("--seed", type=int, default=20261109)
    parser.add_argument("--start", type=int, default=0)
    parser.add_argument("--count", type=int, default=4)
    parser.add_argument("--timeout", type=float, default=90)
    parser.add_argument("--shrink-budget", type=int, default=20)
    parser.add_argument("--replay", type=Path)
    parser.add_argument("--skip-compile", action="store_true")
    args = parser.parse_args()
    if args.count < 1 or args.start < 0 or args.timeout <= 0 or args.shrink_budget < 0:
        parser.error("invalid campaign bounds")
    if args.stage.exists():
        parser.error("stage already exists; choose a fresh path")
    programs = [json.loads(args.replay.read_text())] if args.replay else [
        cases.generate(args.seed, i) for i in range(args.start, args.start + args.count)]
    if not all(cases.valid(program) for program in programs):
        parser.error("invalid replay program")
    runner = Runner(args.xls_root, args.stage, args.timeout)
    runner.prepare(compile=not args.skip_compile)
    differential.write_json(runner.stage / "campaign.json", {"seed": args.seed, "start": args.start,
        "count": len(programs), "horizon": cases.HORIZON, "programs": programs})
    results = []
    for index, program in enumerate(programs):
        result = runner.run_actor(program, f"case-{index:04d}")
        results.append(result)
        differential.write_json(runner.stage / "summary.json", results)
        if result["status"] != "ok":
            if result.get("category") == "result_mismatch" and args.shrink_budget:
                minimize(runner, program, result, args.shrink_budget)
            raise SystemExit(json.dumps(result))
    print(f"PASS: {len(results)} BEAM/generated-owner actors, {sum(r['clocks'] for r in results)} finite RTL clocks")


if __name__ == "__main__":
    main()
