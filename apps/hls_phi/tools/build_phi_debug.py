#!/usr/bin/env python3
"""Build matched production and fully instrumented D3 phi-memory applications.

Uses native XLS plus Yosys. Each directory retains DSLX, IR, RTL, source hashes,
commands and logs; debug/ contains the deployable shared-transport wrapper.
"""
import phi_tool_paths  # Resolve shared tooling for this application.
from compiler_paths import compiler_root, compiler_tool
from backend_build_profile import emit as emit_build_profile, read as read_build_profile
from backend_paths import erl_command, erlang_environment
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[3]


def compile_dslx(xls: Path, stage: Path, module: str, top: str, stages: int,
                 ii: int = 1, rams: str | None = None, build_profile: Path | None = None) -> None:
    """Compile a staged unit; application RAM builds consume emitted policy, debug peripherals keep their explicit clock recipe."""
    policy = read_build_profile(build_profile) if build_profile is not None else None
    if rams and policy is None:
        raise ValueError("application compilation requires an emitted build profile")
    if policy is not None and policy["profile"]["postprocess"]["completion_storage"] != "registers":
        raise ValueError("debug build does not implement completion-storage legalization")
    flags = policy["codegen_flags"] if policy is not None else [
        f"--pipeline_stages={stages}", f"--worst_case_throughput={ii}",
        "--delay_model=unit", "--use_system_verilog=false", "--reset=reset", "--fifo_module="]
    commands = [
        (".ir", [str(xls / "ir_converter_main"), "--warnings_as_errors=false", "--dslx_path=.",
                 f"--dslx_stdlib_path={xls / 'xls/dslx/stdlib'}", f"--top={top}", f"{module}.x"]),
        (".opt.ir", [str(xls / "opt_main"), f"{module}.ir"]),
        (".v", [str(xls / "codegen_main"), *flags,
                *([f"--ram_configurations={rams}"] if rams else []),
                f"{module}.opt.ir"])]
    for suffix, command in commands:
        with (stage / f"{module}{suffix}").open("w") as output, (stage / f"{module}{suffix}.log").open("w") as log:
            subprocess.run(command, cwd=stage, stdout=output, stderr=log, check=True)
    (stage / f"{module}.build.json").write_text(json.dumps({
        "build_profile": policy,
        "assets": {build_profile.name: hashlib.sha256(build_profile.read_bytes()).hexdigest()} if build_profile else {},
        "commands": commands, "tools": {name: hashlib.sha256((xls / name).read_bytes()).hexdigest()
            for name in ("ir_converter_main", "opt_main", "codegen_main")},
        "sources": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in stage.glob("*.x")},
        "stdlib": {str(p.relative_to(xls)): hashlib.sha256(p.read_bytes()).hexdigest()
                   for p in (xls / "xls/dslx/stdlib").rglob("*.x")},
        "outputs": {f"{module}{suffix}": hashlib.sha256((stage / f"{module}{suffix}").read_bytes()).hexdigest()
                    for suffix, _ in commands}
    }, indent=2) + "\n")


