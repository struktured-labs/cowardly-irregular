#!/usr/bin/env bash
# Thin wrapper — the implementation and all gates live in deploy_desktop.sh.
# Kept as a separate entry point because "tools/deploy_linux.sh --publish v…"
# is the documented command and muscle memory; do not put logic here.
exec env PLAT=linux "$(dirname "$0")/deploy_desktop.sh" "$@"
