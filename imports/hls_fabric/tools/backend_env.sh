#!/usr/bin/env bash
# Source after rebar compilation to make both applications available to fixture tools.
backend_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
erl_hls_root=$(python3 - "$backend_root" <<'PYROOT'
import sys
sys.path.insert(0, sys.argv[1] + "/tools")
from backend_paths import PUBLIC
print(PUBLIC)
PYROOT
)
export ERL_HLS_ROOT="$erl_hls_root"
export PYTHONPATH="$backend_root/tools:$erl_hls_root/tools${PYTHONPATH:+:$PYTHONPATH}"
backend_erl_paths=$(python3 - "$backend_root" <<'PYPATHS'
import sys
sys.path.insert(0, sys.argv[1] + "/tools")
from backend_paths import erlang_paths
print(" ".join('"'+str(p)+'"' for p in erlang_paths()))
PYPATHS
)
export ERL_AFLAGS="${ERL_AFLAGS:-} -pa $backend_erl_paths"
