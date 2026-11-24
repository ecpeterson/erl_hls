#!/usr/bin/env python3
"""Run the finite, provenance-bound local/shared XC7 feedback witness in three stages."""
from pathlib import Path
import argparse
import hashlib
import json
import math
import re
import shutil

from backend_commands import digest, run
from backend_paths import ROOT, erlang_environment
from protocol_test_build import compile_build
from test_protocol_arithmetic import action_contract, feedback, mapped_cost, simulate


ROUTE_SCRIPT = Path(__file__).with_name("protocol_arithmetic_route.tcl")
ROUTE_FILES = (
    "core.v", "coverage.rpt", "drc.rpt", "input-identity.json", "paths.rpt",
    "protocol_arithmetic_route.tcl", "protocol_network.sv", "recipe.txt",
    "route-status.rpt", "routed.dcp", "synthesized.dcp", "synthesis-timing.rpt",
    "synthesis-utilization.rpt", "timing.rpt", "utilization.rpt", "workload.xdc",
)
EXPECTED_RECIPE = {
    "part": "xc7z030sbg485-1",
    "top": "protocol_network",
    "clock": "clk",
    "period_ns": "10.0",
    "threads": "1",
    "synth_flatten": "rebuilt",
    "place_directive": "Default",
    "phys_opt_directive": "Default",
    "route_directive": "Default",
    "external_io_false_paths": "true",
    "route_status": "Route Complete",
}


def write_json(path: Path, value: object) -> None:
    """Write one deterministic local evidence record."""
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def sha256_bytes(value: object) -> str:
    """Identify a JSON-compatible value with the canonical encoding used for evidence links."""
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def implementation_record(build: Path, planned: dict) -> dict:
    """Extract and cross-check the four correlated identities from a compiled planned build."""
    receipt_path = build / "compiled.json"
    receipt = json.loads(receipt_path.read_text())
    provenance = receipt["provenance"]
    if provenance["implementation_plan_sha256"] != planned["plan"]:
        raise ValueError("compiled implementation is not bound to the retained plan")
    if receipt["implementation"]["provenance"] != provenance:
        raise ValueError("implementation receipt changed the planned provenance")
    return {
        "logical_system": provenance["logical_system_sha256"],
        "plan": planned["plan"],
        "projection": provenance["target_projection_sha256"],
        "request": receipt["build_request"]["sha256"],
        "product": receipt["products"]["sha256"],
        "implementation": receipt["implementation"]["sha256"],
        "compiled_json_sha256": digest(receipt_path),
    }


def prepare_route_input(candidate: Path, build: Path, identities: dict) -> dict:
    """Freeze and return the complete generated RTL, identity and recipe descriptor."""
    route_input = candidate / "route-input"
    route_input.mkdir()
    sources = {}
    for name, source in {
        "core.v": build / "network/core.v",
        "protocol_network.sv": build / "network/protocol_network.sv",
    }.items():
        target = route_input / name
        shutil.copy2(source, target)
        sources[name] = digest(target)
    shutil.copy2(ROUTE_SCRIPT, route_input / ROUTE_SCRIPT.name)
    identity = {
        "schema": 1,
        "identities": identities,
        "sources": sources,
        "route_recipe_sha256": digest(ROUTE_SCRIPT),
    }
    write_json(route_input / "identity.json", identity)
    return identity


def utilization(text: str) -> dict[str, int]:
    """Read the complete top row of a Vivado hierarchical utilization report."""
    columns = None
    for line in text.splitlines():
        cells = [cell.strip() for cell in line.split("|")[1:-1]]
        if "Total LUTs" in cells:
            columns = cells
        elif columns is not None and len(cells) == len(columns) and len(cells) > 1 and cells[1] == "(top)":
            values = {name: int(value) for name, value in zip(columns[2:], cells[2:])}
            required = {"Total LUTs", "FFs", "DSP Blocks"}
            if not required.issubset(values):
                raise ValueError("missing required utilization columns")
            return {"lut": values["Total LUTs"], "ff": values["FFs"], "dsp": values["DSP Blocks"]}
    raise ValueError("missing top-level utilization row")


