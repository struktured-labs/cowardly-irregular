#!/usr/bin/env bash
# Clip the victory beat over a real battle: tmp/victory_clip/<label>.mp4 + .gif.
# Usage: tools/victory_clip.sh <label> [--rank=S] [--boss] [--seconds=3.4]
# Sandboxed user:// and pads hidden like tools/fx_clip.sh; --write-movie at a fixed fps, so every run is the same frames.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xvfb-run >/dev/null || { echo "[vclip] xvfb-run missing"; exit 3; }
command -v ffmpeg >/dev/null || { echo "[vclip] ffmpeg missing"; exit 3; }
LABEL="${1:?label}"; shift
_XDG="$PWD/tmp/vclip_xdg"; mkdir -p "$_XDG" tmp/victory_clip
JAIL=()
if command -v bwrap >/dev/null && bwrap --dev-bind / / --tmpfs /dev/input true 2>/dev/null; then
  JAIL=(bwrap --dev-bind / / --tmpfs /dev/input)
fi
FPS=30
D="tmp/victory_clip/$LABEL"; rm -rf "$D"; mkdir -p "$D"
LOG="tmp/victory_clip/$LABEL.log"
EC=0
XDG_DATA_HOME="$_XDG" timeout 300 "${JAIL[@]}" xvfb-run -a -s "-screen 0 1280x720x24" godot --audio-driver Dummy \
  --rendering-driver opengl3 --resolution 1280x720 --fixed-fps "$FPS" --write-movie "$D/f.png" \
  -s tools/victory_clip.gd -- "$@" > "$LOG" 2>&1 || EC=$?
command grep -a -E '^\[VCLIP\]|SCRIPT ERROR|Parse Error' "$LOG" || true
[ -e "$_XDG/godot" ] || { echo "[vclip] BLOCKED: the sandbox at $_XDG is empty, so the redirect did not fire." >&2; exit 4; }
N=$(find "$D" -name 'f*.png' | wc -l)
[ "$EC" -eq 0 ] && [ "$N" -ge 30 ] || { echo "[vclip] $LABEL FAILED (exit $EC, $N frames) - $LOG" >&2; exit 1; }
# The battle's setup frames precede the build; keep the last <seconds> of the run, which is the beat.
KEEP=$(command grep -a '^\[VCLIP\] built' "$LOG" >/dev/null && echo yes || echo no)
[ "$KEEP" = yes ] || { echo "[vclip] $LABEL: no build line in $LOG" >&2; exit 1; }
SECS=$(printf '%s\n' "$@" | sed -n 's/^--seconds=//p'); SECS=${SECS:-3.4}
SKIP=$(python3 -c "print(max(1, $N - int(round($SECS * $FPS))))")
ffmpeg -loglevel error -y -framerate "$FPS" -start_number "$SKIP" -i "$D/f%08d.png" -c:v libx264 -pix_fmt yuv420p -crf 18 "tmp/victory_clip/$LABEL.mp4"
ffmpeg -loglevel error -y -framerate "$FPS" -start_number "$SKIP" -i "$D/f%08d.png" \
  -vf "fps=$FPS,scale=960:-1:flags=neighbor,split[a][b];[a]palettegen=max_colors=192[p];[b][p]paletteuse=dither=none" "tmp/victory_clip/$LABEL.gif"
echo "[vclip] $LABEL: $N frames, clip from $SKIP -> tmp/victory_clip/$LABEL.mp4 .gif"
