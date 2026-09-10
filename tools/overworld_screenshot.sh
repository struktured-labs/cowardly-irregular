#!/usr/bin/env bash
# Render an overworld at a world position and report where the player stops walking north.
# Usage: tools/overworld_screenshot.sh [world] [x,y] [tag]
set -euo pipefail
cd "$(dirname "$0")/.."
W="${1:-medieval}"; AT="${2:-2880,1280}"; TAG="${3:-edge}"
command -v xvfb-run >/dev/null || { echo "xvfb-run missing"; exit 3; }
mkdir -p tmp/screens
xvfb-run -a godot --audio-driver Dummy --rendering-driver opengl3 --resolution 1280x720 \
  -s tools/overworld_screenshot.gd -- "--world=$W" "--at=$AT" "--tag=$TAG" 2>&1 \
  | command grep -a -E "SHOT|ERROR|SCRIPT ERROR" || true
