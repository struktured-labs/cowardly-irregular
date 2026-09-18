#!/usr/bin/env bash
# Render an overworld at a world position and report where the player stops walking north.
# Usage: tools/overworld_screenshot.sh [world] [x,y] [tag]
set -euo pipefail
cd "$(dirname "$0")/.."
W="${1:-medieval}"; AT="${2:-}"; TAG="${3:-edge}"; ZOOM="${4:-}"
command -v xvfb-run >/dev/null || { echo "xvfb-run missing"; exit 3; }
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
# ⛔ THE EXIT CODE USED TO BE DISCARDED TWICE HERE: `$?` after a pipeline is the LAST
# stage's status (grep succeeds whenever it matches), and `|| true` swallowed what was
# left. So godot could fail to load the scene, render an empty node, and this returned 0.
# Log first, read the log second, decide on the captured code.
_LOG="tmp/screens/overworld_${W}_${TAG}.log"
_EC=0
XDG_DATA_HOME="$_SHOT_XDG" xvfb-run -a godot --audio-driver Dummy --rendering-driver opengl3 --resolution 1280x720 \
  -s tools/overworld_screenshot.gd -- "--world=$W" ${AT:+--at=$AT} "--tag=$TAG" ${ZOOM:+--zoom=$ZOOM} \
  > "$_LOG" 2>&1 || _EC=$?
command grep -a -E "SHOT|ERROR|SCRIPT ERROR|shot-guard" "$_LOG" || true
if [ "$_EC" -ne 0 ]; then
  echo "[shot] BLOCKED: overworld $W/$TAG exited $_EC — see $_LOG. A frame that depicts nothing" >&2
  echo "       is refused by tools/shot_guard.gd rather than written; these feed the store page." >&2
  exit 4
fi
