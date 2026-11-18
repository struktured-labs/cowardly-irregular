#!/usr/bin/env bash
# Sandboxed runner for tools/uifont_shots.gd — see tools/shot_sandbox.sh for why this file exists.
# Face by environment: COWIR_UIFONT=off (old face) · COWIR_UIFONT_READ=pixel|default (the read tier).
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=tools/shot_sandbox.sh
. tools/shot_sandbox.sh
shot_sandbox_run tools/uifont_shots.gd "$@"
