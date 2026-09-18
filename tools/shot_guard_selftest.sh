#!/usr/bin/env bash
# Run the shot-guard selftest in a sandboxed user://.
#
# WHY THIS EXISTS
# ---------------
# tools/shot_guard_selftest.gd had NO wrapper, so the only way to run it was a bare
#     godot --headless -s tools/shot_guard_selftest.gd
# which resolves user:// by APPLICATION NAME and lands in struktured's real profile.
# Measured 2026-09-18: four such runs between 01:45 and 01:50 filled user://logs/, whose
# ring holds exactly FIVE files, and rotated away his 2026-09-17 play session. Saves,
# settings, autogrind and autobattle were untouched -- logs only, and a crash trace is the
# one log that cannot be regenerated. Second time this lane has cost those five slots;
# .355-.358 did it from the deploy chain by a different route.
#
# ⛔ THE SCRIPT-LEVEL GUARD CANNOT PREVENT THIS AND I MEASURED THAT BEFORE RELYING ON IT.
# Godot opens user://logs/godot.log at BOOT, before the script runs. A refusing script still
# costs a log slot:
#     XDG_DATA_HOME outside the worktree -> script refuses, EC=2 -> and a log is STILL written
# So the guard in the .gd is damage LIMITATION -- it turns a silent bypass into a loud
# refusal, which is what stops someone running it four times without noticing, as I did.
# THIS WRAPPER is the thing that actually prevents the write, because it sets the redirect
# before the engine starts.
#
# ⛔ THE HAZARD IS AN *EMPTY* XDG_DATA_HOME, NOT AN INVALID ONE. I published the opposite
# and @cowir-adhoc falsified it; re-measured here under a fake HOME so nothing was at risk:
#     XDG_DATA_HOME=/nonexistent   -> godot ABORTS (EC=134), creates NOTHING. FAIL-CLOSED.
#     XDG_DATA_HOME=""             -> XDG treats empty as unset; godot writes the REAL
#                                     profile, EC=0, no warning. FAIL-OPEN and silent.
# So an unset-or-empty variable is the killer, which is what `${VAR:-}` or a failed command
# substitution produces. Hence the helper derives the path from $PWD and mkdir -p's it.
#
# ⛔ AND THE INVOCATION THAT ACTUALLY TOOK HIS LOG SLOTS WAS `--check-only`. Measured:
#     HOME=<fake> godot --headless --check-only -s <file>   EC=0, writes logs/godot.log
# A parse check reads as static and is not: it boots the engine, which opens user://logs/
# before anything else. Every bare --check-only I ran tonight cost a slot from a ring of five.
#
# Unlike the deploy chain's --export-release, relocating the data root is SAFE here: this
# runs the project and needs no export_templates, which is the only thing XDG_DATA_HOME breaks.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xvfb-run >/dev/null || { echo "[shot-guard] xvfb-run missing" >&2; exit 3; }
_XDG="$PWD/tmp/shot_xdg"
mkdir -p "$_XDG"
_EC=0
XDG_DATA_HOME="$_XDG" xvfb-run -a godot --headless -s tools/shot_guard_selftest.gd \
  > tmp/shot_guard_selftest.log 2>&1 || _EC=$?
command grep -aE '^  (ok|FAIL)|selftest\]|REFUSED' tmp/shot_guard_selftest.log || true
exit "$_EC"
