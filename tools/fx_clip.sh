#!/usr/bin/env bash
# Render FX sequences (data/vfx_sequences.json) to clips in tmp/fx/: <seq>.mp4 + <seq>.gif.
# Usage: tools/fx_clip.sh [seq ...] [--speed=0.375]   (default: every sequence, at the 1.5x default)
# Needs xvfb-run + a GL driver + ffmpeg. Deterministic: --write-movie at a fixed fps, seeded RNG.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xvfb-run >/dev/null || { echo "[fx] xvfb-run missing"; exit 3; }
command -v ffmpeg >/dev/null || { echo "[fx] ffmpeg missing"; exit 3; }
SPEED=0.375
SEQS=()
for a in "$@"; do
  case "$a" in
    --speed=*) SPEED="${a#--speed=}" ;;
    *) SEQS+=("$a") ;;
  esac
done
if [ "${#SEQS[@]}" -eq 0 ]; then
  mapfile -t SEQS < <(python3 -c "import json;print('\n'.join(json.load(open('data/vfx_sequences.json'))['sequences']))")
fi
# Sandboxed user:// (this runs the project, so it would otherwise resolve to his live profile) and
# his pads hidden: nothing here reads input, and a stray press must not reach the run.
_XDG="$PWD/tmp/fx_xdg"; mkdir -p "$_XDG" tmp/fx
JAIL=()
if command -v bwrap >/dev/null && bwrap --dev-bind / / --tmpfs /dev/input true 2>/dev/null; then
  JAIL=(bwrap --dev-bind / / --tmpfs /dev/input)
fi
FPS=30
_FAILED=0
for S in "${SEQS[@]}"; do
  D="tmp/fx/$S"; rm -rf "$D"; mkdir -p "$D"
  LOG="tmp/fx/$S.log"
  EC=0
  XDG_DATA_HOME="$_XDG" timeout 300 "${JAIL[@]}" xvfb-run -a -s "-screen 0 1280x720x24" godot --audio-driver Dummy \
    --rendering-driver opengl3 --resolution 1280x720 --fixed-fps "$FPS" --write-movie "$D/f.png" \
    -s tools/fx_clip.gd -- "--seq=$S" "--speed=$SPEED" > "$LOG" 2>&1 || EC=$?
  command grep -a -E '^\[FXCLIP\]|ERROR' "$LOG" || true
  N=$(find "$D" -name 'f*.png' | wc -l)
  if [ "$EC" -ne 0 ] || [ "$N" -lt 10 ]; then
    echo "[fx] $S FAILED (exit $EC, $N frames) — $LOG" >&2; _FAILED=1; continue
  fi
  # A clip whose frames are all one image depicts nothing; refuse it rather than ship it.
  UNIQ=$(find "$D" -name 'f*.png' -print0 | xargs -0 md5sum | awk '{print $1}' | sort -u | wc -l)
  if [ "$UNIQ" -lt 5 ]; then
    echo "[fx] $S BLOCKED: $N frames but only $UNIQ distinct" >&2; _FAILED=1; continue
  fi
  ffmpeg -loglevel error -y -framerate "$FPS" -i "$D/f%08d.png" -c:v libx264 -pix_fmt yuv420p -crf 18 "tmp/fx/$S.mp4"
  ffmpeg -loglevel error -y -framerate "$FPS" -i "$D/f%08d.png" \
    -vf "fps=$FPS,scale=640:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=192[p];[b][p]paletteuse=dither=sierra2_4a" "tmp/fx/$S.gif"
  echo "[fx] $S: $N frames ($UNIQ distinct) -> tmp/fx/$S.mp4 tmp/fx/$S.gif"
done
exit "$_FAILED"
