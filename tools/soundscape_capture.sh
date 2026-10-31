#!/usr/bin/env bash
# Capture a village's music + living soundscape, day then night, to tmp/soundscape/<village>.mp4 and .ogg.
# Usage: [TAKES="today proposed louder"] tools/soundscape_capture.sh [village ...]   (default: harmonia eldertree, take proposed).
# Writes tmp/soundscape/<village>_<take>.mp4 + .ogg. Needs xvfb-run, a GL driver, ffmpeg.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xvfb-run >/dev/null || { echo "[scape] xvfb-run missing"; exit 3; }
command -v ffmpeg >/dev/null || { echo "[scape] ffmpeg missing"; exit 3; }
VILLAGES=("$@"); [ "${#VILLAGES[@]}" -gt 0 ] || VILLAGES=(harmonia eldertree)
# Sandboxed user:// (this runs the project, so it would otherwise reach his live profile) and his pads hidden.
_XDG="$PWD/tmp/scape_xdg_$$"; mkdir -p "$_XDG" tmp/soundscape
JAIL=()
if command -v bwrap >/dev/null && bwrap --dev-bind / / --tmpfs /dev/input true 2>/dev/null; then
  JAIL=(bwrap --dev-bind / / --tmpfs /dev/input)
fi
FPS=10
_FAILED=0
read -r -a TAKE_LIST <<< "${TAKES:-proposed}"
for V in "${VILLAGES[@]}"; do
 for T in "${TAKE_LIST[@]}"; do
  N_="${V}_${T}"
  D="tmp/soundscape/$N_"; rm -rf "$D"; mkdir -p "$D"
  LOG="tmp/soundscape/$N_.log"
  EC=0
  XDG_DATA_HOME="$_XDG" timeout 600 "${JAIL[@]}" xvfb-run -a -s "-screen 0 960x540x24" godot --audio-driver Dummy \
    --rendering-driver opengl3 --resolution 960x540 --fixed-fps "$FPS" --write-movie "$D/f.png" \
    -s tools/soundscape_capture.gd -- "--village=$V" "--take=$T" > "$LOG" 2>&1 || EC=$?
  command grep -a -E '^\[SCAPECAP\] (source|soundscape_place|nightfall|done)|SCAPECAP\]|ERROR' "$LOG" | command grep -av 'event ' || true
  N=$(find "$D" -name 'f*.png' | wc -l)
  if [ "$EC" -ne 0 ] || [ "$N" -lt 100 ] || [ ! -s "$D/f.wav" ]; then
    echo "[scape] $N_ FAILED (exit $EC, $N frames, wav=$( [ -s "$D/f.wav" ] && echo yes || echo no )) — $LOG" >&2
    _FAILED=1; continue
  fi
  ffmpeg -v error -y -framerate "$FPS" -i "$D/f%08d.png" -i "$D/f.wav" -c:v libx264 -pix_fmt yuv420p -c:a aac -b:a 160k -shortest "tmp/soundscape/$N_.mp4"
  ffmpeg -v error -y -i "$D/f.wav" -c:a libvorbis -q:a 5 "tmp/soundscape/$N_.ogg"
  echo "[scape] $N_ -> tmp/soundscape/$N_.mp4 + .ogg ($N frames)"
 done
done
[ "$_FAILED" -eq 0 ] || exit 4
