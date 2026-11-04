#!/usr/bin/env bash
# W1 boss signatures recorded in a REAL battle -> tmp/boss_sig/<boss>.mp4 (+ .gif). Sandboxed user://, pads hidden.
# Usage: tools/boss_signature_shots.sh [boss_id ...] [--speed=0.375]
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xvfb-run >/dev/null || { echo "[bosssig] xvfb-run missing"; exit 3; }
command -v ffmpeg >/dev/null || { echo "[bosssig] ffmpeg missing"; exit 3; }
SPEED=0.375
EXTRA=()
SUFFIX=""
BOSSES=()
for a in "$@"; do
  case "$a" in
    --speed=*) SPEED="${a#--speed=}" ;;
    --mode7) EXTRA+=("--mode7"); SUFFIX="_mode7" ;;
    *) BOSSES+=("$a") ;;
  esac
done
if [ "${#BOSSES[@]}" -eq 0 ]; then
  mapfile -t BOSSES < <(python3 -c "import json;d=json.load(open('data/monsters.json'));print('\n'.join(k for k,v in d.items() if isinstance(v,dict) and v.get('fx_signature')))")
fi
_XDG="$PWD/tmp/bosssig_xdg"; rm -rf "$_XDG"; mkdir -p "$_XDG" tmp/boss_sig
JAIL=()
if command -v bwrap >/dev/null && bwrap --dev-bind / / --tmpfs /dev/input true 2>/dev/null; then
  JAIL=(bwrap --dev-bind / / --tmpfs /dev/input)
fi
FPS=30
_FAILED=0
for B in "${BOSSES[@]}"; do
  D="tmp/boss_sig/$B$SUFFIX"; rm -rf "$D"; mkdir -p "$D"
  LOG="tmp/boss_sig/$B$SUFFIX.log"
  EC=0
  XDG_DATA_HOME="$_XDG" timeout 300 "${JAIL[@]}" xvfb-run -a -s "-screen 0 1280x720x24" godot --audio-driver Dummy \
    --rendering-driver opengl3 --resolution 1280x720 --fixed-fps "$FPS" --write-movie "$D/f.png" \
    -s tools/boss_signature_shots.gd -- "--boss=$B" "--speed=$SPEED" "${EXTRA[@]}" > "$LOG" 2>&1 || EC=$?
  command grep -a -E '^\[BOSSSHOT\]' "$LOG" || true
  N=$(find "$D" -name 'f*.png' | wc -l)
  if [ "$EC" -ne 0 ] || [ "$N" -lt 30 ]; then
    echo "[bosssig] $B FAILED (exit $EC, $N frames) — $LOG" >&2; _FAILED=1; continue
  fi
  ffmpeg -loglevel error -y -framerate "$FPS" -start_number 1 -i "$D/f%08d.png" -c:v libx264 -pix_fmt yuv420p -crf 20 "tmp/boss_sig/$B$SUFFIX.mp4"
  echo "[bosssig] $B: $N frames -> tmp/boss_sig/$B$SUFFIX.mp4"
done
exit "$_FAILED"
