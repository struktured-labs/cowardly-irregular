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
# ⛔ AND AN INVALID XDG_DATA_HOME IS WORSE THAN NONE. Measured while testing this very fix:
#     XDG_DATA_HOME=/nonexistent-outside godot --headless -s ...
#     -> godot ABORTS (EC=134) and falls back to the DEFAULT user:// -- his real profile.
# So a typo'd sandbox path writes where you were trying not to, while you believe you are
# sandboxed. That is why this wrapper mkdir -p's the directory before using it, and why the
# path is derived from $PWD rather than typed. I burned two more of his five log slots
# learning that, in the act of fixing the first four.
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
