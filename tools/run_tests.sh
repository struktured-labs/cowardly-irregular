#!/usr/bin/env bash
# run_tests.sh — THE canonical GUT invocation. Always mutes audio and logs
# to tmp/ so test runs never rotate the game's user://logs/godot.log away
# (the 2026-07-15 mage-cutscene crash lost its trace exactly that way).
#
# Usage:
#   tools/run_tests.sh                 # full unit suite
#   tools/run_tests.sh <name> [<name>...]  # one or more files, in ONE godot process
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

# PLAYER-DATA NET — HERE, not in gate.sh, because THIS is the documented command.
# The suite writes test data over user://script_exports/ under fixed filenames, which are the same
# paths the shipped Shift+E export and export_autogrind_rules() write. I originally put the
# snapshot in gate.sh; cowir-sfx measured that CLAUDE.md's canonical command is this script, that
# gate.sh merely WRAPS it, and that three of their own full-suite runs therefore had no net at all.
# Protecting the wrapper protects the path fewest runs take. Every run goes through here.
#
# Traps EXIT INT TERM. I could NOT reproduce the "EXIT doesn't fire on SIGTERM" mechanism three
# lanes diagnosed — in a controlled test EXIT alone did fire, and adding INT TERM fired it twice —
# so the orphaned snapshots are real but their stated cause is unconfirmed. INT TERM is free, the
# handler is idempotent behind the -d guard, and nothing saves a kill -9.
# 2026-08-19: this was ${HOME}-hardcoded while godot's user:// follows XDG_DATA_HOME, so a
# SANDBOXED run still snapshotted and restored the SHARED path on exit. Measured live: a gate
# exit re-stamped autobattle/profiles.json mid-session (mtime backward 25h, ctime now = a cp -a
# restore) while struktured was playing. settings.json and autobattle/ are netted and are exactly
# what a player edits mid-session, so any gate opened a window in which his edits silently
# reverted — and a content hash CANNOT detect it, because reverting TO the baseline is what
# produces the matching hash. Honouring XDG_DATA_HOME makes a sandboxed run net its OWN path,
# which is what six lanes already assumed sandboxing did. saves/ stays excluded below regardless.
_UD_BASE="${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/Cowardly Irregular"
# Dirs the suite is KNOWN to write, derived from the CODE's user:// corpus, not from
# incidents (both prior nets were incident-scoped and each missed the next incident):
# autogrind/ proven rewritten every full-suite run 2026-08-06 (4 ungated tests reach
# writers); root settings.json carried a gate-time mtime the same day. saves/ and
# screenshots/ are EXCLUDED deliberately — the suite must never write them (separately
# guarded) and restoring them could clobber a live play session's writes.
# The net is a BACKSTOP; per-test _test_disable_persistence gates are the real fix.
_NETTED_DIRS=(script_exports autogrind autobattle input)
_SNAP=""
for _d in "${_NETTED_DIRS[@]}"; do
  [ -d "$_UD_BASE/$_d" ] || continue
  [ -n "$_SNAP" ] || _SNAP="$(mktemp -d "${TMPDIR:-/tmp}/gate_exports_snap.XXXXXX")"
  mkdir -p "$_SNAP/$_d"
  cp -a "$_UD_BASE/$_d/." "$_SNAP/$_d/" 2>/dev/null || true
