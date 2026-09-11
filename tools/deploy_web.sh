#!/usr/bin/env bash
# deploy_web.sh — THE canonical web deploy. Every deploy goes through
# this script; ad-hoc butler pushes are how the 2026-07-03 226 MB pck
# slipped past itch.io's 200 MB HTML5-embed limit unnoticed.
#
# Size strategy: export_presets.cfg exclude_filter diets the pck
# losslessly (sprite-pipeline intermediates + W4-W6 music, which has a
# procedural fallback). The old in-place 64k/quantize mangling is gone.
#
# Usage:
#   tools/deploy_web.sh [version-tag]              build + verify only  (DEFAULT, safe)
#   tools/deploy_web.sh --publish [version-tag]    build + verify + butler push
#   (tag defaults to the newest git tag; --gates-only is kept as an alias for the default)
#
# PUBLISHING IS OPT-IN, BY CONSTRUCTION — matching deploy_desktop.sh, which has always
# worked this way. Until 2026-08-22 this script PUBLISHED BY DEFAULT and you had to
# remember --gates-only to avoid it, while its sibling refused to publish unless you
# passed --publish. Two scripts in one lane, opposite defaults, and the dangerous one was
# the one whose header said "THE canonical web deploy". Forgetting a flag must never be
# the thing that pushes to itch.io; struktured's standing rule is that a publish needs
# explicit per-deploy approval, and a default that publishes puts that rule one typo away.
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

# --gates-only runs every LOCAL gate and stops before anything outward-facing. Parsed before
# anything else so it can never be mistaken for a version tag.
PUBLISH=0
ARGS=()
for a in "$@"; do
	case "$a" in
		--publish)    PUBLISH=1 ;;
		--gates-only) : ;;   # now the default; kept so existing invocations keep working
		-*) echo "usage: tools/deploy_web.sh [--publish] [version-tag]" >&2; exit 2 ;;
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

# ── version identity ─────────────────────────────────────────────────────────
# The label this build publishes under and the version it will SHOW A PLAYER must agree.
# v3.33.247-alpha shipped to all three channels on 2026-09-09 with Version.gd still reading
# 3.33.246-alpha — a tools-only re-cut whose semver bump was missed. Nothing in this chain
# looked, so it published three times. The fold's test_version_display_regression protects
# the REPOSITORY at merge time; this protects the PUBLISH, and a tag can be cut and pushed
# between those two moments — which is exactly what happened.
#
# First gate deliberately: it costs milliseconds and the alternative is finding out after a
# 15-minute build, or not at all. Blocks on mismatch AND on any failure to read the version;
# an unreadable version is never a matching one.
if [ -x tools/check_version_matches_tag.sh ]; then
    ./tools/check_version_matches_tag.sh "$VERSION" || exit 5
else
    echo "BLOCKED: tools/check_version_matches_tag.sh missing — refusing to publish a label" >&2
    echo "        nothing has checked against the build's own version string." >&2
    exit 5
fi
ITCH_TARGET="struktured/cowardly-irregular:web"
PCK_LIMIT=199000000   # itch refuses HTML5 embeds with any file >= 200 MB
PCK_WARN=180000000    # early-warning band: plan the next diet before it bites
# Overridable so the post-push confirmation path is testable without touching itch,
# matching deploy_desktop.sh.
BUTLER_BIN="${BUTLER_BIN:-$(command -v butler || echo ./butler-bin/butler)}"

echo "[deploy] target: $VERSION  publish=${PUBLISH}"

