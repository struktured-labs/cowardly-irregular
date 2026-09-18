#!/usr/bin/env bash
# Render a village (default harmonia) at dawn/noon/night into tmp/screens/. Needs xvfb-run + a GL driver.
set -euo pipefail
cd "$(dirname "$0")/.."
V="${1:-harmonia}"
command -v xvfb-run >/dev/null || { echo "xvfb-run missing — launch the game instead and take a cap (F12)"; exit 3; }
mkdir -p tmp/screens
# ⛔ SANDBOXED user://. These scripts run the GAME, not a headless export, so godot resolves
# user:// by APPLICATION NAME and lands in ~/.local/share/godot/app_userdata/Cowardly Irregular
# -- struktured's LIVE save directory -- no matter which worktree you run from. Measured
# 2026-09-12: one sandboxed run created app_userdata/Cowardly Irregular/{logs,shader_cache},
# so unsandboxed it writes there. The fleet rule after the 2026-08-22 incident is that every
# godot invocation sets XDG_DATA_HOME inside its own worktree.
#
# Unlike the deploy chain's --export-release (deploy_web.sh:127), relocating the data root is
# SAFE here: these run the project and need no export_templates, which is the only thing that
# breaks when XDG_DATA_HOME moves.
_SHOT_XDG="$PWD/tmp/shot_xdg"; mkdir -p "$_SHOT_XDG"
# ⛔ THIS LOOP USED TO END IN `| command grep … || true`, WHICH DISCARDS THE EXIT CODE TWICE:
# `$?` after a pipeline is the LAST stage's status (grep always succeeds on a match), and the
# `|| true` swallows whatever survived. So godot could fail to parse the village, render an
# empty node, and this printed its lines and returned 0. Log first, read the log second,
# decide on the captured code -- the same shape tools/gate.sh uses and for the same reason.
_FAILED=0
_SHOTS=()
for P in 0.07 0.30 0.65; do
  _LOG="tmp/screens/${V}_${P}.log"
  _EC=0
  XDG_DATA_HOME="$_SHOT_XDG" xvfb-run -a godot --audio-driver Dummy --rendering-driver opengl3 --resolution 1280x720 \
    -s tools/village_screenshot.gd -- "--village=$V" "--phase=$P" > "$_LOG" 2>&1 || _EC=$?
  command grep -a -E "SCREEN|REFUSED|shot-guard" "$_LOG" || true
  if [ "$_EC" -ne 0 ]; then
    echo "[shot] phase $P FAILED (exit $_EC) — $_LOG" >&2
    _FAILED=1
    continue
  fi
  _SHOTS+=("tmp/screens/${V}_${P}.png")
done
if [ "$_FAILED" -ne 0 ]; then
  echo "[shot] BLOCKED: at least one phase produced no usable frame. These shots feed the itch" >&2
  echo "       store page; a missing one is better than a blank one." >&2
  exit 4
fi
if [ "${#_SHOTS[@]}" -eq 0 ]; then
  echo "[shot] BLOCKED: no shots were produced at all. A loop that ran zero times reports the" >&2
  echo "       same silence as a loop that succeeded." >&2
  exit 4
fi
# THREE DAY PHASES THAT PRODUCE ONE IMAGE ARE NOT THREE DAY PHASES. The blank run that
# prompted all this gave three byte-identical frames at dawn, noon and night -- the override
# at village_screenshot.gd:40 is guarded by `if "lighting" in scene`, so on a scene that
# failed to parse it silently no-opped and nothing said so.
# Conditioned on the override actually LANDING, because an interior or a dungeon has no day
# cycle and identical frames are the correct answer there. That distinction is why this reads
# the script's own phase_applied= report instead of just comparing the files.
_APPLIED=$(command grep -ahc 'phase_applied=true' tmp/screens/${V}_*.log 2>/dev/null | paste -sd+ | bc)
_UNIQ=$(md5sum "${_SHOTS[@]}" | awk '{print $1}' | sort -u | wc -l)
if [ "${_APPLIED:-0}" -gt 0 ] && [ "${#_SHOTS[@]}" -gt 1 ] && [ "$_UNIQ" -eq 1 ]; then
  echo "[shot] BLOCKED: ${#_SHOTS[@]} phases, ${_APPLIED} applied a day-phase override, and every" >&2
  echo "       frame is BYTE-IDENTICAL. The knob reported landing and changed nothing." >&2
  exit 5
fi
echo "[shot] $V: ${#_SHOTS[@]} frame(s), $_UNIQ distinct, ${_APPLIED:-0} with a day-phase override"
ls -la tmp/screens/
