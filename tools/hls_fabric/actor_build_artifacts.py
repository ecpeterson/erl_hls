"""Fingerprint actor fixture builds without loading compiler or simulation drivers."""
import argparse
import json
from pathlib import Path
import shutil

from backend_commands import digest
from backend_paths import ROOT
from compiler_paths import compiler_source_root, compiler_tools_root


def inputs(args: argparse.Namespace) -> dict:
    """Hash compiler, fixture and tool inputs used to validate reuse of the actor RTL build."""
    private = [ROOT / path for path in (
        "apps/hls_fabric/test/hls_actor_pid_fixture.erl", "apps/hls_fabric/test/hls_actor_pid_dslx.erl",
        "apps/hls_fabric/test/rtl/actor_device_tb.sv", "tools/hls_fabric/test_actor_rtl.py", "tools/hls_fabric/actor_build_artifacts.py", "tools/hls_fabric/backend_commands.py",
        "tools/hls_fabric/backend_paths.py", "tools/hls_fabric/compiler_paths.py", "tools/hls_fabric/scheduler_ram_configurations.sh", "rebar.config", "rebar.lock")]
    private += list((ROOT / "apps/hls_fabric/src").rglob("*.erl"))
    private += list((ROOT / "apps/hls_lowering/src").rglob("*.erl"))
    private += list((ROOT / "apps/hls_lowering/priv/xls").rglob("*.x"))
    private += list((ROOT / "apps/hls_fabric/test/xls").rglob("*.x"))
    source_root = compiler_source_root(args.erl_hls)
    public = [source_root / path for path in (
        "priv/rtl/hls_1r1w_ram.v",
        "test/rtl/xls_sim_bridge.c", "test/rtl/xls_sim_axis.h")]
    for pattern in ("src/**/*.erl", "apps/*/src/**/*.erl", "include/**/*.hrl", "priv/xls/**/*.x",
                    "priv/rtl/debug/*.v"):
        public += list(source_root.glob(pattern))
    tools_root = compiler_tools_root(source_root)
    public += list((tools_root / "tools/erl_hls_tools").glob("*.py"))
    files = {"private/" + str(path.relative_to(ROOT)): digest(path) for path in private}
    for path in public:
        try:
            relative = path.relative_to(source_root)
        except ValueError:
            relative = path.relative_to(tools_root)
        files["public/" + str(relative)] = digest(path)
    tools = {name: digest(args.xls / name) for name in ("ir_converter_main", "opt_main", "codegen_main")}
    for path in (args.xls / "xls/dslx/stdlib").rglob("*.x"):
        files["stdlib/" + str(path.relative_to(args.xls / "xls/dslx/stdlib"))] = digest(path)
    for name, executable in (("yosys", args.yosys), ("iverilog", "iverilog"), ("iverilog-vpi", "iverilog-vpi")):
        path = Path(shutil.which(executable) or executable).resolve()
        tools[name] = {"path": str(path), "sha256": digest(path)}
    return {"files": files, "tools": tools}


def outputs(stage: Path) -> dict[str, str]:
    """Hash the required actor executable, instrumentation and emitted source files."""
    paths = [path for directory in ("source", "debug") for path in (stage / directory).iterdir()
             if path.suffix in (".x", ".v", ".json", ".ir")]
    paths += [stage / "actor.vvp", stage / "xls_sim_bridge.vpi"]
    return {str(path.relative_to(stage)): digest(path) for path in sorted(paths)}


def validate_build(args: argparse.Namespace) -> None:
    """Reject reuse when build inputs or required emitted artifacts have changed."""
    saved = json.loads((args.stage / "provenance.json").read_text())
    if saved["inputs"] != inputs(args):
        raise ValueError("RTL build inputs changed; use a fresh --stage without --reuse-build")
    if saved["outputs"] != outputs(args.stage):
        raise ValueError("generated RTL or instrumentation changed; rebuild before simulation")