def timing(text: str) -> dict[str, float | int]:
    """Read design-wide setup, hold and pulse results without treating a routed run as closure."""
    match = re.search(r"WNS\(ns\).*?\n\s*-+.*?\n\s*([^\n]+)", text, re.S)
    if match is None:
        raise ValueError("missing timing summary")
    fields = match[1].split()
    if len(fields) != 12:
        raise ValueError("unexpected timing summary columns")
    return {
        "worst_slack_ns": float(fields[0]),
        "setup_failing_endpoints": int(fields[2]),
        "worst_hold_slack_ns": float(fields[4]),
        "hold_failing_endpoints": int(fields[6]),
        "worst_pulse_slack_ns": float(fields[8]),
        "pulse_failing_endpoints": int(fields[10]),
    }


def timing_coverage(text: str) -> dict[str, int]:
    """Read the two internal timing-coverage checks required by this OOC witness."""
    result = {}
    for name in ("no_clock", "unconstrained_internal_endpoints"):
        match = re.search(rf"\bchecking\s+{name}\s*\((\d+)\)", text, re.I)
        if match is None:
            raise ValueError(f"missing check_timing coverage row: {name}")
        result[name] = int(match.group(1))
    return result


def recipe(path: Path) -> dict[str, str]:
    """Require the closed Stage 5 native recipe and the selected Vivado release."""
    values = {}
    for line in path.read_text().splitlines():
        if "=" not in line:
            raise ValueError("malformed route recipe row")
        key, value = line.split("=", 1)
        if not key or key in values:
            raise ValueError("duplicate or empty route recipe key")
        values[key] = value
    if set(values) != {"tool", *EXPECTED_RECIPE}:
        raise ValueError("route recipe has unknown or missing settings")
    if {key: values.get(key) for key in EXPECTED_RECIPE} != EXPECTED_RECIPE:
        raise ValueError("route recipe differs from the fixed Stage 5 settings")
    if values.get("tool") != "2024.2":
        raise ValueError("the routed witness requires Vivado 2024.2")
    return values


def routed_evidence(
    case: str, candidate: Path, route: Path, expected_identity: dict
) -> tuple[dict, str]:
    """Bind exact inputs, reports and settings; return the narrow physical metrics and identity."""
    if case not in ("local3", "shared3"):
        raise ValueError("unknown finite candidate")
    identity_keys = {
        "compiled_json_sha256",
        "implementation",
        "logical_system",
        "plan",
        "product",
        "projection",
        "request",
    }
    if (
        not isinstance(expected_identity, dict)
        or set(expected_identity) != {
            "schema", "identities", "sources", "route_recipe_sha256"
        }
        or expected_identity.get("schema") != 1
    ):
        raise ValueError("invalid expected route-input identity")
    expected_identities = expected_identity.get("identities")
    if (
        not isinstance(expected_identities, dict)
        or set(expected_identities) != identity_keys
        or any(
            not isinstance(value, str) or re.fullmatch(r"[0-9a-f]{64}", value) is None
            for value in expected_identities.values()
        )
    ):
        raise ValueError("invalid expected implementation identities")
    expected_sources = expected_identity.get("sources")
    if (
        not isinstance(expected_sources, dict)
        or set(expected_sources) != {"core.v", "protocol_network.sv"}
        or any(
            not isinstance(value, str) or re.fullmatch(r"[0-9a-f]{64}", value) is None
            for value in expected_sources.values()
        )
    ):
        raise ValueError("invalid expected routed source identity")
    expected_recipe = expected_identity.get("route_recipe_sha256")
    if (
        not isinstance(expected_recipe, str)
        or re.fullmatch(r"[0-9a-f]{64}", expected_recipe) is None
        or expected_recipe != digest(ROUTE_SCRIPT)
    ):
        raise ValueError("invalid expected routed recipe identity")
    source_identity = json.loads((candidate / "route-input/identity.json").read_text())
    if source_identity != expected_identity:
        raise ValueError("prepared route input differs from workflow state")
    routed_identity = json.loads((route / "input-identity.json").read_text())
    if routed_identity != source_identity:
        raise ValueError("routed input identity differs from the prepared candidate")
    retained_sources = {name: digest(route / name) for name in sorted(expected_sources)}
    prepared_sources = {
        name: digest(candidate / "route-input" / name) for name in sorted(expected_sources)
    }
    if retained_sources != expected_sources or prepared_sources != expected_sources:
        raise ValueError("routed RTL differs from the prepared candidate")
    if (
        digest(route / ROUTE_SCRIPT.name) != expected_recipe
        or digest(candidate / "route-input" / ROUTE_SCRIPT.name) != expected_recipe
    ):
        raise ValueError("routed recipe differs from the prepared candidate")
    settings = recipe(route / "recipe.txt")
    missing = [name for name in ROUTE_FILES if not (route / name).is_file()]
    if missing:
        raise ValueError(f"missing routed artifacts: {missing}")
    resources = utilization((route / "utilization.rpt").read_text())
    route_timing = timing((route / "timing.rpt").read_text())
    route_coverage = timing_coverage((route / "coverage.rpt").read_text())
    for value in (*resources.values(), *route_timing.values(), *route_coverage.values()):
        if isinstance(value, float) and not math.isfinite(value):
            raise ValueError("non-finite routed metric")
    evidence = {
        "schema": 1,
        "case": case,
        "identity": source_identity,
        "settings": settings,
        "outputs": {name: digest(route / name) for name in ROUTE_FILES},
        "resources": resources,
        "timing": route_timing,
        "coverage": route_coverage,
        "method": "One serial, single-threaded Vivado 2024.2 OOC route with fixed part, 10 ns clock and Default implementation directives.",
        "scope": "Finite native routed witness for this exact planned arithmetic implementation.",
        "limits": "No board execution, general optimum, frequency guarantee, route-seed sensitivity or sustained-workload claim.",
    }
    evidence_path = candidate / "route-evidence.json"
    write_json(evidence_path, evidence)
    evidence_identity = digest(evidence_path)
    metrics = {
        "case": case,
        "resources": resources,
        "timing": route_timing,
        "coverage": route_coverage,
    }
    write_json(candidate / "route-metrics.json", metrics)
    return metrics, evidence_identity


