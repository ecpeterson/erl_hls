#!/usr/bin/env bash
# Source after compilation: source tools/hls_fabric/backend_env.sh PROFILE [COMPILER_ROOT].
backend_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
backend_profile=${1:?source backend_env.sh with the compiled rebar profile}
# Resolve sources and beams together. Only this explicit shell operation exports
# context; Python imports never mutate the caller's environment or import paths.
backend_exports=$(PYTHONPATH="$backend_root/tools/hls_fabric" python3 - "$backend_root" "$backend_profile" "${2:-}" <<'PYCONTEXT'
from pathlib import Path
import shlex
import sys
from backend_paths import erlang_environment
from compiler_paths import compiler_application, compiler_root
root, profile, override = sys.argv[1:]
public = compiler_root(profile, Path(override) if override else None, Path(root))
values = {"ERL_HLS_ROOT": str(public),
          "ERL_HLS_COMPILE_ROOT": str(compiler_application(public, "hls_compile")),
          "ERL_HLS_FABRIC_ROOT": str(compiler_application(public, "hls_fabric")),
          "ERL_HLS_TARGET_ROOT": str(compiler_application(public, "hls_target")),
          "PYTHONPATH": str(Path(root) / "tools/hls_fabric"),
          "ERL_AFLAGS": erlang_environment(profile, Path(root), compiler=public)["ERL_AFLAGS"]}
for name, value in values.items():
    print("export " + name + "=" + shlex.quote(value))
PYCONTEXT
) || return
eval "$backend_exports"
erl_hls_root=$ERL_HLS_ROOT
hls_compile_root=$ERL_HLS_COMPILE_ROOT
hls_fabric_root=$ERL_HLS_FABRIC_ROOT
hls_target_root=$ERL_HLS_TARGET_ROOT
