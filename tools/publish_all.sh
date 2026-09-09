#!/usr/bin/env bash
# Publish one tag to linux, windows and web, in that order, with the checks the deploy lane
# learned the hard way on 2026-09-09.
#
# WHY THIS EXISTS
#   Ten publishes were driven by hand that day, each an ad-hoc `for ch in linux windows`
#   loop retyped from memory. One of those retypings shipped a real defect: the guard
#   `[ $EC -ne 0 ] && { break; }` as the last statement of a loop makes the compound's status
#   the script's, so EC=0 reported 1 and — the direction that matters — **EC=1 reported 0**.
#   A genuinely failed channel would have arrived as "completed successfully" and the next
#   channel would have published straight over it. A publish routine repeated ten times is a
#   script; keeping it in muscle memory is how that got in.
#
# WHAT IT ENFORCES, and every line of it is a thing that went wrong once:
#   1. tag evidence          tools/tag_gate_evidence.sh must return the SKIP token, or the
#                            suite runs sandboxed inside the chains as normal.
#   2. version identity      the build's SEMVER must equal the label. v3.33.247-alpha shipped
#                            to all three channels reading 3.33.246-alpha on its title screen.
#   3. prebuilt caches       import cache and audio tier built BEFORE the chains, in this
#                            process. The web chain was memory-killed six times that day, at
#                            gate 0 and gate 2, and the kills stopped once those two steps
#                            were done up front.
#   4. supersession          re-read the newest tag on origin BEFORE each channel, never
#                            during one. A chain that has started finishes or reds.
#   5. exit handling         explicit; no `[ ... ] && { ... }` anywhere near a loop tail.
#   6. his data              saves are cksummed before and after and reported either way.
#
# Usage:
#   tools/publish_all.sh <tag>            publish it
#   tools/publish_all.sh --check <tag>    run every verification and STOP before publishing
#
# Exit: 0 published · 1 a channel red · 2 verification failed · 3 superseded, re-run with the
#       tag named in the message · 4 prebuild failed

set -uo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

CHECK_ONLY=0
if [ "${1:-}" = "--check" ]; then CHECK_ONLY=1; shift; fi
TAG="${1:-}"
if [ -z "$TAG" ]; then
    echo "usage: tools/publish_all.sh [--check] <tag>" >&2
    exit 2
fi

_newest_tag_on_origin() {
    git ls-remote --tags origin 'refs/tags/v3.33.*' 2>/dev/null \
        | grep -v '\^{}' | awk '{print $2}' | sed 's#refs/tags/##' | sort -V | tail -1
}

_saves_cksum() {
    local ud="${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/Cowardly Irregular"
    [ -d "$ud/saves" ] || { echo "NO_SAVES_DIR"; return; }
    find "$ud/saves" -maxdepth 1 -type f | sort | while IFS= read -r f; do cksum < "$f"; done | cksum | awk '{print $1}'
}

echo "═══ publish_all: $TAG ═══"

# ── 1. tag evidence ──────────────────────────────────────────────────────────
# The token is required. Absence of a SKIP is NOT a failure here — it means the chains will
# run the suite sandboxed, which is correct and merely slower. Only report it.
EVIDENCE="$(./tools/tag_gate_evidence.sh "$TAG" 2>/dev/null)"
case "$EVIDENCE" in
    "VERDICT=SKIP "*) echo "[pub] evidence: ${EVIDENCE#VERDICT=SKIP }" ;;
    *)               echo "[pub] evidence: NO SKIP TOKEN — the chains will run the suite sandboxed"
                     echo "[pub]           ${EVIDENCE:-<no output>}" ;;
esac

# ── 2. version identity ──────────────────────────────────────────────────────
if [ -x tools/check_version_matches_tag.sh ]; then
    if ! ./tools/check_version_matches_tag.sh "$TAG"; then
        echo "[pub] BLOCKED: version identity failed — see above." >&2
        exit 2
    fi
else
    echo "[pub] BLOCKED: tools/check_version_matches_tag.sh missing. Refusing to publish a" >&2
    echo "      label nothing has checked against the build's own version string." >&2
    exit 2
fi

# ── 3. worktree must BE the tag ──────────────────────────────────────────────
# The chains export the WORKING TREE, so publishing from a tree that is not at the tag ships
# something the label does not describe.
HEAD_SHA="$(git rev-parse HEAD 2>/dev/null)"
TAG_SHA="$(git rev-parse "${TAG}^{commit}" 2>/dev/null)"
if [ -z "$TAG_SHA" ] || [ "$HEAD_SHA" != "$TAG_SHA" ]; then
    echo "[pub] BLOCKED: HEAD is ${HEAD_SHA:0:8} but ${TAG} is ${TAG_SHA:0:8}." >&2
    echo "      These chains export the working tree; publish from a worktree at the tag." >&2
    exit 2
