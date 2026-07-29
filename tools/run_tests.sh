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

# OUTCOME, not preconditions. require_test_file covers the file-absent cause. It is blind to the
# one that cost the fleet an hour on 2026-07-29: a FRESH WORKTREE has no .godot cache, so
# res://test/unit/test_X.gd resolves to nothing while the file sits on disk — same signature,
# exit 0, nothing run, reads as a pass. There will be a fourth cause. Rather than predicting each
# one, assert that a real suite happened: a run that executed prints a Totals block, and a vacuous
# one prints none, whatever made it vacuous.
run_and_verify() {
  local log; log="$(mktemp tmp/run_tests_verify.XXXXXX)"
  "$@" 2>&1 | tee "$log"
  local ec=${PIPESTATUS[0]}
  if ! grep -q "^---- Totals" "$log"; then
    echo "run_tests.sh: the run produced NO Totals block — nothing was executed (godot exit $ec)." >&2
    echo "  Most likely an unimported tree. Fix: godot --headless --audio-driver Dummy --import --quit" >&2
    echo "  Refusing to return $ec, which would read as a pass." >&2
    rm -f "$log"; exit 2
  fi
  rm -f "$log"
  exit "$ec"
}

case "${1:-}" in
  "")          run_and_verify "${BASE[@]}" -gdir=res://test/unit ;;
  --isolated)  run_and_verify "${BASE[@]}" -gdir=res://test/isolated ;;
  res://*)     require_test_file "${1#res://}"; run_and_verify "${BASE[@]}" -gtest="$1" ;;
  *)           N="${1#test_}"; N="${N%.gd}"; require_test_file "test/unit/test_${N}.gd"; run_and_verify "${BASE[@]}" -gtest="res://test/unit/test_${N}.gd" ;;
esac
