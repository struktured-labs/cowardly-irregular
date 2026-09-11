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
#   tools/publish_all.sh --rollback <tag> deliberately republish a SUPERSEDED tag
#   tools/publish_all.sh --dry-run <tag>  run all three chains, publish NOTHING
#
# Exit: 0 published · 1 a channel red · 2 verification failed · 3 superseded, re-run with the
#       tag named in the message · 4 prebuild failed

set -uo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

CHECK_ONLY=0
ROLLBACK=0
DRY_RUN=0
while [ $# -gt 0 ]; do
    case "${1:-}" in
        --check)    CHECK_ONLY=1; shift ;;
        # DELIBERATE republish of a tag that is NOT the newest on origin. The supersession
        # gate below exists so a stale terminal cannot quietly ship an old build over a new
        # one, and it is right — but it also made ROLLBACK IMPOSSIBLE with this tool, which
        # nobody noticed in 36 publishes because nobody has needed one yet. The safety
        # mechanism and the recovery path were the same switch. This is the recovery path,
        # and it is opt-in, loud, and still subject to every other verification.
        # ⛔ MEASURED 2026-09-11: this flag CANNOT BE USED FOR ITS PURPOSE, from any tree.
        # Rolling back to tag X requires a worktree AT X (section 3 enforces HEAD == TAG and
        # exits 2 otherwise) — and that worktree contains X's OWN tooling, which predates this
        # flag. --rollback exists only in v3.33.294-alpha and newer. So:
        #
        #   worktree at the old tag  -> its publish_all has no --rollback, and the `*)` case
        #                               below took the flag AS THE TAG NAME. Measured against
        #                               v3.33.293-alpha: "publish_all: --rollback", then a
        #                               block three guards deep complaining about VERSION
        #                               IDENTITY, which is not the problem at all.
        #   worktree at HEAD         -> blocked at section 2: this tree calls itself .294 and
        #                               you asked to publish .293. Correct, and fatal to the
        #                               attempt. Section 3 would refuse next anyway.
        #
        # ⛔ So --rollback is reachable ONLY for tags that already carry it — i.e. tags new
        # enough that you would never roll back TO them. Both failures are SAFE (exit 2,
        # nothing published, zero butler calls measured); the feature simply does not work.
        # The comment above says the safety mechanism and the recovery path were the same
        # switch. They still are — the switch just moved.
        #
        # ✅ The recovery path that DOES work today needs no new code: from a worktree at the
        # target tag, drive that tree's per-channel scripts directly —
        #     tools/deploy_linux.sh --publish <old-tag>   (likewise windows, web)
        # The supersession gate is publish_all's, not theirs, so nothing blocks an older tag.
        # Verified by reaching the butler push with a stubbed binary; see the commit message.
        --rollback) ROLLBACK=1; shift ;;
        # Run all three chains to completion and publish NOTHING. --check verifies the TAG;
        # this verifies the BUILD. They answer different questions and the gap between them is
        # where every web RED this week lived: the tag was gated, the version matched, the tree
        # was clean, and the web chain still died at gate 2 three days running. There was no
        # way to learn that except by attempting a publish.
        --dry-run)  DRY_RUN=1; shift ;;
        # An unknown option must NEVER become the tag. `*) break` accepted anything, so
        # `--rollback` on tooling that predates it, or a plain typo like `--dry-runn`, became
        # TAG — and the run then failed several guards later with a message about whatever
        # that guard checks. The guards hold (nothing publishes), but they name the wrong
        # cause, and a recovery path is the worst place to hand someone a misleading error.
        --)         shift; break ;;   # explicit escape hatch for a tag that starts with -
        -*)         echo "publish_all: unknown option: $1" >&2
                    echo "usage: tools/publish_all.sh [--check|--dry-run|--rollback] <tag>" >&2
                    echo "       (use -- before a tag that begins with a dash)" >&2
                    exit 2 ;;
        *)          break ;;
    esac
done
TAG="${1:-}"
if [ -z "$TAG" ]; then
    echo "usage: tools/publish_all.sh [--check|--dry-run|--rollback] <tag>" >&2
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

# ── 0. every polling wait in the deploy chain is bounded ─────────────────────
# FIRST, because it costs milliseconds and the thing it prevents costs the whole batch.
# This script runs the channels in series and web LAST; an unbounded post-push wait in any
# chain does not fail it, it HANGS it — no RED, no exit code, no log line, and the hourly
# publish cadence simply stops. deploy_web.sh carried exactly that for months while
# deploy_desktop.sh's comment described it, which is how a documented hazard reads as a
# handled one.
#
# Delegated so the decision is exercised by ITS OWN selftest as a subprocess — same reason
# as check_import_ok.sh below, and the same reason a re-implemented copy in a probe proves
# nothing about the shipped code.
if [ -x tools/check_polling_bounded.py ]; then
    if ! ./tools/check_polling_bounded.py; then
        echo "[pub] BLOCKED: a polling wait in the deploy chain is unbounded — see above." >&2
        echo "      Refusing to start a batch that can hang instead of failing." >&2
        exit 4
    fi
