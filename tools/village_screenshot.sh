#!/usr/bin/env bash
# Render a village (default harmonia) at dawn/noon/night into tmp/screens/. Needs xvfb-run + a GL driver.
set -euo pipefail
cd "$(dirname "$0")/.."
V="${1:-harmonia}"
command -v xvfb-run >/dev/null || { echo "xvfb-run missing — launch the game instead and take a cap (F12)"; exit 3; }
mkdir -p tmp/screens
for P in 0.07 0.30 0.65; do
  xvfb-run -a godot --audio-driver Dummy --rendering-driver opengl3 --resolution 1280x720 \
    -s tools/village_screenshot.gd -- "--village=$V" "--phase=$P" 2>&1 | command grep -a -E "SCREEN|ERROR" || true
done
ls -la tmp/screens/
