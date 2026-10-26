#!/usr/bin/env python3
"""Build the decoder profile and its wrapper as one published artifact set."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import signal
import sys
from types import ModuleType

from backend_build_profile import read as read_build_profile

INPUTS = "phi_decoder_profile.inputs.json"
PROFILE = "phi_decoder_profile.json"
TOPOLOGY = "phi_decoder_profile_topology.x"
WRAPPER = "phi_decoder_profile_top.v"
BUILD_PROFILE = "phi_decoder_profile.build-profile.json"


def checked_inputs(snapshot: Path, *, assets: Path | None = None) -> dict:
    """Bind compiler-produced metadata to the immutable generated source and wrapper bytes.

    This is an integrity boundary for a trusted local Erlang build, not a second
    topology compiler or authentication of caller-supplied files. An explicit
    assets directory also supports checking a flat prepared experiment stage.
    """
    assets = snapshot / "assets" if assets is None else assets
    manifest = json.loads((assets / INPUTS).read_text())
    if not isinstance(manifest, dict):
        raise ValueError("profile input manifest must be an object")
    if type(manifest.get("version")) is not int or manifest["version"] != 1:
        raise ValueError("unsupported profile input manifest version")
    inputs = manifest.get("inputs")
    if not isinstance(inputs, dict) or not {TOPOLOGY, WRAPPER, PROFILE, BUILD_PROFILE} <= inputs.keys():
        raise ValueError("profile input manifest omits required generated files")
    for name, expected in inputs.items():
        if Path(name).name != name or not (name.endswith(".x") or name in (WRAPPER, PROFILE, BUILD_PROFILE)):
            raise ValueError(f"invalid profile input name: {name!r}")
        path = snapshot / name if name.endswith(".x") else assets / name
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError(f"generated profile input changed: {name}")
    if not isinstance(manifest.get("ram_configurations"), str) or not manifest["ram_configurations"]:
        raise ValueError("profile input manifest omits RAM configurations")
    recipe = manifest.get("ram_configuration")
    if not isinstance(recipe, str) or len(recipe) != 64 or any(c not in "0123456789abcdef" for c in recipe):
        raise ValueError("profile input manifest omits a valid RAM recipe identity")
    return manifest


def selected_compiler(profile: str, public: Path | None) -> ModuleType:
    """Use an explicit compiler or this detached driver's retained standalone helper.

    Checkout invocation resolves only the requested rebar profile. A detached
    stage needs compile_xls.py beside this script, with no repository or rebar.
    """
    retained = Path(__file__).resolve().with_name("compile_xls.py")
    if public is None and retained.is_file():
        name = "_retained_compile_xls_" + hashlib.sha256(str(retained).encode()).hexdigest()
        if name not in sys.modules:
            spec = importlib.util.spec_from_file_location(name, retained)
            if spec is None or spec.loader is None:
                raise ImportError(f"cannot load retained compiler: {retained}")
            module = importlib.util.module_from_spec(spec)
            sys.modules[name] = module
            try:
                spec.loader.exec_module(module)
            except BaseException:
                del sys.modules[name]
                raise
        return sys.modules[name]
    from compiler_paths import compiler_root, compiler_tool
    return compiler_tool(compiler_root(profile, public), "compile_xls")


def main() -> None:
    """Compile checked geometry using an Erlang-emitted, frozen scheduling policy.

    The default policy is bound by the producer input manifest. Local callers may
    select a separately emitted policy; the detached adapter never resolves
    schedule defaults or rewrites its literal flags.
    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--erl-hls", type=Path)
    parser.add_argument("--profile", default="test")
    parser.add_argument("stage", type=Path)
    parser.add_argument("xls_root", type=Path)
    parser.add_argument("--timeout", default="7200")
    parser.add_argument("--build-profile", type=Path, help="Emitted policy; defaults to the producer-bound sidecar.")
    parser.add_argument("--delay-table", type=Path)
    args = parser.parse_args()
    compiler = selected_compiler(args.profile, args.erl_hls)
    try:
        timeout = compiler.duration(args.timeout)
    except argparse.ArgumentTypeError as error:
        parser.error(str(error))
    signal.signal(signal.SIGTERM, compiler.interrupted)
    stage = args.stage.resolve()

    selected = (args.build_profile or stage / BUILD_PROFILE).resolve()
    expected_policy = hashlib.sha256(selected.read_bytes()).hexdigest()
    assets = [stage / name for name in (WRAPPER, "hls_1r1w_ram.v", PROFILE, INPUTS, BUILD_PROFILE)]
    collisions = [path for path in assets if path.name == selected.name]
    if collisions and collisions[0].resolve() != selected:
        raise ValueError("selected build profile collides with a bound profile asset")
    if not collisions:
        assets.append(selected)

    def policy(snapshot: Path) -> dict:
        """Read only selected policy bytes frozen before executor snapshotting."""
        path = snapshot / "assets" / selected.name
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected_policy:
            raise ValueError("selected build profile changed during snapshot")
        value = read_build_profile(path)
        if value["profile"]["postprocess"]["completion_storage"] != "registers":
            raise ValueError("Phi profile compilation does not support completion legalization")
        return value

    def metadata(snapshot: Path) -> dict:
        """Keep application geometry distinct from the retained hardware policy."""
        inputs = checked_inputs(snapshot)
        config = json.loads((snapshot / "assets" / PROFILE).read_text())
        return {"profile": config, "build_profile": policy(snapshot),
                "ram_configuration": inputs["ram_configuration"]}

    def ram_configurations(snapshot: Path) -> str:
        """Pass through RAM bindings emitted from the same checked scheduler plan."""
        return checked_inputs(snapshot)["ram_configurations"]

    compiler.build(stage / TOPOLOGY, args.xls_root, stage / "compiled",
          name="phi_decoder_profile", codegen_flags=lambda snapshot: policy(snapshot)["codegen_flags"],
          ram_configurations=ram_configurations, assets=assets, metadata=metadata,
          timeout=timeout, delay_table=args.delay_table)


if __name__ == "__main__":
    main()
