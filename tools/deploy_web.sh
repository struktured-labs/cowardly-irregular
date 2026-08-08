#!/usr/bin/env bash
# deploy_web.sh — THE canonical web deploy. Every deploy goes through
# this script; ad-hoc butler pushes are how the 2026-07-03 226 MB pck
# slipped past itch.io's 200 MB HTML5-embed limit unnoticed.
#
# Size strategy: export_presets.cfg exclude_filter diets the pck
# losslessly (sprite-pipeline intermediates + W4-W6 music, which has a
# procedural fallback). The old in-place 64k/quantize mangling is gone.
#
# Usage: tools/deploy_web.sh [version-tag] [--gates-only]   (tag defaults to the newest git tag)
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

# --gates-only runs every LOCAL gate and stops before anything outward-facing. Parsed before
# anything else so it can never be mistaken for a version tag.
GATES_ONLY=0
ARGS=()
for a in "$@"; do
	case "$a" in
		--gates-only) GATES_ONLY=1 ;;
		-*) echo "usage: tools/deploy_web.sh [version-tag] [--gates-only]" >&2; exit 2 ;;
		*) ARGS+=("$a") ;;
	esac
done

# NO PIPE. `git tag --sort=-creatordate | head -1` under `set -o pipefail` DIES: head closes the
# pipe after one line, git tag takes SIGPIPE, pipefail propagates 141, and set -e kills the script
# before it prints anything. Measured 2026-07-30 — the documented default path exited 141 in
# silence, which reads as "the script did nothing" rather than as a failure.
# It is LOAD-DEPENDENT and was correct when written: with few tags git finishes writing before head
# exits. This repo has 507, well past the pipe buffer, so it broke as tags accumulated and nobody
# noticed because every real deploy passes an explicit tag.
if [ "${#ARGS[@]}" -gt 0 ]; then
	VERSION="${ARGS[0]}"
else
	VERSION="$(git for-each-ref --sort=-creatordate --count=1 --format='%(refname:short)' refs/tags)"
fi
[ -n "$VERSION" ] || { echo "deploy_web.sh: no version tag given and no tags in the repo" >&2; exit 2; }
ITCH_TARGET="struktured/cowardly-irregular:web"
PCK_LIMIT=199000000   # itch refuses HTML5 embeds with any file >= 200 MB
PCK_WARN=180000000    # early-warning band: plan the next diet before it bites
BUTLER_BIN="$(command -v butler || echo ./butler-bin/butler)"

echo "[deploy] target: $VERSION"

# IMPORT PREWARM. A fresh worktree has no .godot cache, so res://test/unit/* resolves to nothing
# and GUT runs ZERO tests while exiting 0 (cowir-sfx/cowir-ai/cowir-story, 2026-07-29). This script
# had no prewarm, so deploying from a fresh checkout made gate 1 vacuous. Cheap and idempotent.
echo "[deploy] gate 0/4: import prewarm (a fresh worktree runs NOTHING and exits 0)"
godot --headless --audio-driver Dummy --import --quit >/dev/null 2>&1 || true

# GATE 1 DELEGATES TO tools/gate.sh AND CONSULTS ITS EXIT CODE.
#
# It used to read `grep -cE "[Failed]"` with `|| true`, which defused the `set -euo pipefail`
# above and made this the weakest gate in the project — guarding a public butler push
# (cowir-deploy msg-3720). Measured against its own command shape with a nonexistent -gdir:
# godot exit 0, [Failed] count 0, Totals blocks 0 — THE GATE PASSED ON A RUN THAT DID NOTHING.
# It was also blind to [Risky] (a test dying in setup never scores [Failed]; 8 such tests existed
# on main this session), and the count itself is a boolean, not a cardinal — it equals 2x failing
# ASSERTS, so it could never be reported as "N failures" honestly.
#
# gate.sh already carries every instrument: exit code + Failing N agreement, a Totals-present
# floor, scripts-run == test-files-on-disk, load-failure detection, and asserted-nothing naming.
# Re-rolling a weaker version inside the deploy script is what produced the hole, so this deletes
# the check rather than hardening it.
#
# Retry once: 2026-07-14 saw test_movement_isolation.gd fail intermittently under the full suite
# (H-vs-V physics parity asserts diverge in the tens of pixels; passes solo, passes on rerun). A
# real regression fails both tries. First attempt's log kept for diff.
# Non-blocking dead-exclusion report — see deploy_desktop.sh for why it never enforces.
# This matters more on web than desktop: web is the size-capped target, so an exclusion
# that quietly stopped applying eats headroom against itch's 200 MB embed limit.
./tools/check_exclude_patterns.sh || true

echo "[deploy] gate 1/4: unit suite (via tools/gate.sh)"
if ! ./tools/gate.sh tmp/deploy_suite.log; then
  cp tmp/deploy_suite.log tmp/deploy_suite.attempt1.log
  echo "[deploy] suite attempt 1 did not pass the gate — retrying once (physics-timing flake?)"
  if ! ./tools/gate.sh tmp/deploy_suite.log; then
    echo "[deploy] BLOCKED: gate refused the suite on retry — see tmp/deploy_suite.log (+ attempt1)" >&2
    grep -E "^GATE:|^exit=|^scope:" tmp/deploy_suite.log >&2 || true
    grep -B12 "\[Failed\]" tmp/deploy_suite.log | grep -E "^res://test" | sort -u >&2 || true
    exit 1
  fi
  echo "[deploy] suite passed the gate on retry — flake confirmed"
