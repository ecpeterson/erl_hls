"""Locate the public compiler sources and built Erlang applications for local tools."""
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]


def public_root() -> Path:
    """Find the explicit override, checkout, or rebar dependency; reject incomplete sources."""
    override = os.environ.get("ERL_HLS_ROOT")
    candidates = ([Path(override)] if override else [ROOT/"_checkouts/erl_hls",
        ROOT/"_build/default/lib/erl_hls", ROOT/"_build/test/lib/erl_hls"])
    for candidate in candidates:
        if (candidate/"tools/compile_xls.py").is_file():
            return candidate.resolve()
    raise FileNotFoundError("compile the erl_hls dependency first, or set ERL_HLS_ROOT to its source checkout")


def erlang_paths(root: Path = ROOT) -> list[Path]:
    """Prefer checkout beams over stale dependency beams, using the active test/default profile."""
    profile = "test" if (root / "_build/test/lib/hls_fabric/ebin").is_dir() else "default"
    base = root / "_build" / profile
    applications = {}
    for kind in ("lib", "checkouts"):
        for path in sorted((base / kind).glob("*/ebin")):
            applications[path.parent.name] = path
    tests = base / "lib/hls_fabric/test"
    return [*applications.values(), *([tests] if tests.is_dir() else [])]


PUBLIC = public_root()
sys.path.append(str(PUBLIC/"tools"))
# Child fixture generators need both applications even when launched by a small probe.
_paths = erlang_paths()
if _paths:
    os.environ["ERL_AFLAGS"] = os.environ.get("ERL_AFLAGS", "") + " -pa " + " ".join('"'+str(p)+'"' for p in _paths)
