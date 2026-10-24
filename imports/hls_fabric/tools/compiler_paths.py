"""Expose the selected compiler's unpackaged Python tools to legacy tool imports.

Keep this bootstrap separate from Erlang build paths and command execution;
file-only report tools must not need a compiler checkout just to import helpers.
"""
import os
from pathlib import Path
import sys
from backend_paths import ROOT


def public_root() -> Path:
    """Find the explicit override, checkout, or rebar dependency; reject incomplete sources."""
    override = os.environ.get("ERL_HLS_ROOT")
    candidates = ([Path(override)] if override else [ROOT/"_checkouts/erl_hls",
        ROOT/"_build/default/lib/erl_hls", ROOT/"_build/test/lib/erl_hls"])
    for candidate in candidates:
        if (candidate/"tools/compile_xls.py").is_file():
            return candidate.resolve()
    raise FileNotFoundError("compile the erl_hls dependency first, or set ERL_HLS_ROOT to its source checkout")


PUBLIC = public_root()
sys.path.append(str(PUBLIC / "tools"))