# IMPORT PREWARM. A fresh worktree has no .godot cache, so res://test/unit/* resolves to nothing
# and GUT runs ZERO tests while exiting 0 (cowir-sfx/cowir-ai/cowir-story, 2026-07-29). This script
# had no prewarm, so deploying from a fresh checkout made gate 1 vacuous. Cheap and idempotent.
echo "[deploy] gate 0/4: import prewarm (a fresh worktree runs NOTHING and exits 0)"
#
# ⚠️ THIS PREWARM LEAVES A .recovery_mode_lock IN HIS REAL USER DATA. Measured 2026-08-22
# under this exact command string, sandboxed XDG, pre-state recorded before each run:
#     run 1 (dir absent)   EC=0 · 13 lines · dir created · lock 0
#     run 2 (dir present)  EC=0 · 13 lines ·               lock 1
# @cowir-controller's conjunction, replicated by three lanes: an EDITOR-CLASS invocation
# plus a PRE-EXISTING project user-data dir. `--import` is editor-class — godot's own help
# marks it `E` and says "Starts the editor" — and `--headless` means no WINDOW, not
# not-the-editor. His dir has existed for months, so every deploy satisfies both halves.
#
# It is inert for the GAME (0 consumers of recovery_mode in src/; CONTROL: 139 files carry
# `func _ready`, so the scan reads the tree) and 0 bytes on disk. The cost is editor-side:
# `--recovery-mode` "disables tool scripts, editor plugins, GDExtension addons", and the
# lock is what makes the editor offer it on his next open. A deploy should not change how
# his editor starts.
#
# gate 1's snapshot net covers this file, but it runs AFTER this line — so it captures the
# lock we just made as pre-existing state and faithfully RESTORES it. The net preserves the
# debris; it cannot remove it. Hence an explicit before/after here.
#
# ONLY removed if THIS command created it. A lock he already had is his — he may have hit a
# real startup crash and want recovery mode — so an unconditional `rm` would be a different
# bug wearing a cleanup.
_UD="${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/Cowardly Irregular"
_LOCK="$_UD/.recovery_mode_lock"
_LOCK_PRE=0; [ -e "$_LOCK" ] && _LOCK_PRE=1
#
# ✅ PREVENTION, added after the cleanup below: sandbox XDG for THIS invocation (a gitignored
# repo-local dir, reused across deploys so the sandbox stays warm) so the lock
# is never written to his data at all. Measured in a fresh worktree (no .godot):
#     ARM A  no import         run_tests.sh EC=3 "NO TESTS RAN — no Totals block"
#     ARM B  SANDBOXED import  EC=0 · 6510 lines · project .godot created (5 entries)
#     ARM C  same test after B EC=0 · Scripts 1 · Tests 1 · Passing 1     ✅ prewarm intact
#     his real lock mtime, before and after B and C: 17:39:14.803 — BYTE-IDENTICAL, untouched
# The import cache lives in res://.godot — in the PROJECT — so relocating XDG_DATA_HOME
# costs the prewarm nothing. ARM A/C is the pair that matters: it shows the prewarm's
# PURPOSE survives, not merely that the command exits 0.
#
# ⛔ DO NOT extend this env var to gate 2. XDG_DATA_HOME relocates the WHOLE godot data
# root, and export templates live at ~/.local/share/godot/export_templates/4.4.1.stable.
# Measured: a sandboxed `--export-release "Web"` fails EC=1 "No export template found at
# the expected path"; the unsandboxed control emits no such line. Sandbox the PREWARM,
# never the EXPORT.
mkdir -p tmp/prewarm_xdg
XDG_DATA_HOME="$PWD/tmp/prewarm_xdg" godot --headless --audio-driver Dummy --import --quit >/dev/null 2>&1 || true
if [ "$_LOCK_PRE" -eq 0 ] && [ -e "$_LOCK" ]; then
  rm -f "$_LOCK"
  echo "[deploy] gate 0: removed the .recovery_mode_lock this prewarm created (none before)"
fi

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
# `|| true` here discarded the audit's exit code entirely. That script exits 2 with
# "BLOCKED: parsed 0 patterns — the parse is wrong, not the config", precisely because a
# zero-pattern parse would otherwise read as "no dead patterns" — and its own comment says
# so: "the vacuous-pass shape this script exists to prevent elsewhere." The caller then
# threw that away, so the one signal meaning THE AUDIT DID NOT RUN was indistinguishable
# from a clean audit. Measured 2026-08-22: a config with every exclude_filter removed
# exits 2, and with `|| true` the deploy proceeded as if gate 0 had passed.
# EC 2 = the instrument could not measure. On a PUBLISH path that blocks: you do not ship
# when a safety check was unable to run. EC 0 with warnings on stderr stays non-blocking —
# a preset with no exclude_filter is loud but the pck size gate catches its consequence.
./tools/check_exclude_patterns.sh; _PAT_EC=$?
if [ "$_PAT_EC" -eq 2 ]; then
  echo "[deploy] BLOCKED: the exclude-pattern audit could not run (exit 2). Not shipping" >&2
  echo "         on an unaudited exclude_filter — fix the parse or the config first." >&2
  exit 2
fi

# TREE IDENTITY — see deploy_desktop.sh for the measured gap this closes. Web has the
# same shape: gate 1 reads src/ at T, the staged export reads it at T+minutes, and nothing
# connected them. Worse here, because make_web_stage.sh copies the tree into tmp/web_stage
# — so a mid-run edit is captured into the stage silently.
_tree_id() { printf '%s %s' "$(git rev-parse HEAD)" "$(git status --porcelain | sort | md5sum | cut -d' ' -f1)"; }
GATE_TREE_ID="$(_tree_id)"