fi
DIRTY="$(git status --porcelain | wc -l)"
if [ "$DIRTY" -ne 0 ]; then
    echo "[pub] BLOCKED: ${DIRTY} uncommitted change(s). The export ships the working tree." >&2
    exit 2
fi
echo "[pub] tree: ${HEAD_SHA:0:8} == ${TAG}, clean"

SAVES_BEFORE="$(_saves_cksum)"
echo "[pub] his saves before: ${SAVES_BEFORE}"

if [ "$CHECK_ONLY" -eq 1 ]; then
    echo "[pub] --check: all verifications passed, stopping before publish."
    exit 0
fi

# ── 4. prebuild the two steps that get memory-killed ─────────────────────────
# Both are idempotent and both skip when already up to date, so a re-run after an
# interruption is cheap. Doing them here rather than inside the chains is what stopped six
# consecutive kills on 2026-09-09.
echo "[pub] prebuild: import cache"
mkdir -p tmp/prewarm_xdg
XDG_DATA_HOME="$PWD/tmp/prewarm_xdg" godot --headless --audio-driver Dummy --import --quit \
    > tmp/publish_all_import.log 2>&1
IMPORT_EC=$?
IMPORTED="$(find .godot/imported -type f 2>/dev/null | wc -l)"
# A non-zero exit here is NOT decisive: godot has been observed segfaulting during editor
# teardown AFTER `reimport: end`, with the cache fully built. Judge the cache, not the code.
if [ "$IMPORTED" -lt 100 ]; then
    echo "[pub] BLOCKED: import produced only ${IMPORTED} files (exit ${IMPORT_EC}) — see tmp/publish_all_import.log" >&2
    exit 4
fi
echo "[pub] prebuild: ${IMPORTED} imported files (import exit ${IMPORT_EC}; teardown crashes are tolerated when the cache is built)"

echo "[pub] prebuild: 48k audio tier"
if ! ./tools/make_web_audio.sh 48 > tmp/publish_all_audio.log 2>&1; then
    echo "[pub] BLOCKED: audio tier build failed — see tmp/publish_all_audio.log" >&2
    exit 4
fi
TIER_N="$(find tmp/web_audio/music_48k -name '*.ogg' 2>/dev/null | wc -l)"
SRC_N="$(find assets/audio/music -name '*.ogg' | wc -l)"
if [ "$TIER_N" -ne "$SRC_N" ]; then
    echo "[pub] BLOCKED: tier has ${TIER_N} tracks, masters have ${SRC_N}." >&2
    exit 4
fi
echo "[pub] prebuild: tier ${TIER_N}/${SRC_N}"

# ── 5. publish, re-checking supersession before each channel ─────────────────
PUBLISHED=""
for CH in linux windows web; do
    NEWEST="$(_newest_tag_on_origin)"
    if [ -n "$NEWEST" ] && [ "$NEWEST" != "$TAG" ]; then
        echo "[pub] SUPERSEDED before ${CH}: origin now has ${NEWEST}." >&2
        echo "      Published so far: ${PUBLISHED:-none}. Not swapping mid-batch." >&2
        echo "      Re-run: tools/publish_all.sh ${NEWEST}   (it will re-cut every channel)" >&2
        exit 3
    fi

    case "$CH" in
        web) SCRIPT=./tools/deploy_web.sh ;;
        *)   SCRIPT=./tools/deploy_${CH}.sh ;;
    esac
    echo "[pub] ─── ${CH} ───"
    "$SCRIPT" --publish "$TAG" > "tmp/publish_all_${CH}.log" 2>&1
    EC=$?
    if [ "$EC" -ne 0 ]; then
        echo "[pub] RED on ${CH} (exit ${EC}) — STOPPING. Published so far: ${PUBLISHED:-none}" >&2
        echo "      Log: tmp/publish_all_${CH}.log" >&2
        grep -a 'BLOCKED\|VERDICT\|FAIL' "tmp/publish_all_${CH}.log" | tail -5 >&2
        echo "[pub] his saves after: $(_saves_cksum)  (before: ${SAVES_BEFORE})" >&2
        exit 1
    fi
    PUBLISHED="${PUBLISHED}${PUBLISHED:+ }${CH}"
    grep -a 'LIVE:' "tmp/publish_all_${CH}.log" | tail -1
done

# ── 6. verify against butler, not against our own logs ───────────────────────
echo "[pub] ─── verification ───"
butler status struktured/cowardly-irregular 2>&1 | grep -aE 'CHANNEL|linux|windows|^\| web'

SAVES_AFTER="$(_saves_cksum)"
if [ "$SAVES_AFTER" = "$SAVES_BEFORE" ]; then
    echo "[pub] his saves: ${SAVES_AFTER} unchanged"
else
    echo "[pub] ⚠ his saves CHANGED: ${SAVES_BEFORE} -> ${SAVES_AFTER}"
    echo "      Not necessarily a fault — he may have been playing. Diff against"
    echo "      tmp/userdata_snapshot/ before concluding anything."
fi
echo "[pub] done: ${PUBLISHED}"
exit 0
