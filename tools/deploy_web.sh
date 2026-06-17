#!/usr/bin/env bash
# deploy_web.sh — build the web export with reduced assets and push to itch.io
#
# Compresses music (64 kbps mono OGG) and monster sprites (64-color quant)
# in-place via tmp copies, exports, pushes via butler, then restores the
# originals via `git checkout`. The source tree on disk is unchanged after
# the script returns; only the web bundle ships compressed assets.
#
# Usage: tools/deploy_web.sh [version-tag]
# If no tag is supplied, the latest git tag is used.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

BUTLER="${BUTLER:-$HOME/.local/bin/butler}"
ITCH_TARGET="struktured/cowardly-irregular:web"
PCK_LIMIT_MIB=200

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  VERSION=$(git tag --sort=-creatordate | head -1)
fi
echo "[deploy_web] target version: $VERSION"

restore_assets() {
  echo "[deploy_web] restoring source assets via git checkout..."
  git checkout HEAD -- assets/audio/music/ assets/sprites/monsters/ 2>&1 | tail -3 || true
}
trap restore_assets EXIT

echo "[deploy_web] compressing music to 64 kbps mono OGG..."
music_compressed=0
for f in assets/audio/music/*.ogg; do
  info=$(ffprobe -v error -show_entries stream=bit_rate,channels -of csv=p=0 "$f" 2>/dev/null)
  br=$(echo "$info" | cut -d, -f2)
  ch=$(echo "$info" | cut -d, -f1)
  if [ "$br" = "64000" ] && [ "$ch" = "1" ]; then
    continue
  fi
  # ffmpeg infers output format from the file extension; keep ".ogg" on
  # the tmp name so libvorbis is selected (a bare ".tmp" suffix fails
  # with "Unable to choose an output format").
  tmp="${f%.ogg}.tmp.ogg"
  ffmpeg -y -loglevel error -i "$f" -ac 1 -b:a 64k -map_metadata -1 "$tmp" && mv "$tmp" "$f"
  music_compressed=$((music_compressed + 1))
done
echo "[deploy_web]   $music_compressed file(s) compressed"

echo "[deploy_web] quantizing monster sprites (iterative 256→128→64 colors)..."
# Empirically (interactive deploy 2026-06-16) the iterative reduction
# produces a tighter final palette than a single-pass to 64 — final pck
# came in ~17 MiB smaller. Each pass refines the previous output.
sprites_quantized=0
for f in assets/sprites/monsters/*.png; do
  for colors in 256 128 64; do
    magick "$f" -strip -colors "$colors" -dither FloydSteinberg "${f}.tmp"
    optipng -o2 -quiet "${f}.tmp"
    mv "${f}.tmp" "$f"
  done
  sprites_quantized=$((sprites_quantized + 1))
done
echo "[deploy_web]   $sprites_quantized sprite(s) quantized"

echo "[deploy_web] building Godot web export..."
mkdir -p builds/web
godot --headless --export-release "Web" builds/web/index.html 2>&1 | tail -3

PCK_SIZE_BYTES=$(stat -c%s builds/web/index.pck)
PCK_SIZE_MIB=$((PCK_SIZE_BYTES / 1024 / 1024))
echo "[deploy_web] index.pck size: ${PCK_SIZE_MIB} MiB"

if [ "$PCK_SIZE_MIB" -ge "$PCK_LIMIT_MIB" ]; then
  echo "[deploy_web] ERROR: pck (${PCK_SIZE_MIB} MiB) at or over itch HTML5 per-file limit (~${PCK_LIMIT_MIB} MiB)" >&2
  echo "[deploy_web] refusing to push. Trim further (lower music bitrate, more aggressive sprite quant, or exclude assets) and retry." >&2
  exit 2
fi

echo "[deploy_web] pushing to $ITCH_TARGET (userversion $VERSION)..."
"$BUTLER" push builds/web/ "$ITCH_TARGET" --userversion "$VERSION"

echo "[deploy_web] done. Verify at https://struktured.itch.io/cowardly-irregular"
