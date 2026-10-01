#!/usr/bin/env python3
"""Build or test the backend with its pinned compiler; default to compilation."""
import subprocess
import sys
from prepare_compiler import ROOT, prepare

if __name__ == "__main__":
    prepare()
    raise SystemExit(subprocess.call(["rebar3", *(sys.argv[1:] or ["compile"])], cwd=ROOT))
