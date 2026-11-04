#!/usr/bin/env bash
# A party's tier-3 glory spells recorded in a REAL battle at low/mid/high intensity -> tmp/glory/<spell>_<tier>.mp4.
# Usage: tools/glory_spell_shots.sh [spell ...] [--speed=0.375] [--tiers=low,mid,high]  (summons work too: summon_ifrit ...)
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xvfb-run >/dev/null || { echo "[glory] xvfb-run missing"; exit 3; }
command -v ffmpeg >/dev/null || { echo "[glory] ffmpeg missing"; exit 3; }
SPEED=0.375
SPELLS=()
TIERS=(low mid high)
for a in "$@"; do
  case "$a" in
    --speed=*) SPEED="${a#--speed=}" ;;
    --tiers=*) IFS=, read -r -a TIERS <<< "${a#--tiers=}" ;;
    *) SPELLS+=("$a") ;;
  esac
done
[ "${#SPELLS[@]}" -eq 0 ] && SPELLS=(firaga blizzaga thundaga)
_XDG="$PWD/tmp/glory_xdg"; rm -rf "$_XDG"; mkdir -p "$_XDG" tmp/glory
JAIL=()
if command -v bwrap >/dev/null && bwrap --dev-bind / / --tmpfs /dev/input true 2>/dev/null; then
  JAIL=(bwrap --dev-bind / / --tmpfs /dev/input)
fi
FPS=30
_FAILED=0
for S in "${SPELLS[@]}"; do
  for T in "${TIERS[@]}"; do
    N_="${S}_$T"; D="tmp/glory/$N_"; rm -rf "$D"; mkdir -p "$D"
    LOG="tmp/glory/$N_.log"
    EC=0
    XDG_DATA_HOME="$_XDG" timeout 300 "${JAIL[@]}" xvfb-run -a -s "-screen 0 1280x720x24" godot --audio-driver Dummy \
      --rendering-driver opengl3 --resolution 1280x720 --fixed-fps "$FPS" --write-movie "$D/f.png" \
      -s tools/glory_spell_shots.gd -- "--spell=$S" "--tier=$T" "--speed=$SPEED" > "$LOG" 2>&1 || EC=$?
    command grep -a -E '^\[GLORYSHOT\]' "$LOG" || true
    N=$(find "$D" -name 'f*.png' | wc -l)
    if [ "$EC" -ne 0 ] || [ "$N" -lt 30 ]; then
      echo "[glory] $N_ FAILED (exit $EC, $N frames) — $LOG" >&2; _FAILED=1; continue
    fi
    ffmpeg -loglevel error -y -framerate "$FPS" -start_number 1 -i "$D/f%08d.png" -c:v libx264 -pix_fmt yuv420p -crf 20 "tmp/glory/$N_.mp4"
    echo "[glory] $N_: $N frames -> tmp/glory/$N_.mp4"
  done
done
exit "$_FAILED"
