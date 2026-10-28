"""Validate retained Phi bridge and mesh artifacts without invoking build tools."""
import phi_tool_paths  # Resolve shared tooling for this application.
import json
from pathlib import Path

from backend_commands import digest


def bridge_outputs(stage: Path, *, devices_only: bool = False) -> dict:
    """Hash generated devices; require the bridge adapter unless the build explicitly omits it."""
    paths = [path for directory in ("source", "device0", "device1")
             for path in (stage / directory).rglob("*")
             if path.is_file() and path.suffix in (".x", ".v", ".vh", ".json", ".ir", ".term")]
    paths += [stage / "phi_devices.vh", *stage.glob("*.vpi")]
    if not devices_only:
        paths.append(stage / "phi_bridge.vvp")
    return {str(path.relative_to(stage)): digest(path) for path in sorted(paths)}


def read_bridge_build(stage: Path) -> dict:
    """Return the build record only when all selected device/harness artifact hashes still match."""
    saved = json.loads((stage / "provenance.json").read_text())
    devices_only = saved["inputs"]["config"].get("devices_only", False)
    if saved["outputs"] != bridge_outputs(stage, devices_only=devices_only):
        raise ValueError("generated RTL or instrumentation changed; rebuild before simulation")
    return saved


def mesh_artifacts(directory: Path) -> dict:
    """Hash retained RTL, source, manifests and compiler output for resumable builds."""
    return {str(p.relative_to(directory)): digest(p) for p in sorted(directory.rglob("*"))
            if p.is_file() and p.suffix in (".x", ".v", ".ir", ".json", ".term", ".gz")
            and p.name != "complete.json"}
