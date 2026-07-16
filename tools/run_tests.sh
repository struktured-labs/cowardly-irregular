#!/usr/bin/env bash
# run_tests.sh — THE canonical GUT invocation. Always mutes audio and logs
# to tmp/ so test runs never rotate the game's user://logs/godot.log away
# (the 2026-07-15 mage-cutscene crash lost its trace exactly that way).
#
# Usage:
#   tools/run_tests.sh                 # full unit suite
#   tools/run_tests.sh <name>          # single file: test_<name>.gd or a res:// path
#   tools/run_tests.sh --isolated      # the quarantined suite (own process by design)
set -uo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p tmp

BASE=(godot --headless --audio-driver Dummy --log-file tmp/gut_manual_godot.log -s addons/gut/gut_cmdln.gd -gprefix=test_ -gsuffix=.gd -gexit)

case "${1:-}" in
  "")          exec "${BASE[@]}" -gdir=res://test/unit ;;
  --isolated)  exec "${BASE[@]}" -gdir=res://test/isolated ;;
  res://*)     exec "${BASE[@]}" -gtest="$1" ;;
  *)           exec "${BASE[@]}" -gtest="res://test/unit/test_${1#test_}" ;;
esac