fi

echo "[deploy] gate 1b: movement-isolation suite (own process — suite-order contamination quarantine 2026-07-15)"
# Same delegation. test/isolated holds very few files, so an emptied directory would have reported
# green forever under the old [Failed] count — gate.sh's scripts-run == on-disk check catches that.
if ! ./tools/gate.sh tmp/deploy_isolated.log --isolated; then
  echo "[deploy] BLOCKED: gate refused the isolated suite — see tmp/deploy_isolated.log" >&2
  grep -E "^GATE:|^exit=|^scope:" tmp/deploy_isolated.log >&2 || true
  exit 1
fi

echo "[deploy] gate 2/4: web export"
# STAGED EXPORT, not a direct one. struktured's ruling (2026-07-30): ship the W4-W6
# endings, compress to fit. The web preset excludes 54 ending tracks to stay under
# itch's embed cap; make_web_stage.sh builds a throwaway copy of the project with a
# 48 kbps audio tier swapped in and those exclusions dropped, so the endings ship.
# Measured: 154 tracks at 48k is SMALLER than 98 at 96k, so they cost nothing.
#
# It is a COPY, never a swap. assets/ keeps the 96k masters for desktop and is never
# touched, so a deploy killed mid-run cannot leave lo-fi audio where the masters
# belong — there is no restore step to skip. That matters because a gate crossing a
# harness timeout dies by SIGTERM, which is the normal case here, not the edge case.
#
# WEB_STAGE=0 falls back to the direct export (faster, no endings) for a quick
# non-publishing check. Publishing on that path ships less content than was measured,
# so it is deliberately NOT the default.
mkdir -p builds/web
if [ "${WEB_STAGE:-1}" = "1" ]; then
  ./tools/make_web_stage.sh 48 || {
    echo "[deploy] BLOCKED: staged web build failed — see its own BLOCKED line above." >&2
    echo "        WEB_STAGE=0 exports directly, but ships WITHOUT the W4-W6 endings." >&2
    exit 2; }
  # Downstream gates, both smokes and the butler push all read builds/web. Move the
  # staged artifact there rather than re-pointing five call sites.
  rm -rf builds/web && mkdir -p builds/web
  cp -a tmp/web_stage/builds/web/. builds/web/
  echo "[deploy] staged build in place (48 kbps tier, endings included)"
else
  echo "[deploy] WEB_STAGE=0 — direct export, W4-W6 endings EXCLUDED"
  godot --headless --export-release "Web" builds/web/index.html 2>&1 | tail -3
fi
# An export that reported success and produced nothing would otherwise reach the pck
# gate as a stat error rather than a named failure.
[ -s builds/web/index.pck ] || {
  echo "[deploy] BLOCKED: no index.pck after export — nothing to measure or push." >&2; exit 2; }

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

# --gates-only stops HERE, before anything outward-facing. Every gate above is local: suite,
# export, pck size, render smoke, WASM boot smoke. Verifying that main is shippable is a thing
# people legitimately want, and until now the only way to do it was to read this file to the end
# and confirm the push below wouldn't fire — or hand-roll the sequence. Making the safe path
# supported is cheaper than trusting everyone to check. Publishing still requires struktured's
# explicit per-deploy approval; this flag does not grant it, it removes the reason to skip asking.
if [ "$GATES_ONLY" = "1" ]; then
  echo "[deploy] --gates-only: ALL GATES PASSED for ${VERSION}. Nothing pushed."
  echo "[deploy] build is in builds/web/ — publishing needs struktured's explicit approval."
  exit 0
fi

# Same defect as deploy_desktop.sh carried, same fix — see its comment at VERSION for the
# measurement. This script exports the working tree (or a stage built FROM it), so the tag
# is a label and never the built commit. `-dirty` because a dirty export is reproducible
# from no SHA at all.
BUILD_SHA="$(git rev-parse --short HEAD)"
git diff --quiet HEAD -- 2>/dev/null || BUILD_SHA="${BUILD_SHA}-dirty"
USERVERSION="${VERSION}+${BUILD_SHA}"
echo "[deploy] pushing to ${ITCH_TARGET} (userversion ${USERVERSION})"
echo "[deploy]   tag ${VERSION} is a LABEL; ${BUILD_SHA} is the tree that was exported"
"${BUTLER_BIN}" push builds/web/ "${ITCH_TARGET}" --userversion "${USERVERSION}"
until "${BUTLER_BIN}" status "${ITCH_TARGET}" 2>/dev/null | grep -q "${VERSION}"; do sleep 8; done
"${BUTLER_BIN}" status "${ITCH_TARGET}" | grep web
echo "[deploy] LIVE: ${VERSION} — https://struktured.itch.io/cowardly-irregular"