done
# Root-level flat files a dir list cannot carry (settings.json, autogrind_history.json,
# .recovery_mode_lock, debug atlases…). Restored to their exact pre-run bytes.
# The glob was *.json and therefore missed .recovery_mode_lock, which Godot writes at the
# root and which NEITHER arm covered. Harmless in itself (0 consumers in src/ — it is an
# engine artifact) but it survives every gate with a FRESH timestamp, so it tops the
# "newest files" list in his live dir and four lanes independently spent tonight reasoning
# it away in live-data audits. The second pattern picks up dotfiles; `[ -f ]` skips a glob
# that matched nothing. The restore side already copies dotfiles (cp -a "${_d}.").
if [ -d "$_UD_BASE" ]; then
  for _f in "$_UD_BASE"/* "$_UD_BASE"/.[!.]*; do
    [ -f "$_f" ] || continue
    [ -n "$_SNAP" ] || _SNAP="$(mktemp -d "${TMPDIR:-/tmp}/gate_exports_snap.XXXXXX")"
    mkdir -p "$_SNAP/__root__"
    cp -a "$_f" "$_SNAP/__root__/" 2>/dev/null || true
  done
fi
if [ -n "$_SNAP" ]; then
  trap '[ -n "$_SNAP" ] && [ -d "$_SNAP" ] && { for _d in "$_SNAP"/*/; do _n="$(basename "$_d")"; if [ "$_n" = "__root__" ]; then cp -a "${_d}." "$_UD_BASE/" 2>/dev/null; else mkdir -p "$_UD_BASE/$_n"; cp -a "${_d}." "$_UD_BASE/$_n/" 2>/dev/null; fi; done; rm -rf "$_SNAP"; }' EXIT INT TERM
  # SAY SO. gate.sh used to print this and I nearly dropped it in the move, which would have made the
  # net unobservable in every run rather than only in the ones where it silently failed. Four lanes
  # spent this morning arguing about whether it had run, from artifacts that could not answer.
  # THREE STATES, NOT TWO (cowir-ai, 2026-08-22). A sandbox drifts from "absent" into
  # "present but empty" after its first run, so the same command gives a different header
  # on run 2 than on run 1 — silent, then "snapshotted 0", then "snapshotted N".
  # Measured here: run 1 -> "did NOT arm"; run 2 -> "snapshotted 0 … restored on exit".
  # That trailing clause asserts a protection covering nothing, and a reader scanning for
  # "did the net arm" sees a snapshot line and moves on. Truthful count, reassuring frame.
  _SNAP_N="$(find "$_SNAP" -type f 2>/dev/null | wc -l)"
  if [ "$_SNAP_N" -eq 0 ]; then
    echo "run_tests.sh: player-data net ARMED but snapshotted 0 files under $_UD_BASE — it will restore nothing." >&2
    echo "  (the netted dirs exist and are empty — a reused sandbox, or a real dir whose data has gone. Not 'protected'.)" >&2
  else
    echo "run_tests.sh: snapshotted $_SNAP_N player data file(s) across ${#_NETTED_DIRS[@]} dir(s) + root files — restored on exit"
  fi
else
  # SAY SO IN THIS DIRECTION TOO. Measured 2026-08-22: with a fresh XDG_DATA_HOME every
  # loop above takes its `continue`, $_SNAP stays empty, this whole block is skipped, and
  # the run emits NOTHING — byte-identical to a run where the net armed, minus one line
  # nobody is looking for. Two causes print the same silence:
  #   BENIGN  a sandboxed run whose user dir is genuinely empty — nothing to protect
  #   BAD     $_UD_BASE computed wrong (XDG semantics change, a Godot path change, a typo)
  #           -> his real data is UNPROTECTED and the run says so nowhere
  # Non-blocking, because the benign case is legitimate and common. Loud, because the
  # bad case is otherwise unobservable. Same three-state rule the CI PE check uses: the
  # instrument's inability to act must be its own outcome, never folded into silence.
  echo "run_tests.sh: player-data net did NOT arm — nothing to snapshot under $_UD_BASE" >&2
  echo "  (benign for a sandboxed run; if this is his real user dir, the net is not protecting it)" >&2
