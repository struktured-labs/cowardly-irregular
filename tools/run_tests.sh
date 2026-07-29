#!/usr/bin/env bash
# run_tests.sh — THE canonical GUT invocation. Always mutes audio and logs
# to tmp/ so test runs never rotate the game's user://logs/godot.log away
# (the 2026-07-15 mage-cutscene crash lost its trace exactly that way).
#
# Usage:
#   tools/run_tests.sh                 # full unit suite
#   tools/run_tests.sh <name>          # single file: test_<name>.gd or a res:// path
#   tools/run_tests.sh --isolated      # the quarantined suite (own process by design)
#
# Exit codes:  0 pass · 1 test failures · 2 bad invocation · 3 nothing ran
set -uo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p tmp

BASE=(godot --headless --audio-driver Dummy --log-file tmp/gut_manual_godot.log -s addons/gut/gut_cmdln.gd -gprefix=test_ -gsuffix=.gd -gexit)

require_test_file() {
  [ -f "$1" ] && return 0
  echo "run_tests.sh: no such test file: $1" >&2
  exit 2
}

require_test_dir() {
  for f in "$1"/test_*.gd; do
    [ -e "$f" ] && return 0
    break
  done
  echo "run_tests.sh: no test_*.gd files in $1" >&2
  exit 2
}

# GUT exits 0 when it runs NOTHING, and the causes are open-ended: absent file,
# empty dir, unimported worktree (res:// unresolvable while the file is on
# disk), a parse error that drops the script. Enumerating them is a losing game
# — three were found in one evening — so assert the OUTCOME instead: a real run
# always prints a Totals block, and a vacuous one never does.
run_gut() {
  "${BASE[@]}" "$@" 2>&1 | tee tmp/run_tests_last.log
  local ec=${PIPESTATUS[0]}
  if ! grep -q '^Tests' tmp/run_tests_last.log; then
    echo "run_tests.sh: NO TESTS RAN — no Totals block in the output." >&2
    grep -iE 'have not been imported|Failed to load script|Parse Error|does not extend GutTest' tmp/run_tests_last.log | head -3 | sed 's/^/  /' >&2
    echo "  fresh worktree? godot --headless --audio-driver Dummy --import" >&2
    exit 3
  fi
  exit "$ec"
}

case "${1:-}" in
  "")          require_test_dir "test/unit";     run_gut -gdir=res://test/unit ;;
  --isolated)  require_test_dir "test/isolated"; run_gut -gdir=res://test/isolated ;;
  res://*)     require_test_file "${1#res://}";  run_gut -gtest="$1" ;;
  *)           N="${1#test_}"; N="${N%.gd}"; require_test_file "test/unit/test_${N}.gd"; run_gut -gtest="res://test/unit/test_${N}.gd" ;;
esac
