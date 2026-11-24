"""Expose shared checkout tooling; detached stages use only their retained sibling helpers."""
from pathlib import Path
import sys

TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parents[2] if TOOLS.parts[-3:] == ("workloads", "hls_phi", "tools") else None
if ROOT is not None and str(ROOT / "tools/hls_fabric") not in sys.path:
    sys.path.insert(0, str(ROOT / "tools/hls_fabric"))
