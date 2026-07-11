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
FAILS=$(godot --headless --audio-driver Dummy -s addons/gut/gut_cmdln.gd -gdir=res://test/unit -gprefix=test_ -gsuffix=.gd -gexit 2>&1 | tee tmp/deploy_suite.log | grep -cE "\[Failed\]") || true
if [ "${FAILS}" != "0" ]; then
  echo "[deploy] BLOCKED: ${FAILS} test failure(s) — see tmp/deploy_suite.log" >&2
  grep -B12 "\[Failed\]" tmp/deploy_suite.log | grep -E "^res://test" | sort -u >&2
  exit 1
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
# Retry once: Xvfb intermittently dies mid-run on this box ("X connection
# broken", 3 distinct steps 2026-07-08/09) — a REAL regression fails twice;
# first attempt's log is kept as deploy_smoke.attempt1.log for comparison.
SMOKE_CMD=(xvfb-run -a timeout 300 godot --rendering-driver opengl3 --audio-driver Dummy -- --render-smoke)
if ! "${SMOKE_CMD[@]}" > tmp/deploy_smoke.log 2>&1; then
  cp tmp/deploy_smoke.log tmp/deploy_smoke.attempt1.log
  echo "[deploy] smoke attempt 1 failed (xvfb flake?) — retrying once"
  if ! "${SMOKE_CMD[@]}" > tmp/deploy_smoke.log 2>&1; then
    echo "[deploy] BLOCKED: render smoke failed TWICE — see tmp/deploy_smoke.log (+ attempt1)" >&2; exit 3
  fi
fi
grep "VERDICT" tmp/deploy_smoke.log

echo "[deploy] gate 5/5: web boot smoke (the ACTUAL WASM build in headless chromium)"
# Retry once: headless chromium occasionally dies mid-run when the box is
# busy (live playtest + export on one GPU, 2026-07-11) — a REAL break fails twice.
if ./tools/web_smoke.sh > tmp/deploy_web_smoke.log 2>&1; then
  grep "WEB-SMOKE" tmp/deploy_web_smoke.log
else
  RC=$?
  if [ "$RC" = "3" ]; then
    echo "[deploy] WARNING: web smoke SKIPPED (no playwright on this machine) — desktop smoke still gated"
  else
    cp tmp/deploy_web_smoke.log tmp/deploy_web_smoke.attempt1.log
    echo "[deploy] web smoke attempt 1 failed (chromium flake?) — retrying once"
    if ./tools/web_smoke.sh > tmp/deploy_web_smoke.log 2>&1; then
      grep "WEB-SMOKE" tmp/deploy_web_smoke.log
    else
      RC=$?
      if [ "$RC" = "3" ]; then
        echo "[deploy] WARNING: web smoke SKIPPED on retry — desktop smoke still gated"
      else
        echo "[deploy] BLOCKED: web build failed to boot in chromium TWICE — see tmp/deploy_web_smoke.log (+ attempt1)" >&2; exit 5
      fi
    fi
  fi
fi

echo "[deploy] pushing to ${ITCH_TARGET} (userversion ${VERSION})"
"${BUTLER_BIN}" push builds/web/ "${ITCH_TARGET}" --userversion "${VERSION}"
until "${BUTLER_BIN}" status "${ITCH_TARGET}" 2>/dev/null | grep -q "${VERSION}"; do sleep 8; done
"${BUTLER_BIN}" status "${ITCH_TARGET}" | grep web
echo "[deploy] LIVE: ${VERSION} — https://struktured.itch.io/cowardly-irregular"