fi
# Reap snapshots abandoned by a run that died without its trap — four were sitting in TMPDIR this
# morning, each holding a stale copy, and hand-restoring from one re-litters the real directory
# with another lane's canary. Older than an hour only, so a concurrent run's live snapshot is safe.
find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'gate_exports_snap.*' -type d -mmin +60 -exec rm -rf {} + 2>/dev/null || true

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
  # ASSERT THE COUNT, NOT THE LINE. The Totals-block check below was `grep -q '^Tests'`, and
  # GUT prints a Totals block with `Tests 0` when the named script PARSE-ERRORS or when the
  # -gtest name simply does not exist — so the line was present, the vacuity arm never fired,
  # and the run exited 0 having executed nothing. cowir-main hit the parse-error mouth live
  # (a duplicate const in HarmoniaVillage read "green"); cowir-battle named the typo mouth,
  # which is worse for mutation testing: a misspelled name returns EC=0 with no failures,
  # which reads as "my mutation didn't land" and invites reverting a change that was correct.
  # Enumerating causes is the losing game this block already rejects — so assert the outcome
  # one level deeper: a real run reports Tests > 0.
  _tests_ran="$(command grep -aE '^Tests[[:space:]]+[0-9]+' "$RUN_LOG" | tail -1 | tr -dc '0-9')"
  if [ -n "$_tests_ran" ] && [ "$_tests_ran" -eq 0 ]; then
    echo "run_tests.sh: NO TESTS RAN — Totals reported 'Tests 0'." >&2
    echo "  a named test whose script fails to parse, or a -gtest name that does not exist," >&2
    echo "  both produce a Totals block with zero tests and would otherwise exit 0." >&2
    command grep -aiE 'Parse Error|Failed to load script|does not extend GutTest' "$RUN_LOG" | head -3 | sed 's/^/  /' >&2
    echo "  logs kept for inspection: $RUN_LOG $GUT_LOG" >&2
    exit 3
  fi
  # PER-FILE VACUITY. The arm above is WHOLE-RUN: on a 1300-file suite one script that
  # fails to parse leaves `Tests` at ~1307, which is nonzero, so it cannot see it. A
  # parse-failed script is not counted as FAILED — it is NOT COUNTED. @cowir-overworld
  # measured both arms byte-identical: Tests, Passing, Failing, EC and the Totals block
  # are the same whether the broken file exists or was never written.
  #
  # The missing quantity is not in GUT's output at all: EXECUTED is `Scripts N`, AUTHORED
  # is on disk. tools/gate.sh has carried exactly this since before tonight (:50-53) and
  # I proved both its arms just now — but gate.sh is the WRAPPER, and CLAUDE.md sends
  # every lane here. That split is a REPEAT: the player-data net lived in gate.sh until
  # 2026-07-30 and protected only the runs that typed gate.sh, which is the argument
  # written at :28 of this file. Protecting the wrapper protects the path fewest runs take.
  #
  # AUTHORED comes from the FILESYSTEM, never `git ls-tree`: GUT globs the working tree, so
  # a commit-derived count reds on an uncommitted new test — i.e. on the lane whose job is
  # adding tests, for doing it right (@cowir-adhoc/@cowir-controller, measured, retracted).
  # Scoped to the invocation's OWN -gdir so test/unit and test/isolated never cross-count.
  local _gdir="" _a
  for _a in "$@"; do case "$_a" in -gdir=res://*) _gdir="${_a#-gdir=res://}" ;; esac; done
  # A -gtest SELECTION gets the same treatment, authored == the count we ASKED for. This
  # is the arm that was structurally absent on the named-file path -- precisely where a
  # dropped file is invisible, at THIS rung or at GUT's (-gselect eats the list too).
  # Star form, not \s+: Scripts/Tests/Asserts sit at COLUMN 0 while Passing/Failing are
  # indented 2, and `^\s+Scripts` matches nothing (four lanes hit this tonight; one
  # published "delta 1307" where the truth was 9). No :-0 default -- an unmeasurable
  # instrument WARNS, it never becomes a zero that fires the alarm.
  if [ -z "$_gdir" ] && [ -n "${_REQUESTED:-}" ] && [ "${_REQUESTED}" -gt 0 ]; then
    local _sel_exec
    _sel_exec="$(command grep -aoE '^[[:space:]]*Scripts[[:space:]]+[0-9]+' "$RUN_LOG" | tail -1 | tr -dc '0-9')"
    if [ -z "$_sel_exec" ]; then
      echo "run_tests.sh: WARNING — no 'Scripts N' line; selection completeness NOT checked." >&2
    elif [ "$_sel_exec" -lt "$_REQUESTED" ]; then
      echo "run_tests.sh: NOT ALL REQUESTED FILES RAN — asked for $_REQUESTED, GUT loaded $_sel_exec." >&2
      echo "  ⇒ DISCARD THIS RUN. A selection that silently loses a file still prints a real" >&2
      echo "    Totals block and exits 0, so it reads as a correct smaller run." >&2
      command grep -aiE 'Parse Error|Failed to load script|does not extend GutTest' "$RUN_LOG" | head -5 | sed 's/^/  /' >&2
      echo "  logs kept for inspection: $RUN_LOG $GUT_LOG" >&2
      exit 3
    fi
  fi
  if [ -n "$_gdir" ] && [ -d "$_gdir" ]; then
    local _authored _executed
    _authored="$(ls "$_gdir"/test_*.gd 2>/dev/null | command grep -c .)"   # grep -c PRINTS 0; no ||
    _executed="$(command grep -aoE '^[[:space:]]*Scripts[[:space:]]+[0-9]+' "$RUN_LOG" | tail -1 | tr -dc '0-9')"
    if [ -z "$_executed" ]; then
      # THREE-STATE: the instrument could not measure. That must be its own loud outcome,
      # never folded into a verdict about the suite.
      echo "run_tests.sh: WARNING — no 'Scripts N' line; per-file vacuity NOT checked." >&2
    elif [ "$_executed" -lt "$_authored" ]; then
      echo "run_tests.sh: NOT ALL TEST FILES RAN — $_authored authored in $_gdir, $_executed loaded." >&2
      echo "  ⇒ DISCARD THIS RUN. It did not execute everything it was supposed to, so its" >&2
      echo "    Tests/Passing/Failing/EC describe a SUBSET and are silent about the rest." >&2
      echo "    This says nothing about whether the code is good — only that this run" >&2
      echo "    cannot answer. Fix the run, then re-read." >&2
      echo "  Causes seen so far (NOT a complete list — do not stop at the first that fits):" >&2
      echo "    - the tree was never imported. A fold adding class_name files makes GameLoop-" >&2
      echo "      dependent scripts fail to resolve; the cascade reads like a broken subsystem." >&2
      echo "      Run: godot --headless --audio-driver Dummy --import --quit, check the LOG" >&2
      echo "      (its exit code is inert), then re-run this." >&2
      echo "    - a test script genuinely fails to parse — SKIPPED, never counted as failed." >&2
      command grep -aiE 'Parse Error|Failed to load script|does not extend GutTest' "$RUN_LOG" | head -5 | sed 's/^/  /' >&2
      echo "  logs kept for inspection: $RUN_LOG $GUT_LOG" >&2
      exit 3
    elif [ "$_executed" -gt "$_authored" ]; then
      # Also an instrument mismatch, NOT a suite failure — a nested corpus would do it.
      # Failing here would be the permanent false alarm everyone learns to suppress.
      echo "run_tests.sh: WARNING — GUT loaded $_executed script(s) but only $_authored are" >&2
      echo "  directly in $_gdir. The authored count may be mis-scoped; not failing on it." >&2
    fi
  fi
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