def build_candidate(xls: Path, candidate: Path, plan: Path, planned: dict, yosys: Path,
                    cache: Path, *, contracts: bool) -> tuple[dict, dict]:
    """Compile, simulate and map one retained plan, then freeze its native-route payload."""
    source = candidate / "build"
    emitted = feedback(candidate, "emit", "write", plan, source)
    if emitted["plan"] != planned["plan"]:
        raise ValueError("planned writer changed the retained implementation plan")
    build = compile_build(xls, source, profile="test+spacetime", cache=cache)
    simulate(build, candidate, 3)
    cost = mapped_cost(build, candidate, yosys)
    if contracts:
        action_contract(xls, build, candidate, yosys)
    identities = implementation_record(build, emitted)
    result = {"plan": emitted, "identities": identities, "mapped_cost": cost}
    write_json(candidate / "implementation.json", result)
    route_identity = prepare_route_input(candidate, build, identities)
    return result, route_identity


def baseline(args: argparse.Namespace) -> None:
    """Prepare the exact local plan, semantic evidence and first native-route payload."""
    args.stage.mkdir()
    run(["rebar3", "as", "test,spacetime", "compile"], args.stage, "build-backend")
    candidate = args.stage / "local3"
    candidate.mkdir()
    plan = candidate / "implementation-plan.etf"
    planned = feedback(candidate, "propose", "propose", "local3", plan)
    result, route_identity = build_candidate(
        args.xls,
        candidate,
        plan,
        planned,
        args.yosys,
        args.stage / "implementation-cache",
        contracts=False,
    )
    write_json(args.stage / "state.json", {
        "schema": 1,
        "phase": "awaiting_local_route",
        "local3": result,
        "route_inputs": {"local3": route_identity},
    })


def revise(args: argparse.Namespace) -> None:
    """Consume the exact local route, characterize it and prepare only its revised shared plan."""
    state_path = args.stage / "state.json"
    state = json.loads(state_path.read_text())
    if state.get("phase") != "awaiting_local_route":
        raise ValueError("feedback state is not awaiting the local route")
    local = args.stage / "local3"
    _metrics, evidence = routed_evidence(
        "local3", local, args.route, state["route_inputs"]["local3"]
    )
    shared = args.stage / "shared3"
    shared.mkdir()
    revised_plan = shared / "implementation-plan.etf"
    revision = feedback(
        shared,
        "revise-local",
        "revise",
        local / "implementation-plan.etf",
        state["local3"]["identities"]["implementation"],
        evidence,
        local / "route-metrics.json",
        local / "characterization.etf",
        revised_plan,
    )
    if revision["action"] != "share" or revision["parent_plan"] != state["local3"]["plan"]["plan"]:
        raise ValueError("local routed feedback did not produce the expected direct sharing revision")
    result, route_identity = build_candidate(
        args.xls,
        shared,
        revised_plan,
        revision,
        args.yosys,
        args.stage / "implementation-cache",
        contracts=True,
    )
    if result["mapped_cost"]["dsp"] > 1:
        raise ValueError("revised shared candidate did not map to at most one DSP")
    write_json(state_path, {
        "schema": 1,
        "phase": "awaiting_shared_route",
        "local3": state["local3"],
        "local_characterization": revision,
        "shared3": result,
        "route_inputs": {
            "local3": state["route_inputs"]["local3"],
            "shared3": route_identity,
        },
    })