else
    echo "[pub] BLOCKED: tools/check_polling_bounded.py missing — nothing has checked that the" >&2
    echo "      deploy chain can still time out. A missing guard is not a passing one." >&2
    exit 4
fi

# ── 0b. publishing is opt-in in every deploy script ──────────────────────────
# --dry-run and --rollback both rehearse a publish by WITHHOLDING --publish. That makes the
# whole containment rest on one sentence in the --dry-run comment below: "publishing is opt-in
# by construction in every deploy_*.sh". It was FALSE until 2026-08-22 — deploy_web.sh had a
# gate and published by DEFAULT — so the invariant this depends on has already been broken
# once, silently, in the script the comment names.
#
# A rollback rehearsal that publishes ships a SUPERSEDED build over a newer live one. That is
# the worst thing this lane can do, and the flag that prevents it was never checked.
if [ -x tools/check_publish_is_optin.py ]; then
    if ! ./tools/check_publish_is_optin.py; then
        echo "[pub] BLOCKED: a butler push is reachable without --publish — see above." >&2
        echo "      --dry-run and --rollback are not safe while that is true." >&2
        exit 4
    fi
else
    echo "[pub] BLOCKED: tools/check_publish_is_optin.py missing — nothing has checked that" >&2
    echo "      withholding --publish actually withholds the push. A missing guard is not a" >&2
    echo "      passing one." >&2
    exit 4
fi

# ── 1. tag evidence ──────────────────────────────────────────────────────────
# The token is required. Absence of a SKIP is NOT a failure here — it means the chains will
# run the suite sandboxed, which is correct and merely slower. Only report it.
EVIDENCE="$(./tools/tag_gate_evidence.sh "$TAG" 2>/dev/null)"
case "$EVIDENCE" in
    "VERDICT=SKIP "*) EVIDENCE_STATE="gated (suite may be skipped in the chains)"
                     echo "[pub] evidence: ${EVIDENCE#VERDICT=SKIP }" ;;
    *)               EVIDENCE_STATE="NOT gated — the chains will run the suite sandboxed"
                     echo "[pub] evidence: NO SKIP TOKEN — the chains will run the suite sandboxed"
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

# ── 3b. supersession, REPORTED HERE and not only at publish time ─────────────
# This check used to live solely inside the publish loop, so `--check` validated evidence,
# version and tree, printed a green verdict, and exited 0 for a publish that would refuse
# immediately. Demonstrated 2026-09-10: `--check v3.33.292-alpha` from a clean worktree at
# that tag returned exit 0 while origin was already on .293.
#
# A check whose verdict does not predict the run it is checking is not a check. So this now
# fails the SAME WAY the publish would, with the same exit code.
NEWEST_NOW="$(_newest_tag_on_origin)"
if [ -n "$NEWEST_NOW" ] && [ "$NEWEST_NOW" != "$TAG" ]; then
    if [ "$ROLLBACK" -eq 1 ]; then
        echo "[pub] ⚠ ROLLBACK: ${TAG} is SUPERSEDED by ${NEWEST_NOW} on origin, and --rollback was given."
        echo "[pub]   This will publish an OLDER build over a newer one, on all three channels."
    else
        echo "[pub] SUPERSEDED: ${TAG} is not the newest tag on origin — ${NEWEST_NOW} is." >&2
        echo "      A publish would refuse at the supersession gate before touching butler." >&2
        echo "      Publish the newest:  tools/publish_all.sh ${NEWEST_NOW}" >&2
        echo "      Deliberate rollback: tools/publish_all.sh --rollback ${TAG}" >&2
        exit 3
    fi
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
    # NAME WHAT RAN, AND CARRY THE ONE RESULT THAT IS REPORTED RATHER THAN ENFORCED.
    #
    # This line used to read "all verifications passed". It was byte-identical for a gated tag
    # and for a tag carrying NO gate evidence at all — demonstrated end-to-end on a clean tree
    # with an ungated annotated tag, both printing the same sentence and exiting 0. The verdict
    # was right (no SKIP token simply means the chains run the suite sandboxed, the safe path);
    # the sentence was not. "All" is unbounded, and it covered a step that only REPORTS.
    #
    # The general tell, which is cheaper than imagining a violating input: A LABEL THAT CANNOT
    # CHANGE WHEN ITS INPUT CHANGES IS NOT REPORTING THAT INPUT. Vary each thing the summary
    # claims to cover; if the text is invariant, the claim is decoration.
    echo "[pub] --check: version identity OK · tree identity OK · saves baseline recorded."
    echo "[pub]          tag evidence: ${EVIDENCE_STATE}"
    # This line said "NOT checked here: prebuilds, supersession, and every chain gate" — and
    # then supersession MOVED here, making it false in the under-claiming direction. A summary
    # that enumerates what it skipped decays exactly as fast as one that claims "all", just
    # less visibly: nothing re-reads it when a check is added. Kept because naming the gap is
    # still right, corrected because the gap moved.
    echo "[pub]          also checked: supersession against origin."
    echo "[pub]          NOT checked here: prebuilds and every chain gate (suite, export, smokes)."
    echo "[pub]          Stopping before publish."
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
if [ "$IMPORTED" -lt 100 ]; then
    echo "[pub] BLOCKED: import produced only ${IMPORTED} files (exit ${IMPORT_EC}) — see tmp/publish_all_import.log" >&2
    exit 4
