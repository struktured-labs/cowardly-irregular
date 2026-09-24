#!/usr/bin/env bash
# run_tests.sh — THE canonical GUT invocation. Always mutes audio and logs
# to tmp/ so test runs never rotate the game's user://logs/godot.log away
# (the 2026-07-15 mage-cutscene crash lost its trace exactly that way).
#
# Usage:
#   tools/run_tests.sh                 # full unit suite
#   tools/run_tests.sh <name> [<name>...]  # one or more files, in ONE godot process
#   tools/run_tests.sh --isolated      # the quarantined suite (own process by design)
#   RUN_TESTS_SEE_PADS=1 tools/run_tests.sh ...  # let godot see plugged-in controllers (hidden by default)
#
# Exit codes:  0 pass · 1 test failures · 2 bad invocation · 3 nothing ran · 4 a test did not assert
#              124 wedged (no Totals block — the run was never judged)
# A shutdown SIGKILL (137) or SIGTERM (143) AFTER a real Totals block is not 124 and not a pass
# by itself. The totals are the verdict: Failing N stays exit 1; a block with no failures is exit 0.
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

# HIDE THE HOST'S CONTROLLERS. Headless godot enumerates a plugged-in pad, and every "no pad attached"
# arm then goes RED: 17 across 10 files of one 92-file corpus with struktured's 8BitDo awake
# (2026-09-23, identical at unmodified main), 40 in cowir-main's first .474 gate. A live press also
# reached a test process and freed an editor mid-arm. What is plugged into the box is not the tree,
# so every run gets an EMPTY /dev/input. Measured on the real child before relying on it: a 90-frame
# probe counts 1 pad bare / 0 jailed; exit codes pass through; a spinning godot under `timeout 3` is
# still cut at 3.0s with EC=124 and nothing left running. ⚠️ No `--die-with-parent`: measured, it
# does NOT reap a TERM-ignoring child, so it would read as a backstop and be none (the --kill-after
# trap below). The bound still rests on godot honouring the TERM that bwrap forwards.
# The reported state is MEASURED from the /dev/input godot will see, not inferred from whether this
# jail applied: under an OUTER jail (cowir-main gates that way) a nested bwrap is refused, and the
# first version then printed VISIBLE over a run whose pads were already hidden.
PAD_JAIL=(bwrap --dev-bind / / --tmpfs /dev/input)
_input_nodes() { if [ -d /dev/input ]; then ls -A /dev/input | wc -l; else echo 0; fi; }
_jail_err=""
if [ "${RUN_TESTS_SEE_PADS:-0}" != "1" ] && command -v bwrap > /dev/null; then
  if _jail_err="$("${PAD_JAIL[@]}" true 2>&1)"; then
    BASE=("${PAD_JAIL[@]}" "${BASE[@]}")
  fi
fi
if [ "${BASE[0]}" = "bwrap" ]; then
  PAD_STATE="hidden (empty /dev/input)"
elif [ "$(_input_nodes)" -eq 0 ]; then
  PAD_STATE="hidden (/dev/input already empty here)"
elif [ "${RUN_TESTS_SEE_PADS:-0}" = "1" ]; then
  PAD_STATE="VISIBLE (RUN_TESTS_SEE_PADS=1)"
else
  PAD_STATE="VISIBLE ($([ -n "$_jail_err" ] && echo "${_jail_err%%,*}" || echo "no bwrap on PATH")) — 'no pad' arms red if a controller is plugged in"
