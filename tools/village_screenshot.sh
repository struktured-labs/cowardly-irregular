#!/usr/bin/env bash
# Render a village (default harmonia) at dawn/noon/night into tmp/screens/. Needs xvfb-run + a GL driver.
set -euo pipefail
cd "$(dirname "$0")/.."
V="${1:-harmonia}"
command -v xvfb-run >/dev/null || { echo "xvfb-run missing — launch the game instead and take a cap (F12)"; exit 3; }
mkdir -p tmp/screens
# ⛔ SANDBOXED user://. These scripts run the GAME, not a headless export, so godot resolves
# user:// by APPLICATION NAME and lands in ~/.local/share/godot/app_userdata/Cowardly Irregular
# -- struktured's LIVE save directory -- no matter which worktree you run from. Measured
# 2026-09-12: one sandboxed run created app_userdata/Cowardly Irregular/{logs,shader_cache},
# so unsandboxed it writes there. The fleet rule after the 2026-08-22 incident is that every
# godot invocation sets XDG_DATA_HOME inside its own worktree.
#
# Unlike the deploy chain's --export-release (deploy_web.sh:127), relocating the data root is
# SAFE here: these run the project and need no export_templates, which is the only thing that
# breaks when XDG_DATA_HOME moves.
_SHOT_XDG="$PWD/tmp/shot_xdg"; mkdir -p "$_SHOT_XDG"
for P in 0.07 0.30 0.65; do
  XDG_DATA_HOME="$_SHOT_XDG" xvfb-run -a godot --audio-driver Dummy --rendering-driver opengl3 --resolution 1280x720 \
    -s tools/village_screenshot.gd -- "--village=$V" "--phase=$P" 2>&1 | command grep -a -E "SCREEN|ERROR" || true
done
ls -la tmp/screens/
