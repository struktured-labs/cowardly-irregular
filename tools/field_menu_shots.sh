#!/usr/bin/env bash
# Sandboxed runner for tools/field_menu_shots.gd — see tools/shot_sandbox.sh for why this file exists.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=tools/shot_sandbox.sh
. tools/shot_sandbox.sh
shot_sandbox_run tools/field_menu_shots.gd "$@"
