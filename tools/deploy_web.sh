#!/usr/bin/env bash
# deploy_web.sh — THE canonical web deploy. Every deploy goes through
# this script; ad-hoc butler pushes are how the 2026-07-03 226 MB pck
# slipped past itch.io's 200 MB HTML5-embed limit unnoticed.
#
# Size strategy: export_presets.cfg exclude_filter diets the pck
# losslessly (sprite-pipeline intermediates + W4-W6 music, which has a
# procedural fallback). The old in-place 64k/quantize mangling is gone.
#
# Usage: tools/deploy_web.sh [version-tag]   (defaults to latest git tag)
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

VERSION="${1:-$(git tag --sort=-creatordate | head -1)}"
ITCH_TARGET="struktured/cowardly-irregular:web"
PCK_LIMIT=199000000   # itch refuses HTML5 embeds with any file >= 200 MB
PCK_WARN=180000000    # early-warning band: plan the next diet before it bites
BUTLER_BIN="$(command -v butler || echo ./butler-bin/butler)"

echo "[deploy] target: $VERSION"

echo "[deploy] gate 1/4: unit suite"
FAILS=$(godot --headless --audio-driver Dummy -s addons/gut/gut_cmdln.gd -gdir=res://test/unit -gprefix=test_ -gsuffix=.gd -gexit 2>&1 | grep -cE "\[Failed\]") || true
if [ "${FAILS}" != "0" ]; then
  echo "[deploy] BLOCKED: ${FAILS} test failure(s)" >&2; exit 1
fi

echo "[deploy] gate 2/4: web export"
mkdir -p builds/web
godot --headless --export-release "Web" builds/web/index.html 2>&1 | tail -3

echo "[deploy] gate 3/4: pck size"
PCK=$(stat -c%s builds/web/index.pck)
echo "[deploy] index.pck: $((PCK / 1048576)) MB"
if [ "${PCK}" -ge "${PCK_LIMIT}" ]; then
  echo "[deploy] BLOCKED: pck >= 200 MB — itch will refuse the HTML5 embed." >&2
  echo "[deploy] check export_presets.cfg exclude_filter and recent large assets." >&2
  exit 2
fi
if [ "${PCK}" -ge "${PCK_WARN}" ]; then
  echo "[deploy] WARNING: pck within 20 MB of the itch limit — plan the next diet now."
fi

echo "[deploy] gate 4/4: render smoke"
mkdir -p tmp
# --audio-driver Dummy: xvfb fakes the DISPLAY but not audio — without it the
# smoke blasts game music through the user's speakers (2026-07-08 complaint).
if ! xvfb-run -a timeout 220 godot --rendering-driver opengl3 --audio-driver Dummy -- --render-smoke > tmp/deploy_smoke.log 2>&1; then
  echo "[deploy] BLOCKED: render smoke failed — see tmp/deploy_smoke.log" >&2; exit 3
fi
grep "VERDICT" tmp/deploy_smoke.log

echo "[deploy] pushing to ${ITCH_TARGET} (userversion ${VERSION})"
"${BUTLER_BIN}" push builds/web/ "${ITCH_TARGET}" --userversion "${VERSION}"
until "${BUTLER_BIN}" status "${ITCH_TARGET}" 2>/dev/null | grep -q "${VERSION}"; do sleep 8; done
"${BUTLER_BIN}" status "${ITCH_TARGET}" | grep web
echo "[deploy] LIVE: ${VERSION} — https://struktured.itch.io/cowardly-irregular"