# See tools/tag_gate_evidence.sh for why a skip demands positive proof and why an
# unrecognised verdict must fall through to RUN. Same contract as deploy_desktop.sh.
# The suite, when it runs, runs SANDBOXED: run_tests.sh's net restores settings.json and
# autobattle/ on whatever user:// it is pointed at, and pointing it at struktured's live
# profile silently reverted settings he changed mid-deploy.
# SCOPED TO THE SUITE, NEVER EXPORTED GLOBALLY. Godot's export templates live at
# ~/.local/share/godot/export_templates/4.4.1.stable — under XDG_DATA_HOME — so a global
# export here would redirect gate 2's --export-release to a sandbox holding no templates.
# Verified 2026-09-07: templates present at the real path, absent in tmp/gate_xdg.
_GATE_XDG="$PWD/tmp/gate_xdg"
mkdir -p "$_GATE_XDG"
_SUITE_STAMP="tmp/suite_ok_$(printf '%s' "$GATE_TREE_ID" | md5sum | cut -d' ' -f1)"

echo "[deploy] gate 1/4: unit suite"
_EVIDENCE="$(./tools/tag_gate_evidence.sh "${VERSION}" 2>/dev/null)"
case "${_EVIDENCE}" in
  "VERDICT=SKIP "*)
    echo "[deploy] gate 1: SKIPPED — ${_EVIDENCE#VERDICT=SKIP }"
    ;;
  *)
    if [ -f "$_SUITE_STAMP" ]; then
      echo "[deploy] gate 1: already run for this exact tree by an earlier chain ($(cat "$_SUITE_STAMP"))"
    else
      [ -n "${_EVIDENCE}" ] && echo "[deploy] gate 1: running the suite — ${_EVIDENCE#VERDICT=RUN }"
      if ! XDG_DATA_HOME="$_GATE_XDG" ./tools/gate.sh tmp/deploy_suite.log; then
        cp tmp/deploy_suite.log tmp/deploy_suite.attempt1.log
        echo "[deploy] suite attempt 1 did not pass the gate — retrying once (physics-timing flake?)"
        if ! XDG_DATA_HOME="$_GATE_XDG" ./tools/gate.sh tmp/deploy_suite.log; then
          echo "[deploy] BLOCKED: gate refused the suite on retry — see tmp/deploy_suite.log (+ attempt1)" >&2
          grep -E "^GATE:|^exit=|^scope:" tmp/deploy_suite.log >&2 || true
          grep -B12 "\[Failed\]" tmp/deploy_suite.log | grep -E "^res://test" | sort -u >&2 || true
          exit 1
        fi
        echo "[deploy] suite passed the gate on retry — flake confirmed"
      fi
      echo "web $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$_SUITE_STAMP"
    fi
    ;;
esac

# 1b is NOT covered by the tag marker — that vouches for the unit corpus (test/unit), and
# test/isolated is a separate, deliberately tiny suite. It stays unconditional: it costs
# seconds, and a skip here would rest on evidence that never described it.
echo "[deploy] gate 1b: movement-isolation suite (own process — suite-order contamination quarantine 2026-07-15)"
# Same delegation. test/isolated holds very few files, so an emptied directory would have reported
# green forever under the old [Failed] count — gate.sh's scripts-run == on-disk check catches that.
if ! XDG_DATA_HOME="$_GATE_XDG" ./tools/gate.sh tmp/deploy_isolated.log --isolated; then
  echo "[deploy] BLOCKED: gate refused the isolated suite — see tmp/deploy_isolated.log" >&2
  grep -E "^GATE:|^exit=|^scope:" tmp/deploy_isolated.log >&2 || true
  exit 1
fi