def validate(build: Path) -> None:
    """Reject stale compiler outputs or a manifest detached from its source RTL."""
    for directory, modules in (("production", ["phi_memory_gateway"]), ("observed", ["phi_memory_gateway"]),
                               ("support", ["hls_fabric_router", "hls_debug_observer", "hls_debug_server"])):
        stage = build / directory
        for module in modules:
            metadata = json.loads((stage / f"{module}.build.json").read_text())
            for name, expected in (metadata["sources"] | metadata["outputs"] | metadata.get("assets", {})).items():
                if hashlib.sha256((stage / name).read_bytes()).hexdigest() != expected:
                    raise ValueError(f"stale build input/output: {stage / name}")
    manifest = json.loads((build / "debug/manifest.json").read_text())
    candidates = {p.name: p for directory in ("observed", "support") for p in (build / directory).glob("*.v")}
    for source in manifest["sources"]:
        path = candidates[source["name"]]
        if hashlib.sha256(path.read_bytes()).hexdigest() != source["sha256"]:
            raise ValueError(f"manifest source mismatch: {path}")
    fingerprint = manifest.pop("fingerprint")
    canonical = json.dumps(manifest, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()
    if hashlib.sha256(canonical).hexdigest() != fingerprint:
        raise ValueError("manifest fingerprint mismatch")


def build(args: argparse.Namespace) -> None:
    """Compile the test profile and emit matched production and observed Phi devices."""
    stage, xls = args.stage.resolve(), args.xls.resolve()
    subprocess.run(["rebar3", "as", "test", "compile"], cwd=ROOT, check=True)
    public = compiler_root("test", getattr(args, "erl_hls", None))
    topology = compiler_tool(public, "topology_debug")
    for mode in ("production", "observed"):
        out = stage / mode
        out.mkdir(parents=True, exist_ok=True)
        expression = ('[Dir, Flag, Shards] = init:get_plain_arguments(), '
                      'ok = hls_phi_debug_dslx:write(Dir, Flag =:= "true", list_to_integer(Shards)), halt().')
        subprocess.run(erl_command(public, expression, out, str(mode == "observed").lower(),
                                  str(args.shards), profile="test"), cwd=ROOT,
                       env=erlang_environment("test", compiler=public), check=True)
        for source in [*public.glob("priv/xls/lib/*.x"), *ROOT.glob("apps/hls_lowering/priv/xls/lib/*.x"), *public.glob("priv/xls/fabric/*.x"),
                       ROOT / "apps/hls_phi/src/phi_field.x", public / "priv/rtl/hls_1r1w_ram.v"]:
            shutil.copy(source, out)
        banks = len(json.loads((out / "actors.json").read_text())["banks"])
        rams = subprocess.check_output(["bash", "-c", 'source tools/hls_fabric/scheduler_ram_configurations.sh; scheduler_ram_configurations "$1"',
                                        "phi-ram-config", str(banks)], cwd=ROOT, text=True).strip()
        print(f"Building {mode}: {banks} scheduler banks", flush=True)
        policy = out / "build-profile.json"
        emit_build_profile(policy, profile="test", public=public)
        compile_dslx(xls, out, "phi_memory_gateway", "Top", 2, rams=rams, build_profile=policy)
    (stage / "fixture.json").write_text(json.dumps({"shards": args.shards}) + "\n")
    support = stage / "support"
    support.mkdir(exist_ok=True)
    for source in [*public.glob("priv/xls/debug/*.x"), *public.glob("priv/xls/fabric/*.x"), *public.glob("priv/xls/lib/*.x"), *ROOT.glob("apps/hls_lowering/priv/xls/lib/*.x")]:
        shutil.copy(source, support)
    for module, top, stages, ii in (("hls_fabric_router", "HostRoutedTx", 1, 1),
                                    ("hls_debug_observer", "Observer", 2, 1),
                                    ("hls_debug_server", "DebugServer", 3, 2)):
        compile_dslx(xls, support, module, top, stages, ii)
    out = stage / "observed"
    topology.instrument(argparse.Namespace(
        rtl=[out / "phi_memory_top.v", out / "phi_memory_gateway.v", out / "hls_1r1w_ram.v",
             support / "hls_fabric_router.v"], top="phi_memory_top", clock="aclk", reset="aresetn",
        reset_active_low=True, output_top="hls_instrumented_application", stage=stage / "debug",
        yosys=args.yosys, actor_projection=out / "actors.json", actor_root="",
        monitor_rx="s_axis", monitor_tx="m_axis", monitor_routed=True))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--erl-hls", type=Path, help="Compiler source with matching test-profile beams.")
    parser.add_argument("xls", type=Path)
    parser.add_argument("--stage", type=Path, default=Path("_build/phi-debug"))
    parser.add_argument("--yosys", default="yosys")
    parser.add_argument("--shards", type=int, choices=range(1, 10), default=1,
                        help="executors per phi plane; the standard D3 deployment uses one")
    build(parser.parse_args())