def finish(args: argparse.Namespace) -> None:
    """Consume the revised shared route and close the two-candidate policy decision."""
    state_path = args.stage / "state.json"
    state = json.loads(state_path.read_text())
    if state.get("phase") != "awaiting_shared_route":
        raise ValueError("feedback state is not awaiting the shared route")
    shared = args.stage / "shared3"
    _metrics, evidence = routed_evidence(
        "shared3", shared, args.route, state["route_inputs"]["shared3"]
    )
    decision = feedback(
        shared,
        "revise-shared",
        "revise",
        shared / "implementation-plan.etf",
        state["shared3"]["identities"]["implementation"],
        evidence,
        shared / "route-metrics.json",
        shared / "characterization.etf",
        shared / "policy-result.etf",
    )
    retained = (
        decision["action"] == "retain"
        and decision["plan"] == state["shared3"]["plan"]["plan"]
    )
    result = {
        "schema": 1,
        "passed": retained,
        "local3": state["local3"],
        "local_characterization": state["local_characterization"],
        "shared3": state["shared3"],
        "shared_characterization": decision,
        "claim": "Finite two-candidate semantic, mapped and native routed witness for exact planned implementations.",
        "limits": "No board execution, general optimum, frequency guarantee, route-seed sensitivity or sustained-workload claim.",
    }
    if not result["passed"]:
        raise ValueError("shared policy did not retain the exact characterized plan")
    write_json(args.stage / "result.json", result)
    write_json(state_path, {"schema": 1, "phase": "complete", "result_sha256": sha256_bytes(result)})


def route(args: argparse.Namespace) -> None:
    """Run the closed route recipe with a local Vivado executable; EC2 transfers remain external."""
    candidate = args.candidate.resolve()
    output = candidate / "route-output"
    run(
        [
            args.vivado,
            "-mode",
            "batch",
            "-source",
            candidate / "route-input" / ROUTE_SCRIPT.name,
            "-tclargs",
            candidate / "route-input",
            output,
        ],
        candidate,
        "vivado-route",
        timeout=None,
    )


def main() -> None:
    """Dispatch the resumable feedback phases without weakening exact plan/implementation correlation."""
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    first = commands.add_parser("baseline", help="prepare local candidate and route payload")
    first.add_argument("xls", type=lambda path: Path(path).resolve())
    first.add_argument("stage", type=lambda path: Path(path).resolve())
    first.add_argument("--yosys", type=lambda path: Path(path).resolve(), default=Path("yosys"))
    first.set_defaults(function=baseline)
    second = commands.add_parser("revise", help="consume local route and prepare its shared revision")
    second.add_argument("xls", type=lambda path: Path(path).resolve())
    second.add_argument("stage", type=lambda path: Path(path).resolve())
    second.add_argument("route", type=lambda path: Path(path).resolve())
    second.add_argument("--yosys", type=lambda path: Path(path).resolve(), default=Path("yosys"))
    second.set_defaults(function=revise)
    final = commands.add_parser("finish", help="consume shared route and close the policy decision")
    final.add_argument("stage", type=lambda path: Path(path).resolve())
    final.add_argument("route", type=lambda path: Path(path).resolve())
    final.set_defaults(function=finish)
    native = commands.add_parser("route", help="run the fixed recipe with a local Vivado")
    native.add_argument("candidate", type=Path)
    native.add_argument("--vivado", type=Path, default=Path("vivado"))
    native.set_defaults(function=route)
    args = parser.parse_args()
    args.function(args)


if __name__ == "__main__":
    main()
