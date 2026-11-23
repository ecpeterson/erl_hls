#!/usr/bin/env bash
# Retain the shell entry point used by prepared local and remote profile stages.
set -euo pipefail
exec python3 "$(dirname "${BASH_SOURCE[0]}")/compile_phi_decoder_profile.py" "$@"
