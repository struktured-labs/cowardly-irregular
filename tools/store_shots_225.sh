#!/usr/bin/env bash
# Sandboxed runner for tools/store_shots_225.gd — see tools/shot_sandbox.sh for why this file exists.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=tools/shot_sandbox.sh
. tools/shot_sandbox.sh
shot_sandbox_run tools/store_shots_225.gd "$@"
