#!/usr/bin/env python3
"""Run selected compiler regression cases through the common external command executor."""
import argparse
from dataclasses import asdict
import json
from pathlib import Path
import re
import shutil
import sys
import time
from collections.abc import Iterator

from erl_hls_tools import compile_xls as executor
import regression_cases
from regression_inventory import load_inventory, paths_since, select_cases
from regression_steps import Case, Command, Copy, FileText, Rows, Step

ROOT = Path(__file__).resolve().parents[1]


def describe(step: Step) -> dict:
    """Expose the plan without reading generated inputs or executing commands."""
    if isinstance(step, Rows):
        return {"kind": "generated_rows", "source": str(step.source), "columns": step.columns}
    data = asdict(step)
    data["kind"] = "command" if isinstance(step, Command) else "copy"
    return data


def resolve(argument: str | FileText) -> str:
    """Resolve one generated scalar without shell evaluation or argv splitting."""
    if isinstance(argument, FileText):
        text = argument.path.read_text().strip()
        if not text or "\n" in text:
            raise ValueError(f"expected one generated scalar: {argument.path}")
        return argument.prefix + text + argument.suffix
    return argument


def expanded(steps: list[Step]) -> Iterator[Command | Copy]:
    """Read generated variant tables only after earlier fixture steps have completed."""
    for step in steps:
        if isinstance(step, Rows):
            lines = step.source.read_text().splitlines()
            if not lines:
                raise ValueError(f"empty regression variant table: {step.source}")
            for line in lines:
                row = line.split()
                if len(row) != step.columns:
                    raise ValueError(f"invalid regression variant row in {step.source}: {line!r}")
                yield from expanded(step.expand(row))
        else:
            yield step


def require_fresh(stage: Path) -> None:
    """Refuse reused products before any command can accidentally satisfy a new check."""
    if stage.exists() and (not stage.is_dir() or any(stage.iterdir())):
        raise ValueError(f"regression stage must be absent or empty: {stage}; choose a new STAGE")


def run_case(name: str, case: Case) -> dict:
    """Execute in a fresh stage, retaining all inputs, products, logs and failure receipts."""
    require_fresh(case.stage)
    case.stage.mkdir(parents=True, exist_ok=True)
    attempt = case.stage / "logs"
    attempt.mkdir()
    result = {"case": name, "status": "running", "stage": str(case.stage), "steps": []}
    current = case.stage / "regression.json"
    executor.save(current, result)
    try:
        for index, step in enumerate(expanded(case.steps)):
            label = step.name if isinstance(step, Command) else "copy-" + step.source.name
            log = attempt / f"{index:03d}-{re.sub(r'[^a-zA-Z0-9_.-]', '_', label)}"
            log.mkdir()
            row = {"step": label, "status": "running", "log": str(log)}
            result["steps"].append(row)
            executor.save(current, result)
            if isinstance(step, Copy):
                sources = sorted(step.source.glob(step.pattern))
                if not sources:
                    raise ValueError(f"no support inputs match {step.source / step.pattern}")
                step.target.mkdir(parents=True, exist_ok=True)
                for source in sources:
                    shutil.copyfile(source, step.target / source.name)
                row["files"] = [str(step.target / source.name) for source in sources]
            else:
                argv = [resolve(argument) for argument in step.argv]
                stdout = step.stdout or log / "stdout.log"
                stdout.parent.mkdir(parents=True, exist_ok=True)
                for directory in step.directories:
                    directory.mkdir(parents=True, exist_ok=True)
                executor.save(log / "command.json", {"argv": argv, "cwd": str(case.root),
                    "stdout": str(stdout), "timeout": step.timeout, "rejection": step.rejection,
                    "products": list(map(str, step.products)), "completion": step.completion})
                print(f"{name}: {label}", flush=True)
                row["metrics"] = executor.run(argv, log, str(stdout), step.timeout,
                    cwd=case.root, allow_empty=not step.nonempty, expect_failure=step.rejection)
                for product in step.products:
                    if not product.is_file() or not product.stat().st_size:
                        raise ValueError(f"missing regression product: {product}")
                if step.completion is not None and step.completion not in stdout.read_text(errors="replace"):
                    raise ValueError(f"missing regression completion witness: {step.completion}")
                row["stdout"] = str(stdout)
                row["expected_rejection"] = step.rejection is not None
            row["status"] = "passed"
            executor.save(current, result)
        result["status"] = "passed"
        print(f"PASS: {name} ({len(result['steps'])} steps); {current}", flush=True)
    except BaseException as error:
        result["status"] = "failed"
        result["error"] = str(error)
        if result["steps"] and result["steps"][-1]["status"] == "running":
            result["steps"][-1]["status"] = "failed"
        raise
    finally:
        executor.save(current, result)
        executor.save(attempt / "result.json", result)
    return result


