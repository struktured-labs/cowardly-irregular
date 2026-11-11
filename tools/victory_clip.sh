#!/usr/bin/env bash
# Clip the victory beat over a real battle, WITH the game's own audio mix: tmp/victory_clip/<label>.mp4 (+ a silent .gif).
# Usage: tools/victory_clip.sh <label> [--rank=S] [--boss] [--seconds=3.4]
# The same capture path as tools/demo_capture.sh's segments: Movie Maker writes frames and the engine mix into one AVI on
# game time (no audio sink, no Dummy driver), a sandboxed user://, and the host's pads hidden.
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
[ ${#JAIL[@]} -gt 0 ] || { echo "[vclip] BLOCKED: no usable bwrap to hide the host's pads from the capture" >&2; exit 2; }
AVI="tmp/victory_clip/$LABEL.avi"; rm -f "$AVI"
LOG="tmp/victory_clip/$LABEL.log"
EC=0
env -u WAYLAND_DISPLAY XDG_DATA_HOME="$_XDG" "${JAIL[@]}" timeout 300 xvfb-run -a -s "-screen 0 1280x720x24" \
  godot --display-driver x11 --rendering-driver opengl3 --resolution 1280x720 --write-movie "$AVI" --fixed-fps 30 \
  -s tools/victory_clip.gd -- "$@" < /dev/null > "$LOG" 2>&1 || EC=$?
command grep -a -E '^\[VCLIP\]|SCRIPT ERROR|Parse Error' "$LOG" || true
[ -e "$_XDG/godot" ] || { echo "[vclip] BLOCKED: the sandbox at $_XDG is empty, so the redirect did not fire." >&2; exit 4; }
[ "$EC" -eq 0 ] && [ -s "$AVI" ] || { echo "[vclip] $LABEL FAILED (exit $EC) - $LOG" >&2; exit 1; }
command grep -a -q '^\[VCLIP\] built' "$LOG" || { echo "[vclip] $LABEL: no build line in $LOG" >&2; exit 1; }
# The clip is for judging the beat WITH its music: refuse one whose overlay was built over anything but a victory bed or the stinger.
command grep -a -qE '^\[VCLIP\] under=(victory|stinger_boss_defeated)' "$LOG" || { echo "[vclip] $LABEL FAILED: no victory music under the letters ($(command grep -a '^\[VCLIP\] under=' "$LOG"))" >&2; exit 1; }
PROBE="$(ffprobe -v error -show_entries stream=codec_type -of csv=p=0 "$AVI" | sort -u | tr '\n' ' ')"
case "$PROBE" in *audio*video*) ;; *) echo "[vclip] $LABEL FAILED: the AVI lacks a video or an audio stream ($PROBE)" >&2; exit 1 ;; esac
# The battle's setup precedes the build; keep the last <seconds> of the run, which is the beat.
SECS="3.4"
for a in "$@"; do case "$a" in --seconds=*) SECS="${a#--seconds=}" ;; esac; done
ffmpeg -loglevel error -y -sseof "-$SECS" -i "$AVI" -c:v libx264 -pix_fmt yuv420p -crf 18 -c:a aac -b:a 192k "tmp/victory_clip/$LABEL.mp4"
ffmpeg -loglevel error -y -sseof "-$SECS" -i "$AVI" \
  -vf "fps=30,scale=960:-1:flags=neighbor,split[a][b];[a]palettegen=max_colors=192[p];[b][p]paletteuse=dither=none" "tmp/victory_clip/$LABEL.gif"
echo "[vclip] $LABEL: $(ffprobe -v error -show_entries stream=codec_type -of csv=p=0 "tmp/victory_clip/$LABEL.mp4" | tr '\n' ' ')$(ffprobe -v error -show_entries format=duration -of csv=p=0 "tmp/victory_clip/$LABEL.mp4")s -> tmp/victory_clip/$LABEL.mp4"
