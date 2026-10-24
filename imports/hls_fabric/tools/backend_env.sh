#!/usr/bin/env bash
# Source after compilation: source tools/backend_env.sh default|test.
backend_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
backend_profile=${1:?source backend_env.sh with the compiled rebar profile}
backend_erl_flags=$(python3 - "$backend_root" "$backend_profile" <<'PYPATHS'
import sys
sys.path.insert(0, sys.argv[1] + "/tools")
from backend_paths import erlang_environment
print(erlang_environment(sys.argv[2])["ERL_AFLAGS"])
PYPATHS
) || return
erl_hls_root=$(python3 - "$backend_root" <<'PYROOT'
import sys
sys.path.insert(0, sys.argv[1] + "/tools")
from compiler_paths import PUBLIC
print(PUBLIC)
PYROOT
) || return
export ERL_HLS_ROOT="$erl_hls_root"
export PYTHONPATH="$backend_root/tools:$erl_hls_root/tools${PYTHONPATH:+:$PYTHONPATH}"
export ERL_AFLAGS="$backend_erl_flags"
