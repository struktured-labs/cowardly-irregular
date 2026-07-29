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

# GUT exits 0 when -gtest names a file that does not exist: a vacuous green no
# exit code can tell from a real pass. Exit 2 so it can't be read as "passed".
require_test_file() {
  [ -f "$1" ] && return 0
  echo "run_tests.sh: no such test file: $1" >&2
  echo "  (nothing would have run, and GUT would have exited 0 — refusing to report a vacuous pass)" >&2
  exit 2
}

case "${1:-}" in
  "")          exec "${BASE[@]}" -gdir=res://test/unit ;;
  --isolated)  exec "${BASE[@]}" -gdir=res://test/isolated ;;
  res://*)     require_test_file "${1#res://}"; exec "${BASE[@]}" -gtest="$1" ;;
  *)           N="${1#test_}"; N="${N%.gd}"; require_test_file "test/unit/test_${N}.gd"; exec "${BASE[@]}" -gtest="res://test/unit/test_${N}.gd" ;;
esac
