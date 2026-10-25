"""Fingerprint actor fixture builds without loading compiler or simulation drivers."""
import argparse
import json
from pathlib import Path
import shutil

from backend_commands import digest
from backend_paths import ROOT


def inputs(args: argparse.Namespace) -> dict:
    """Hash compiler, fixture and tool inputs used to validate reuse of the actor RTL build."""
    private = [ROOT / path for path in (
        "test/hls_actor_pid_fixture.erl", "test/hls_actor_pid_dslx.erl",
        "test/rtl/actor_device_tb.sv", "tools/test_actor_rtl.py", "tools/actor_build_artifacts.py", "tools/backend_commands.py",
        "tools/backend_paths.py", "tools/compiler_paths.py", "tools/phi_scheduler_rams.sh", "rebar.config", "rebar.lock")]
    private += list((ROOT / "src").rglob("*.erl"))
    private += list((ROOT / "priv/xls").rglob("*.x"))
    private += list((ROOT / "test/xls").rglob("*.x"))
    public = [args.erl_hls / path for path in (
        "priv/rtl/hls_1r1w_ram.v",
        "test/rtl/xls_sim_bridge.c", "test/rtl/xls_sim_axis.h")]
    for pattern in ("src/**/*.erl", "include/**/*.hrl", "priv/xls/**/*.x",
                    "priv/rtl/debug/*.v", "tools/erl_hls_tools/*.py"):
        public += list(args.erl_hls.glob(pattern))
    files = {"private/" + str(path.relative_to(ROOT)): digest(path) for path in private}
    files.update({"public/" + str(path.relative_to(args.erl_hls)): digest(path) for path in public})
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