# Extra arguments are SILENTLY DROPPED by the dispatcher below — every branch reads $1
# and nothing reads $2..$N, so `run_tests.sh A B` runs A alone with a valid Totals block,
# Scripts 1 and EC 0, which is indistinguishable from a correct single-file run. The
# wrapper's own per-file vacuity arm cannot catch it: that arm is gated on -gdir, and the
# named-file branches take -gtest, so it is off on precisely the path that loses files.
# (GUT's stacked -gselect drops in the OPPOSITE direction, keeping the LAST file.)
# MULTIPLE NAMES ARE ACCEPTED, and this supersedes the reject that landed in d5cea002.
# The original defect (cowir-music): `run_tests.sh A B` referenced $1 only, so B was
# SILENTLY DROPPED — EC=0, a real Totals block, `Scripts 1`, no warning, indistinguishable
# from a correct single-file run because it WAS one. cowir-autogrind diagnosed why the
# per-file arm above could not see it: that arm is gated on -gdir, and every named-file
# branch takes a -gtest path where _gdir is empty, so the detector that catches a dropped
# file is OFF on exactly the path that drops files.
#
# REJECTING was the smaller fix and its message pointed at `repeated -gtest= via
# gut_cmdln.gd` — which cowir-story measured drops the PLAYER-DATA NET (:53 dirs, :67 root
# arm) and the --log-file redirect at :24 that keeps a run out of his user://logs/. Three
# protections removed to work around one bug, and five lanes ran 26-119-file post-refactor
# checklists through that path tonight. cowir-main's call to supersede it.
#
# ⛔ NOT -gselect: stacked -gselect runs the file named LAST and discards the rest, with a
#    valid Totals block and EC=0 (cowir-controller found it; cowir-battle measured that it
#    is the LAST, not merely "one"). Repeated -gtest= is the form that composes.
case "${1:-}" in
  "")          require_test_dir "test/unit";     run_gut -gdir=res://test/unit ;;
  --isolated)
    [ "$#" -eq 1 ] || { echo "run_tests.sh: --isolated takes no other arguments; got $# ($*)" >&2; exit 2; }
    require_test_dir "test/isolated"; run_gut -gdir=res://test/isolated ;;
  *)
    _SEL=()
    for _n in "$@"; do
      case "$_n" in
        --*)     echo "run_tests.sh: unknown option: $_n" >&2; exit 2 ;;
        res://*) require_test_file "${_n#res://}"; _SEL+=("-gtest=$_n") ;;
        *)       N="${_n#test_}"; N="${N%.gd}"
                 require_test_file "test/unit/test_${N}.gd"
                 _SEL+=("-gtest=res://test/unit/test_${N}.gd") ;;
      esac
    done
    # ONE godot for the whole list: the net and the log redirect still apply, and the
    # engine boots once instead of N times (a shell loop over 26 files was measured
    # KILLED at 2 min having reported ZERO files -- cowir-story).
    _REQUESTED="${#_SEL[@]}"
    run_gut "${_SEL[@]}" ;;
esac