fi

# Delegated to tools/check_import_ok.sh so the decision is exercised by ITS OWN selftest as a
# subprocess, rather than by a copy of the condition living in whatever shell I happened to be
# in. The inline version was "tested" by me re-implementing the grep in a probe function — four
# green arms that proved my copy worked and never invoked this file at all. (cowir-battle,
# 2026-09-09: a test that calls the repaired function directly cannot tell either; testing a
# re-implementation does not even execute the shipped code.)
if [ -x tools/check_import_ok.sh ]; then
    if ! ./tools/check_import_ok.sh tmp/publish_all_import.log "$IMPORT_EC" 100 "$IMPORTED"; then
        echo "[pub] BLOCKED: refusing to build on this import cache — see above." >&2
        exit 4
    fi
else
    echo "[pub] BLOCKED: tools/check_import_ok.sh missing. Refusing to accept a non-zero import" >&2
    echo "      exit on a file count alone — that is the guard whose stated reason did not hold." >&2
    exit 4
fi

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
    if [ "$ROLLBACK" -eq 1 ]; then
        NEWEST="$TAG"   # --rollback: a newer tag is expected and is not a reason to stop
    fi
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
    # The ONLY difference between a dry run and a publish is this flag. Publishing is opt-in
    # by construction in every deploy_*.sh — without --publish they run every gate and stop at
    # gate 4 — so a dry run is not a separate code path that could drift from the real one. It
    # is the same path with the last step withheld, which is the only kind of rehearsal worth
    # having.
    if [ "$DRY_RUN" -eq 1 ]; then
        "$SCRIPT" "$TAG" > "tmp/publish_all_${CH}.log" 2>&1
    else
        "$SCRIPT" --publish "$TAG" > "tmp/publish_all_${CH}.log" 2>&1
    fi
    EC=$?
    if [ "$EC" -ne 0 ]; then
        echo "[pub] RED on ${CH} (exit ${EC}) — STOPPING. Published so far: ${PUBLISHED:-none}" >&2
        echo "      Log: tmp/publish_all_${CH}.log" >&2
        # A KILLED chain is not a FAILED chain, and this lane kills chains routinely — the
        # header above records the web chain being memory-killed six times in one day. A killed
        # process emits no Totals block and no verdict, so the grep below returns NOTHING, and
        # "RED, no explanation" reads as a gate failure nobody can find. That sends you editing
        # correct code to chase a stopwatch or a memory ceiling. (@cowir-controller, 2026-09-11:
        # their sweep collapsed EC 1, 3 and 124 into one blank field for exactly this reason.)
        case "$EC" in
            124) echo "      ⚠ EXIT 124 = TIMED OUT. The chain was killed by a ceiling, not" >&2
                 echo "        failed by a gate. Nothing below is a verdict; the grep is empty" >&2
                 echo "        because no gate got to report. Re-run on a quieter box before" >&2
                 echo "        touching any code — check: pgrep -c godot" >&2 ;;
            137) echo "      ⚠ EXIT 137 = KILLED, signal 9 — almost certainly the OOM killer." >&2
                 echo "        Not a gate failure. This lane's web chain was memory-killed six" >&2
                 echo "        times in one day; that is why the caches are prebuilt in §4." >&2
                 echo "        Re-run; §4 is idempotent and skips what is already current." >&2 ;;
            143) echo "      ⚠ EXIT 143 = TERMINATED, signal 15. Something asked it to stop." >&2
                 echo "        Not a gate failure." >&2 ;;
        esac
        grep -a 'BLOCKED\|VERDICT\|FAIL' "tmp/publish_all_${CH}.log" | tail -5 >&2
        echo "[pub] his saves after: $(_saves_cksum)  (before: ${SAVES_BEFORE})" >&2
        exit 1
    fi
    PUBLISHED="${PUBLISHED}${PUBLISHED:+ }${CH}"
    if [ "$DRY_RUN" -eq 1 ]; then
        # Do not grep for LIVE: on a dry run — there is none, and `tail -1` of an empty grep
        # prints nothing, which would read as a quiet success rather than as "did not publish".
        echo "[pub] ${CH}: all gates GREEN, nothing published"
    else
        grep -a 'LIVE:' "tmp/publish_all_${CH}.log" | tail -1
    fi
done

# ── 6. verify against butler, not against our own logs ───────────────────────
if [ "$DRY_RUN" -eq 1 ]; then
    echo "[pub] ─── dry run complete ───"
    echo "[pub] all three chains GREEN for ${TAG}. NOTHING WAS PUBLISHED."
    echo "[pub] the store is still on whatever it was — verify with tools/store_status.sh"
    echo "[pub] his saves: $(_saves_cksum)  (before: ${SAVES_BEFORE})"
    echo "[pub] to publish for real: tools/publish_all.sh ${TAG}"
    exit 0
fi

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