fi

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
# ARM 1 OF 2 -- THIS ARRAY IS THE DIRECTORY CORPUS, NOT THE WHOLE NET.
# Root-level *.json (settings.json, autogrind_history.json) are snapshotted by a SEPARATE
# glob ~14 lines below, restored via the __root__ branch. That arm has NO identifier, so
# grepping for what the net covers cannot find it, and `grep -A3 _NETTED_DIRS` -- what
# everyone actually runs -- shows a complete-looking answer that is wrong.
# Three lanes independently concluded "root file => not netted" from this array alone on
# 2026-08-22; two of them had already read the correction in-channel first.
# saves/ IS deliberately excluded (see below) -- do NOT generalise the root-json arm to it.
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
# PROVENANCE HEADER -- a log in tmp/ does not say which TREE produced it, and a stale one reads as
# current. cowir-sfx 2026-09-17: a probe log carried `SCRIPT ERROR: Invalid access to property
# '_sfx_suppressed_by_cooldown'` naming a member that a commit 21 minutes EARLIER had added -- the
# branch had been cut off a base predating that fix, so the error was correct about a tree nobody
# has. A stale GREEN makes you ship something unverified; a stale RED makes you CHANGE WORKING CODE,
# and the fix passes every test you write for it. The run also scored `1/1 passed`: the error
# aborted the function AFTER its one assert, so EC=4 (which keys off [Risky] NAMES) cannot see it.
# `dirty=N` is the count git status reports; N>0 means the SHA does not describe what ran.
_tree_stamp() {
  local sha branch dirty
  sha="$(git rev-parse --short=9 HEAD 2>/dev/null)"
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  # wc, not `grep -c .`: grep exits 1 on zero matches, so a CLEAN tree would take the error branch.
  dirty="$(git status --porcelain 2>/dev/null | wc -l | tr -dc '0-9')"
  [ -n "$sha" ] || { sha="unknown"; branch="unknown"; dirty="?"; }
  echo "run_tests.sh: TREE ${sha} (${branch}) dirty=${dirty} at $(date -Is)"
}

# kill(1) delivers SIGKILL. `timeout --signal=KILL` on this box does not.
_kill_pid_tree() {
  local _p="$1" _c
  for _c in $(ps -o pid= --ppid "$_p" 2>/dev/null); do
    _kill_pid_tree "$_c"
  done
  kill -9 "$_p" 2>/dev/null || true
}

