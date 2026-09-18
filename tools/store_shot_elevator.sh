#!/usr/bin/env bash
# Sandboxed runner for tools/store_shot_elevator.gd — see tools/shot_sandbox.sh for why this file exists.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=tools/shot_sandbox.sh
. tools/shot_sandbox.sh
shot_sandbox_run tools/store_shot_elevator.gd "$@"