GATE_TREE_ID_NOW="$(_tree_id)"
if [ "$GATE_TREE_ID_NOW" != "$GATE_TREE_ID" ]; then
  echo "[deploy] BLOCKED: the working tree CHANGED between the suite gate and the export." >&2
  echo "        at gate 1: ${GATE_TREE_ID}" >&2
  echo "        now:       ${GATE_TREE_ID_NOW}" >&2
  echo "        The stage is built FROM the working tree, so what would ship is not what" >&2
  echo "        gate 1 tested. Re-run from a quiescent tree." >&2
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
# SANDBOXED PROFILE. Gate 3b on the desktop chain has isolated its combat smoke since it was
# written (deploy_desktop.sh: HOME="$SMOKE_HOME"); this gate never did, and the gate-1 hardening
# of 2026-09-07 fixed the suite and stopped there — so a second writer kept running against
# struktured's live user:// on every web deploy. Measured 2026-09-09: 26 smoke screenshots sitting
# in his real profile under app_userdata/Cowardly Irregular/smoke/, one batch per deploy.
#
# TWO reasons, and the second is the one that makes this a correctness fix rather than tidiness:
#
#  (a) DATA. The smoke boots the real game and fights real battles. Nothing here nets or restores
#      user://, and saves/ is not protected by the suite's exclusion because the suite is not what
#      is running. Whatever it writes, stays.
#
#  (b) DETERMINISM. Godot loads settings.json at startup, so this gate currently inherits the
#      OPERATOR'S PERSONAL SETTINGS — his live profile carries battle_speed_index=2,
#      default_battle_speed=0.25, text_speed=fast. A gate whose result depends on who is running it
#      and how they like their battle speed is not a gate; it cannot be reproduced on another box
#      or in CI. A sandboxed profile means the smoke always tests DEFAULTS, which is what a new
#      player gets.
#
# Safe by inspection, checked before changing it: the smoke READS nothing from user:// (no
# SaveSystem, no has_save, no load_game anywhere in GameLoop.gd:414-610) and only WRITES
# user://smoke/<name>.png — and nothing downstream in this chain reads those shots back.
#
# XDG_DATA_HOME rather than HOME: it is the minimal redirect that moves user://, verified in both
# directions 2026-09-07 (sandboxed -> resolves inside the sandbox, bare -> his real profile). Safe
# HERE because this runs the project directly; it must NEVER wrap gate 2, whose --export-release
# needs the templates that live under the real XDG_DATA_HOME (see the ⛔ note above).
_SMOKE_XDG="$PWD/tmp/smoke_xdg"
mkdir -p "$_SMOKE_XDG"
SMOKE_CMD=(env "XDG_DATA_HOME=$_SMOKE_XDG" xvfb-run -a timeout 300 godot --rendering-driver opengl3 --audio-driver Dummy -- --render-smoke)
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
if [ "$PUBLISH" != "1" ]; then
  echo "[deploy] gate 6/6: SKIPPED — ALL GATES PASSED for ${VERSION}. Nothing pushed."
  echo "[deploy] build is in builds/web/ — publishing needs struktured's explicit approval."
  echo "[deploy] to publish: tools/deploy_web.sh --publish ${VERSION}"
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
# ── post-push confirmation: BOUNDED, and advisory ───────────────────────────
# This was `until … ; do sleep 8; done` — an UNBOUNDED wait. If the version never registered,
# the web chain hung forever: no timeout, no diagnosis, and publish_all blocked behind it
# indefinitely. deploy_desktop.sh's own comment recorded this ("deploy_web.sh's equivalent
# loop has no timeout"), and the asymmetry survived because the desktop side was the one that
# had recently misbehaved.
#
# An infinite hang is the worst of the three possible failures here. A RED at least says
# something; this said nothing and stopped the batch by never returning — and it is the
# quietest way for an hourly publish cadence to stop, because absence is what you notice last.
#
# Bounded to the same budget as the desktop chain, and ADVISORY for the same reason: the push
# itself is fatal and already covered by `set -euo pipefail` above; the authoritative check is
# store-wide and runs in publish_all after the last channel.
CONFIRM_BUDGET="${CONFIRM_BUDGET:-900}"
CONFIRMED=0
_waited=0
while [ "$_waited" -lt "$CONFIRM_BUDGET" ]; do
    if "${BUTLER_BIN}" status "${ITCH_TARGET}" 2>/dev/null | grep -q "${VERSION}"; then
        CONFIRMED=1; break
    fi
    sleep 8; _waited=$((_waited+8))
done

if [ "$CONFIRMED" -eq 1 ]; then
    # Witness the VERSION, not the channel name. The old line here was `status | grep web`,
    # which selects a row by CHANNEL — so the line a human reads as proof looks identical for
    # any version on that channel.
    #
    # Being precise about what that was and wasn't, because I first wrote it down as worse
    # than it is: it was NOT a false outcome. The `until` loop above it had already matched
    # the VERSION, so by the time `grep web` ran the build genuinely had landed. It was a WEAK
    # WITNESS — correct conclusion, evidence that cannot vary with it — not the
    # precondition-for-outcome substitution deploy_desktop.sh had. Measured: with a stub whose
    # status names the channel but a DIFFERENT version, the old form never reaches this line
    # at all; it hangs in the loop above (exit 124 at a 25s cutoff). The hang is the defect.
    "${BUTLER_BIN}" status "${ITCH_TARGET}" 2>&1 | grep -a "${VERSION}" || true
    echo "[deploy] LIVE: ${VERSION} — https://struktured.itch.io/cowardly-irregular"
else
    echo "[deploy] PUSHED, NOT YET CONFIRMED: ${VERSION} has not appeared in butler status" >&2
    echo "         after ${CONFIRM_BUDGET}s. butler reported the push succeeded; itch may still" >&2
    echo "         be processing. NOT failing — the authoritative check is tools/store_status.sh" >&2
    echo "         across all three channels, which publish_all asserts after the last one." >&2
    echo "         Verify before assuming it shipped: https://itch.io/dashboard" >&2
    "${BUTLER_BIN}" status "${ITCH_TARGET}" >&2 || true
fi