run_gut() {
  # Truncate explicitly, then append: `tee -a` alone would inherit a same-PID log from a previous
  # boot, which is the same stale-artifact class the header exists to close.
  : > "$RUN_LOG"
  _tree_stamp | tee -a "$RUN_LOG" >&2
  echo "run_tests.sh: host controllers ${PAD_STATE}" | tee -a "$RUN_LOG" >&2
  # ⛔ BOUND THE RUN. A wedged godot is not a slow one and does not end on its own: the .461 gate
  # spun 1h57m at 100% on ONE thread with its log frozen for 1h49m, and nothing in this script or
  # in gate.sh would ever have stopped it. Measured suites are 268-689s, so 1800s is ~2.6x the
  # worst observed and cannot cut a healthy run.
  local _budget="${RUN_TESTS_TIMEOUT:-1800}" _t0 _elapsed
  _t0=$SECONDS
  # ⛔ PLAIN `timeout`, DELIBERATELY — NO `--kill-after`. THIS BINARY CANNOT DELIVER SIGKILL.
  # Measured five lanes independently, identical cooperative child, only the signal varying:
  #   --signal=TERM / INT / HUP / 15   fire AT the budget
  #   --signal=KILL / 9                NEVER fire; the child runs to completion
  # `--kill-after` escalates to SIGKILL, so it is the one path this binary cannot take — which is
  # why four lanes' TERM-ignoring children all survived it. It bought us nothing here except
  # turning a clean 124 into a 125, so it is gone. Godot has the DEFAULT SIGTERM disposition
  # (SigIgn=0, bit 0x4000 clear in SigIgn and SigCgt, read off a live gate), so plain TERM reaps
  # it and no escalation is needed. ⚠️ A CONSEQUENCE WORTH MORE THAN THIS CALL SITE:
  # `timeout --signal=KILL N CMD` is a SILENT NO-OP as a bound — it returns 124 on schedule while
  # the command runs on. Never reach for KILL as "the forceful option".
  # Totals are printed before engine shutdown. A wedged mix thread then never joins,
  # so the process sits forever with the results already in the log. `timeout --signal=KILL`
  # cannot deliver SIGKILL on this box; kill(1) can. Silence AFTER a real Totals block means
  # shutdown is stuck, not that a test is still thinking. Default 30s; tests shrink it.
  local _poll="${RUN_TESTS_POLL_S:-1}" _quiet="${RUN_TESTS_QUIET_AFTER_TOTALS:-30}"
  case "$_poll" in ''|*[!0-9]*) _poll=1 ;; esac
  case "$_quiet" in ''|*[!0-9]*) _quiet=30 ;; esac
  timeout "$_budget" "${BASE[@]}" "$@" > >(tee -a "$RUN_LOG") 2>&1 &
  local _tp=$! _last_size=0 _still=0 _sz _killed_after_totals=0
  while kill -0 "$_tp" 2>/dev/null; do
    sleep "$_poll"
    _sz=$(wc -c < "$RUN_LOG" 2>/dev/null | tr -dc '0-9')
    if [ -z "$_sz" ] || [ "$_sz" != "$_last_size" ]; then
      _last_size=${_sz:-0}
      _still=0
      continue
    fi
    _still=$((_still + _poll))
    if [ "$_still" -ge "$_quiet" ] && command grep -aE '^Tests[[:space:]]+[0-9]+$' "$RUN_LOG" >/dev/null; then
      echo "run_tests.sh: totals are in and the log has been still for ${_still}s — killing a mix thread that will not join" >&2
      _killed_after_totals=1
      _kill_pid_tree "$_tp"
      break
    fi
  done
  wait "$_tp"
  local ec=$?
  _elapsed=$(( SECONDS - _t0 ))
  # A signal exit that already has a Totals block was judged. 137 is our SIGKILL (or
  # SoundManager's OS.kill at headless shutdown). It must not fall through to WEDGED,
  # and it must not count as a pass while Failing N is on the page.
  local _totals_present=0 _failing_n=0 _passing_n=0 _tests_n=0 _shutdown_raw=0 _signal_exit=0
  if command grep -aE '^Tests[[:space:]]+[0-9]+$' "$RUN_LOG" >/dev/null; then
    _totals_present=1
    _tests_n="$(command grep -aE '^Tests[[:space:]]+[0-9]+$' "$RUN_LOG" | tail -1 | tr -dc '0-9')"
    _passing_n="$(command grep -aE '^[[:space:]]+Passing[[:space:]]+[0-9]+$' "$RUN_LOG" | tail -1 | tr -dc '0-9')"
    _failing_n="$(command grep -aE '^[[:space:]]+Failing[[:space:]]+[0-9]+$' "$RUN_LOG" | tail -1 | tr -dc '0-9')"
    _passing_n="${_passing_n:-0}"
    _failing_n="${_failing_n:-0}"
  fi
  case "$ec" in
    124|125|137|143) _signal_exit=1 ;;
  esac
  if [ "$_killed_after_totals" -eq 1 ]; then
    _signal_exit=1
  fi
  if [ "$_totals_present" -eq 1 ] && [ "$_signal_exit" -eq 1 ]; then
    _shutdown_raw=$ec
    echo "run_tests.sh: SHUTDOWN KILLED AFTER TOTALS (process exit ${_shutdown_raw})." >&2
    echo "  Tests ${_tests_n}  Passing ${_passing_n}  Failing ${_failing_n}." >&2
    echo "  The signal is not the verdict. A run passes only when the totals show no failures." >&2
    if [ "$_failing_n" -gt 0 ]; then
      echo "  Failing ${_failing_n} — this stays a failure (exit 1). The kill must not hide it." >&2
      ec=1
    else
      echo "  Failing 0 — the totals are clean. Exit 0 unless a later vacuity check refuses the run." >&2
      ec=0
    fi
  fi
  # ⛔ DO NOT TEST FOR 124 ALONE — THE CODE IS SET BY THE FLAGS, NOT BY THE IMPLEMENTATION.
  # Plain / --signal=TERM -> 124; --kill-after -> 125. I first wrote this off as uutils-vs-GNU;
  # it is not. And the code can name a signal that was NEVER SENT: a TERM-ignoring child under
  # --kill-after returned EC=137 ("killed by SIGKILL") at elapsed 8007ms against a 2s budget —
  # it ran to completion and exited on its own. A lane retracted that exact row as a measurement
  # error when it was a true observation of a lying instrument.
  # ELAPSED TIME is the only stable signal: only a run that actually reached the budget was cut
  # by it. The code corroborates, it does not decide, and the normalisation to 124 below is
  # load-bearing rather than a courtesy. The 125/137/143 arms are kept so a hand-rolled wrapper
  # or a future fixed binary still lands here.
  # This arm sits ABOVE the vacuity checks on purpose — a killed run prints no Totals, so without
  # it a wedge exits 3 and reports itself as "NO TESTS RAN", which is a different defect entirely.
  # (Measured: that is exactly what the first version of this arm did.)
  # 137/143 that already carried a Totals block were rewritten above. Reaching this arm
  # with those codes means there is no totals block: the run was never judged.
  case "$ec" in
    124|125|137|143)
      if [ "$_elapsed" -ge "$_budget" ]; then
        echo "run_tests.sh: WEDGED — no exit after ${_budget}s (ran ${_elapsed}s, EC=$ec); killed, not failed." >&2
        echo "  A hang is not a red: judge a long godot run by CPU TIME, not log growth. A spinning" >&2
        echo "  NON-main thread means the GDScript is not the cause — we author no threads." >&2
        echo "  per-thread CPU, no ptrace needed:  for t in /proc/<pid>/task/*; do ...; done" >&2
        echo "  last file the log reached:" >&2
        sed 's/\x1b\[[0-9;]*m//g' "$RUN_LOG" | command grep -aE '^res://' | tail -1 | sed 's/^/    /' >&2
        echo "  logs kept for inspection: $RUN_LOG $GUT_LOG" >&2
        exit 124
      fi
      ;;
  esac
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
  _tests_ran="$(command grep -aE '^Tests[[:space:]]+[0-9]+$' "$RUN_LOG" | tail -1 | tr -dc '0-9')"
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
    _sel_exec="$(command grep -aoE '^[[:space:]]*Scripts[[:space:]]+[0-9]+$' "$RUN_LOG" | tail -1 | tr -dc '0-9')"
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
  # A test that asserted NOTHING is not a pass, and nothing above can see it: GUT scores it
  # Risky, `-gexit` returns 0, and the Totals block is perfectly well-formed. Six lanes measured
  # this on 2026-09-16 by renaming the member their guard defends — one got
  # `EC=0 · Passing 4 · Risky 10 · Asserts 125 -> 16` from a file whose subject no longer existed.
  #
  # Derived from unique test NAMES, never from a line count: `[Risky]` prints TWICE per test (a
  # named line and a bare "Did not assert"), so a count is 2x — the same trap as `grep -cF
  # '[Failed]'`. tools/gate.sh has derived it this way for months; this is that line, in the
  # wrapper every LANE uses, which had no risky handling at all.
  #
  # `[Pending]` is NOT counted. It is a DELIBERATE skip this codebase uses on purpose
  # (test_real_saves_hydrate_smoke says so in its own text, on every sandboxed run).
  #
  # Exit 4 only when the run would otherwise be GREEN: a real failure must keep reporting 1.
  # ⚠️ STRIP ANSI FIRST. Godot colours stdout, so the raw line is
  #   `\e[33m    [Risky]:  \e[0mtest_name did not assert`
  # and a pattern anchored on `[Risky]:` cannot cross the escape to reach the name — it matches
  # ZERO on a log that plainly contains the marker. gate.sh greps the ANSI-free `--log-file` and
  # never meets this; RUN_LOG is the stdout capture and does. CLAUDE.md documents the same trap
  # for `[Failed]`, and this implementation walked into it before the probe caught it.
  # [A-Za-z_0-9]: 191 arms carry an uppercase letter (test_CONTROL_*, test_ANY_*) and a
  # lowercase-only class made every one of them invisible to this check.
  local _noassert
  _noassert="$(sed 's/\x1b\[[0-9;]*m//g' "$RUN_LOG" | command grep -aoE '\[Risky\]: +[A-Za-z_0-9]+ did not assert' | sort -u | command grep -c . )"
  if [ "${_noassert:-0}" -gt 0 ]; then
    echo "run_tests.sh: ${_noassert} TEST(S) RAN AND ASSERTED NOTHING — scored Risky, never [Failed]." >&2
    echo "  ⇒ An arm that aborts before its first assert is NOT failing, so EC and Failing are both" >&2
    echo "    clean while the guard defends nothing. Usually the member it names was renamed or" >&2
    echo "    removed and a direct reference raised. An existence arm using get()/has_method()" >&2
    echo "    turns this into a failing assert that says so." >&2
    sed 's/\x1b\[[0-9;]*m//g' "$RUN_LOG" | command grep -aoE '\[Risky\]: +[A-Za-z_0-9]+ did not assert' | sort -u | sed 's/^/    /' >&2
    if [ "$ec" = "0" ]; then
      echo "  ⇒ exit 4: this run would otherwise have reported success." >&2
      exit 4
    fi
    echo "  (the run already reports failures; leaving exit $ec)" >&2
  fi

  if [ -n "$_gdir" ] && [ -d "$_gdir" ]; then
    # ⛔ A test_*.gd in a SUBDIRECTORY of $_gdir is invisible to BOTH numbers below and never runs.
    # GUT's include_subdirs defaults to false (addons/gut/gut_config.gd:29) and nothing in tools/
    # passes -ginclude_subdirs, so such a file is not LOADED; _authored globs one level, so it is
    # not COUNTED either. Neither the < nor the > branch can fire: Scripts == authored stays
    # satisfied while those files contribute nothing. That is the one false-GREEN path in an
    # invariant whose every other failure mode is a false red, so it gets its own arm.
    local _nested _nested_list
    _nested_list="$(find "$_gdir" -mindepth 2 -name 'test_*.gd' -type f 2>/dev/null | sort)"
    _nested="$(printf '%s' "$_nested_list" | command grep -c . || true)"
    if [ "${_nested:-0}" -gt 0 ]; then
      echo "run_tests.sh: ${_nested} test file(s) SIT BELOW $_gdir AND DID NOT RUN." >&2
      printf '%s\n' "$_nested_list" | head -10 | sed 's/^/    /' >&2
      echo "  ⇒ DISCARD THIS RUN. GUT's include_subdirs is false and nothing passes" >&2
      echo "    -ginclude_subdirs, so these were never loaded; the authored count globs one" >&2
      echo "    level, so they were never counted. Scripts == authored is SATISFIED and silent" >&2
      echo "    about every test in them." >&2
      echo "  Move them up beside the others, or pass -ginclude_subdirs deliberately." >&2
      exit 3
    fi

    local _authored _executed
    _authored="$(ls "$_gdir"/test_*.gd 2>/dev/null | command grep -c .)"   # grep -c PRINTS 0; no ||
    _executed="$(command grep -aoE '^[[:space:]]*Scripts[[:space:]]+[0-9]+$' "$RUN_LOG" | tail -1 | tr -dc '0-9')"
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
  if ! command grep -qE '^Tests[[:space:]]+[0-9]+$' "$RUN_LOG"; then
    echo "run_tests.sh: NO TESTS RAN — no Totals block in the output." >&2
    command grep -aiE 'have not been imported|Failed to load script|Parse Error|does not extend GutTest' "$RUN_LOG" | head -3 | sed 's/^/  /' >&2
    echo "  fresh worktree? godot --headless --audio-driver Dummy --import" >&2
    echo "  logs kept for inspection: $RUN_LOG $GUT_LOG" >&2
    exit 3
  fi
  # GUT's own exit can be 0 while the totals name failures (a kill we rewrote, or a
  # runner that returned before -gexit). A pass is the totals, not the signal.
  if [ "${_failing_n:-0}" -gt 0 ] && [ "$ec" -eq 0 ]; then
    echo "run_tests.sh: totals show Failing ${_failing_n} but the runner exited 0 — refusing to call this a pass." >&2
    ec=1
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
