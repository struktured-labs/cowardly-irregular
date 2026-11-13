#!/usr/bin/env bash
# Clip a night at the inn in the real inn room, WITH the game's own audio mix: tmp/inn_clip/<label>.mp4 (+ a silent .gif).
# Usage: tools/inn_clip.sh <label> [--seconds=9.5] [--skip_at=<s into the night>]
# The same capture path as tools/demo_capture.sh's segments: Movie Maker writes frames and the engine mix into one AVI on
# game time (no audio sink, no Dummy driver), a sandboxed user://, and the host's pads hidden.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xvfb-run >/dev/null || { echo "[iclip] xvfb-run missing"; exit 3; }
command -v ffmpeg >/dev/null || { echo "[iclip] ffmpeg missing"; exit 3; }
LABEL="${1:?label}"; shift
_XDG="$PWD/tmp/iclip_xdg"; mkdir -p "$_XDG" tmp/inn_clip
JAIL=()
if command -v bwrap >/dev/null && bwrap --dev-bind / / --tmpfs /dev/input true 2>/dev/null; then
  JAIL=(bwrap --dev-bind / / --tmpfs /dev/input)
fi
[ ${#JAIL[@]} -gt 0 ] || { echo "[iclip] BLOCKED: no usable bwrap to hide the host's pads from the capture" >&2; exit 2; }
AVI="tmp/inn_clip/$LABEL.avi"; rm -f "$AVI"
LOG="tmp/inn_clip/$LABEL.log"
EC=0
env -u WAYLAND_DISPLAY XDG_DATA_HOME="$_XDG" "${JAIL[@]}" timeout 300 xvfb-run -a -s "-screen 0 1280x720x24" \
  godot --display-driver x11 --rendering-driver opengl3 --resolution 1280x720 --write-movie "$AVI" --fixed-fps 30 \
  -s tools/inn_clip.gd -- "$@" < /dev/null > "$LOG" 2>&1 || EC=$?
command grep -a -E '^\[ICLIP\]|SCRIPT ERROR|Parse Error' "$LOG" || true
[ -e "$_XDG/godot" ] || { echo "[iclip] BLOCKED: the sandbox at $_XDG is empty, so the redirect did not fire." >&2; exit 4; }
# Not on godot's exit code: on this box a windowed godot under xvfb-run exits 1 even on quit(0) (measured 2026-11-13); the artifacts below are the verdict.
echo "[iclip] $LABEL godot exit $EC (recorded, not judged)"
[ -s "$AVI" ] || { echo "[iclip] $LABEL FAILED: no movie written (exit $EC) - $LOG" >&2; exit 1; }
command grep -a -q '^\[ICLIP\] done' "$LOG" || { echo "[iclip] $LABEL FAILED: the clip script never finished (exit $EC) - $LOG" >&2; exit 1; }
command grep -a -q '^\[ICLIP\] FAIL' "$LOG" && { echo "[iclip] $LABEL FAILED: $(command grep -a '^\[ICLIP\] FAIL' "$LOG" | head -1)" >&2; exit 1; }
command grep -a -q '^\[ICLIP\] built' "$LOG" || { echo "[iclip] $LABEL: no build line in $LOG" >&2; exit 1; }
command grep -a -q '^\[ICLIP\] beat=dawn' "$LOG" || { echo "[iclip] $LABEL FAILED: the night never reached dawn" >&2; exit 1; }
command grep -a -q 'cutscene_playing=false' "$LOG" || { echo "[iclip] $LABEL FAILED: a cutscene was playing over the room" >&2; exit 1; }
PROBE="$(ffprobe -v error -show_entries stream=codec_type -of csv=p=0 "$AVI" | sort -u | tr '\n' ' ')"
case "$PROBE" in *audio*video*) ;; *) echo "[iclip] $LABEL FAILED: the AVI lacks a video or an audio stream ($PROBE)" >&2; exit 1 ;; esac
# The boot and the walk into the room precede the rest; keep the last <seconds> of the run, which is the night.
SECS="9.5"
for a in "$@"; do case "$a" in --seconds=*) SECS="${a#--seconds=}" ;; esac; done
ffmpeg -loglevel error -y -sseof "-$SECS" -i "$AVI" -c:v libx264 -pix_fmt yuv420p -crf 18 -c:a aac -b:a 192k "tmp/inn_clip/$LABEL.mp4"
ffmpeg -loglevel error -y -sseof "-$SECS" -i "$AVI" \
  -vf "fps=30,scale=960:-1:flags=neighbor,split[a][b];[a]palettegen=max_colors=192[p];[b][p]paletteuse=dither=none" "tmp/inn_clip/$LABEL.gif"
echo "[iclip] $LABEL: $(ffprobe -v error -show_entries stream=codec_type -of csv=p=0 "tmp/inn_clip/$LABEL.mp4" | tr '\n' ' ')$(ffprobe -v error -show_entries format=duration -of csv=p=0 "tmp/inn_clip/$LABEL.mp4")s -> tmp/inn_clip/$LABEL.mp4"