def selected(args: argparse.Namespace, inventory: dict, root: Path) -> list[str]:
    """Resolve one explicit selection; an empty JSON list is an intentional no-op."""
    if args.cases_json is not None:
        names = json.loads(args.cases_json)
        if not isinstance(names, list) or any(not isinstance(name, str) for name in names):
            raise ValueError("--cases-json requires an array of case names")
    elif args.cases is not None:
        names = args.cases
    elif args.all:
        names = list(inventory["cases"])
    elif args.changed_since is not None:
        names = select_cases(paths_since(args.changed_since, root), inventory)
    else:
        raise ValueError("select --cases, --cases-json, --all or --changed-since")
    names = list(dict.fromkeys(names))
    unknown = set(names) - inventory["cases"].keys()
    if unknown:
        raise ValueError("unknown regression cases: " + ", ".join(sorted(unknown)))
    return names


def make_cases(names: list[str], inventory: dict, root: Path, xls: Path,
               stage: Path | None, placements: tuple[str, ...]) -> list[tuple[str, Case]]:
    """Allocate fresh default stages and compile test BEAMs once before the selected fixtures."""
    cases = []
    run_id = str(time.time_ns())
    for name in names:
        directory = root / inventory["cases"][name]["default_stage"] / run_id if stage is None else (
            stage if len(names) == 1 else stage / name)
        case = Case(root, xls, directory.resolve(), placements)
        factory = getattr(regression_cases, name)
        factory(case)
        cases.append((name, case))
    compile_step = next((step for _, case in cases for step in case.steps
                         if isinstance(step, Command) and step.name == "beam-compile"), None)
    if compile_step is not None:
        for _, case in cases:
            case.steps = [step for step in case.steps if not (isinstance(step, Command) and step.name == "beam-compile")]
        cases[0][1].steps.insert(0, compile_step)
    return cases


def main(argv: list[str] | None = None) -> None:
    """Select local/CI cases, preview descriptions, or execute with retained stage diagnostics."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xls", nargs="?", type=Path)
    parser.add_argument("stage", nargs="?", type=Path)
    selection = parser.add_mutually_exclusive_group()
    selection.add_argument("--cases", nargs="+")
    selection.add_argument("--cases-json")
    selection.add_argument("--all", action="store_true")
    selection.add_argument("--changed-since")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--placements", nargs="+", choices=("direct", "ingress_direct"), default=("direct", "ingress_direct"))
    args = parser.parse_args(argv)
    inventory = load_inventory(ROOT)
    if args.list:
        print(json.dumps(inventory, indent=2))
        return
    try:
        names = selected(args, inventory, ROOT)
        if not names:
            print("No regression cases selected.")
            return
        if args.xls is None:
            raise ValueError("XLS_ROOT is required")
        cases = make_cases(names, inventory, ROOT, args.xls.resolve(), args.stage, tuple(args.placements))
        if args.dry_run:
            print(json.dumps([{ "case": name, "stage": str(case.stage), "steps": [describe(s) for s in case.steps]}
                              for name, case in cases], default=str, indent=2))
        else:
            for _, case in cases:
                require_fresh(case.stage)
            for name, case in cases:
                run_case(name, case)
    except (ValueError, OSError, RuntimeError, TimeoutError) as error:
        parser.exit(1, f"regression failed: {error}\n")


if __name__ == "__main__":
    main()
