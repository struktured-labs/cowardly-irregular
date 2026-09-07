#!/usr/bin/env bash
# Render every floor of the five W2-W6 dungeons into tmp/screens/. Needs xvfb-run + a GL driver.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xvfb-run >/dev/null || { echo "xvfb-run missing — launch the game instead and take a cap (F12)"; exit 3; }
mkdir -p tmp/screens

render() {
  local script="$1" floor="$2" x="$3" y="$4"
  xvfb-run -a godot --audio-driver Dummy --rendering-driver opengl3 --resolution 1280x720 \
    -s tools/later_world_dungeon_screenshot.gd -- "--script=$script" "--floor=$floor" "--x=$x" "--y=$y" \
    2>&1 | command grep -a -E "SCREEN|ERROR" || true
}

render res://src/maps/dungeons/SuburbanUnderground.gd 1 10 7
render res://src/maps/dungeons/SuburbanUnderground.gd 2 10 7
render res://src/maps/dungeons/SuburbanUnderground.gd 3 9 8
render res://src/maps/dungeons/SuburbanUnderground.gd 4 10 7

render res://src/maps/dungeons/SteampunkMechanism.gd 1 10 7
render res://src/maps/dungeons/SteampunkMechanism.gd 2 9 7
render res://src/maps/dungeons/SteampunkMechanism.gd 3 10 7
render res://src/maps/dungeons/SteampunkMechanism.gd 4 10 7

render res://src/maps/dungeons/AssemblyCore.gd 1 10 7
render res://src/maps/dungeons/AssemblyCore.gd 2 9 8
render res://src/maps/dungeons/AssemblyCore.gd 3 10 7
render res://src/maps/dungeons/AssemblyCore.gd 4 10 7

render res://src/maps/dungeons/RootProcess.gd 1 10 7
render res://src/maps/dungeons/RootProcess.gd 2 10 7
render res://src/maps/dungeons/RootProcess.gd 3 9 8
render res://src/maps/dungeons/RootProcess.gd 4 10 7

render res://src/maps/dungeons/NullChamber.gd 1 10 7
render res://src/maps/dungeons/NullChamber.gd 2 9 8
render res://src/maps/dungeons/NullChamber.gd 3 10 7

ls -la tmp/screens/
