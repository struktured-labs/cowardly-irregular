#!/usr/bin/env bash
# Every starter job's quip bubble over its own head, in all six world costumes -> tmp/bubble_anchor/.
# Sandboxed through tools/shot_sandbox.sh; one godot run per world (costumes load at battle start).
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck source=tools/shot_sandbox.sh
. tools/shot_sandbox.sh
_FAILED=0
for W in 1 2 3 4 5 6; do
  shot_sandbox_run tools/bubble_anchor_shots.gd "--world=$W" || { echo "[shot] world $W FAILED" >&2; _FAILED=1; }
  command grep -a '^\[SHOT\]' tmp/bubble_anchor_shots.log || true
done
if command -v ffmpeg >/dev/null && ls tmp/bubble_anchor/w1_*.png >/dev/null 2>&1; then
  for W in 1 2 3 4 5 6; do
    mapfile -t F < <(ls tmp/bubble_anchor/w${W}_*.png 2>/dev/null | sort)
    [ "${#F[@]}" -gt 1 ] || continue
    ARGS=(); for f in "${F[@]}"; do ARGS+=(-i "$f"); done
    ffmpeg -loglevel error -y "${ARGS[@]}" -filter_complex "hstack=${#F[@]}" "tmp/bubble_anchor/row_w$W.png"
  done
  mapfile -t R < <(ls tmp/bubble_anchor/row_w*.png | sort)
  ARGS=(); for f in "${R[@]}"; do ARGS+=(-i "$f"); done
  [ "${#R[@]}" -gt 1 ] && ffmpeg -loglevel error -y "${ARGS[@]}" -filter_complex "vstack=${#R[@]}" tmp/bubble_anchor/all_worlds.png
fi
exit "$_FAILED"
