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

# PER-PROCESS LOG PATHS. These were shared (tmp/gut_manual_godot.log and tmp/run_tests_last.log),
# and up to 6 lanes/agents run this concurrently. A neighbour's run truncates the file between our
# write and our read, so the outcome assertion below finds no "Tests" line and reports exit 3 —
# NO TESTS RAN — on a run that actually passed. A false RED on the tool the whole fleet gates with,
# reported by a subagent that hit it on a green run (2026-07-30).
# Shared mutable state keyed by nothing is the same class as user:// keying by app name.
GUT_LOG="tmp/gut_manual_godot.$$.log"
RUN_LOG="tmp/run_tests_last.$$.log"
BASE=(godot --headless --audio-driver Dummy --log-file "$GUT_LOG" -s addons/gut/gut_cmdln.gd -gprefix=test_ -gsuffix=.gd -gexit)

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
  "${BASE[@]}" "$@" 2>&1 | tee "$RUN_LOG"
  local ec=${PIPESTATUS[0]}
  # `command grep`: the session grep is a ugrep shim carrying -I, and it SILENTLY skips a file it
  # judges binary. Godot logs can carry NUL bytes, which made a 150KB log read as zero matches —
  # a false zero on the artifact this assertion depends on.
  if ! command grep -q '^Tests' "$RUN_LOG"; then
    echo "run_tests.sh: NO TESTS RAN — no Totals block in the output." >&2
    command grep -aiE 'have not been imported|Failed to load script|Parse Error|does not extend GutTest' "$RUN_LOG" | head -3 | sed 's/^/  /' >&2
    echo "  fresh worktree? godot --headless --audio-driver Dummy --import" >&2
    echo "  logs kept for inspection: $RUN_LOG $GUT_LOG" >&2
    exit 3
  fi
  # Keep both logs when the run FAILED — that is exactly when someone needs the evidence — and
  # clean up when it passed, or per-process naming turns into per-process litter.
  if [ "$ec" -eq 0 ]; then
    rm -f "$RUN_LOG" "$GUT_LOG"
  else
    echo "run_tests.sh: logs kept for inspection: $RUN_LOG $GUT_LOG" >&2
  fi
  exit "$ec"
}

case "${1:-}" in
  "")          require_test_dir "test/unit";     run_gut -gdir=res://test/unit ;;
  --isolated)  require_test_dir "test/isolated"; run_gut -gdir=res://test/isolated ;;
  res://*)     require_test_file "${1#res://}";  run_gut -gtest="$1" ;;
  *)           N="${1#test_}"; N="${N%.gd}"; require_test_file "test/unit/test_${N}.gd"; run_gut -gtest="res://test/unit/test_${N}.gd" ;;
esac
