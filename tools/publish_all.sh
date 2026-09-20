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

# ── the store read-back's ABSENCE is announced, on every exit path ───────────────────────
# tools/verify_store_artifact.sh is the only check in this lane that crosses the CDN: every
# gate tests the LOCAL artifact and stops at the moment of upload, and `butler status` reports
# what butler was ASKED to push, not the bytes a player downloads. It is deliberately NOT wired
# into every publish — its own header says so, "real bandwidth for a check whose expected answer
# is identical. Run it after a publish that mattered."
#
# ⛔ THE PROBLEM IS THAT SKIPPING IT IS SILENT. On 2026-09-11 I published v3.33.295-alpha — 39
# branches, 1634 scripts, a publish that mattered by that tool's own criterion — did not run the
# read-back, and then removed the worktree as tidy-up, DELETING the local builds it compares
# against. Nothing said so. "Never ran" and "passed" produce identical output, which is the
# quiet failure direction: a loud wrong answer gets investigated, a quiet one ends the inquiry.
#
# I recorded a sequencing rule for myself afterwards. A rule I have to remember is a reminder
# wearing a rule's clothes — it fails exactly when I am tired, which is when publishes happen.
#
# ⚠ WHY A TRAP AND NOT A LINE AT THE END: this script has 21 exit paths and 19 of them are
# BEFORE section 6. The one that matters most is the mid-batch RED — some channels already
# shipped, the run stopped — and a notice at the bottom is structurally unreachable exactly
# there. An early return would skip the warning about the thing the early return skipped.
# (@cowir-controller, 2026-09-11, whose run_tests.sh vacuity check sits after the tee and so
# cannot fire on a killed run.)
# ── the evidence outlives the worktree ──────────────────────────────────────────────────
# Every per-channel log this script writes lands in `tmp/` INSIDE the publish worktree, and a
# publish worktree is removed minutes later — it is 3.5 GB and there is no reason to keep it
# once the read-back is done. So the logs die with it.
#
# ⛔ MEASURED 2026-09-11, after publishing .297, .298 and .299 in one session:
#
#     archived log directories from pub* worktrees:  0
#     surviving rel-262/publish_all_web.log:         "[deploy] index.pck: 164 MB"
#
# That line is the web pack size at gate 3/4 — the number two lanes needed this afternoon to
# size an audio-tier decision, measured three times today and discarded three times. The lane's
# own reaper archives logs for exactly this reason ("the evidence trail behind published
# claims") but only under `tmp/rel-`, and the publish flow creates `tmp/pub<N>`. The tool and
# its subject drifted apart by a path prefix.
#
# 🔑 The repair is NOT to widen that prefix, and not to remember to reap instead of remove.
# Archiving was coupled to REMOVAL, and removal is the one step whose whole purpose is to
# destroy the directory. It belongs to the thing that PRODUCES the logs, at the moment it is
# finished with them — which is here, on every exit path, including the blocked ones. A publish
# that was REFUSED leaves evidence worth more than one that succeeded.
#
# ⛔ AND THE DESTINATION IS NOT `git rev-parse --git-common-dir`. That was the first version and
# it resolved to the PRIMARY checkout — a tree this lane does not own and must not write into
# (measured: it pointed at /home/.../cowardly-irregular, another agent's working directory).
# A publish worktree is created as `<lane worktree>/tmp/<name>`, so the lane root is the path
# before `/tmp/`. That is derived from this worktree's own location, checkable, and refuses
# out loud rather than guessing when the shape does not match.
_archive_evidence() {
    local here dest n=0
    here="$(pwd -P)"
    case "$here" in
        */tmp/*) dest="${here%%/tmp/*}/tmp/_archive/logs/${TAG:-untagged}" ;;
        *)  # Not a publish worktree under a lane tmp/ — say so rather than invent a path.
            echo "[pub] note: logs not archived — ${here} is not a <lane>/tmp/<worktree> path;" >&2
            echo "[pub]       set the archive by hand if this run's evidence matters." >&2
            return 0 ;;
    esac
    [ -d tmp ] || return 0
    mkdir -p "$dest" 2>/dev/null || return 0
    # ⛔ NEVER OVERWRITE AN ARCHIVED LOG. The archive is keyed by TAG, so a second publish of
    # the same tag lands on the same filenames — and `cp` truncates its destination on open,
    # so the FIRST run's evidence is gone before the second byte is written.
    #
    # That is not hypothetical. v3.33.422-alpha red on web with a godot signal-11 trace, and
    # when I later rebuilt the stage to test reproducibility that rebuild overwrote the
    # worktree copy. tmp/_archive/logs/v3.33.422-alpha/stage_import.log was the ONLY surviving
    # record, and the import-gate fix in .426 was verified against it. Had I re-run the publish
    # for that tag instead of running the stage directly, this loop would have replaced the
    # crash log with a clean one and there would have been no ground truth left to test.
    #
    # The FIRST archive of a tag is the interesting one: a re-run is usually the clean run.
    # So the first copy is kept and later runs land beside it. Nothing is lost in either
    # direction, and this stays best-effort — it never blocks a publish.
    for f in tmp/*.log; do
        [ -f "$f" ] || continue
        _dst="${dest}/$(basename "$f")"
        if [ -e "$_dst" ]; then
            _i=2
            while [ -e "${_dst}.run${_i}" ]; do _i=$((_i + 1)); done
            _dst="${_dst}.run${_i}"
        fi
        cp -p "$f" "$_dst" 2>/dev/null && n=$((n + 1))
    done
    [ "$n" -gt 0 ] && echo "[pub] evidence archived: ${n} log(s) -> ${dest}"

    # The release NOTE, derived from the tag's own merge history rather than from prose.
    #
    # WHY IT IS HERE. Measured 2026-09-16: a release describes itself to nobody. Every GitHub
    # release body we have published is one auto-generated compare link (checked live on .355,
    # .356, .357) and itch gets a version string. The changelog written per tag lives in the
    # annotation, reaches no surface outside the repo, and nothing checks it against the tree —
    # v3.33.358-alpha's opened with "a costume no longer re-times the character" and that tag
    # contains no such change, plus two more clauses naming branches that never merged.
    #
    # This writes the derived note beside the evidence so every release HAS one. Publishing it
    # to the GitHub release body is a one-line change and deliberately NOT made here: that is
    # outward-facing and is struktured's call, not a side effect of archiving.
    # ── and verify it did not move while the channels ran ───────────────────────────────────
    # Never fatal: the upload has already happened by the time this runs, so failing the publish
    # here would undo nothing. It is loud instead, and the evidence records it — an artifact that
    # may not be the gated commit is a fact about the release, not a reason to pretend otherwise.
    if [ -x tools/check_tree_unmoved.sh ] && [ -r "${_TREE_REC:-/nonexistent}" ]; then
        ./tools/check_tree_unmoved.sh --verify "$TAG" "$_TREE_REC" \
            || echo "[pub] ⚠ THE SHIPPED TREE IS NOT THE GATED TREE — see above. The read-back cannot detect this." >&2
    fi

    if [ -n "${TAG:-}" ] && [ -x tools/release_note.sh ]; then
        # --prev is what the STORE had, not the previous tag: see STORE_BEFORE above.
        _note_prev=(); [ -n "${STORE_BEFORE:-}" ] && _note_prev=(--prev "$STORE_BEFORE")
        if ./tools/release_note.sh "$TAG" ${_note_prev[@]+"${_note_prev[@]}"} \
                --out "${dest}/RELEASE_NOTE.md" >/dev/null 2>&1; then
            echo "[pub] release note derived -> ${dest}/RELEASE_NOTE.md"
        else
            # Never fatal: a publish that shipped correctly is not undone by a note that did not
            # generate. But say it, because a silently absent note is how this gap persisted.
            echo "[pub] note: release note NOT derived for ${TAG} — see tools/release_note.sh" >&2
        fi
    fi
    return 0
}

READBACK_DONE=0
_readback_notice() {
    # Nothing shipped -> nothing to read back. --check, --dry-run and every pre-publish BLOCK
    # land here and stay silent, so the notice cannot become background noise.
    [ -n "${PUBLISHED:-}" ] || return 0
    if [ "${READBACK_DONE:-0}" = "1" ]; then
        echo "[pub] store read-back: performed."
        return 0
    fi
    echo "[pub] ⚠ STORE READ-BACK NOT PERFORMED — published: ${PUBLISHED}" >&2
    echo "[pub]   Every gate above tested the LOCAL artifact and stopped at the upload." >&2
    echo "[pub]   Nothing here has looked at what the store SERVES." >&2
    # Only the channels that actually SHIPPED. Listing build/windows after a linux-and-web
    # publish names a directory irrelevant to this run — a label broader than its predicate,
    # which is the defect I have spent the day removing from this lane's guards.
    local any=0 _d
    for _c in ${PUBLISHED}; do
        case "$_c" in
            web) _d="builds/web" ;;
            *)   _d="build/${_c}" ;;
        esac
        if [ -d "$_d" ]; then
            echo "[pub]   ${_c}: local build still on disk at ${_d}" >&2
            any=1
        else
            echo "[pub]   ${_c}: local build ${_d} is GONE" >&2
        fi
    done
    if [ "$any" = "1" ]; then
        # ABSOLUTE, and rooted in the worktree that produced these artifacts. These used to be
        # relative, which is correct only if you are standing in this worktree — and the whole
        # point of the block is that you are reading it later, somewhere else. Measured 2026-09-16:
        # I pasted them into the lane's main checkout, which sat on a branch from three weeks
        # earlier, and ran a read-back of .354 against an Aug-22 build. verify_store_artifact.sh
        # now refuses that comparison outright, but the instruction is what sent me there.
        local _root; _root="$(pwd -P)"
        echo "[pub]   RUN IT NOW, for the channels whose build survives:" >&2
        echo "[pub]     cd ${_root}" >&2
        for _c in ${PUBLISHED}; do
            case "$_c" in
                web) [ -d builds/web ] && echo "[pub]     ${_root}/tools/verify_store_artifact.sh web ${_root}/builds/web" >&2 ;;
                *)   [ -d "build/${_c}" ] && echo "[pub]     ${_root}/tools/verify_store_artifact.sh ${_c} ${_root}/build/${_c}" >&2 ;;
            esac
        done
        echo "[pub]   Do not remove the worktree until it has run or you have decided to skip it." >&2
    else
        echo "[pub]   ⛔ THE LOCAL BUILDS ARE ALREADY GONE. The read-back compares the store to" >&2
        echo "[pub]      what we built; that half no longer exists and a rebuild is not the same" >&2
        echo "[pub]      bytes. This publish can no longer be verified against the store." >&2
    fi
}
_on_exit() {
    # Archive FIRST: the read-back notice is advisory, the logs are the record. If anything
    # in the notice ever fails, the evidence is already written.
    _archive_evidence
    _readback_notice
}
trap _on_exit EXIT

CHECK_ONLY=0
ROLLBACK=0
DRY_RUN=0
READ_BACK=0
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
        # Opt-in, because the read-back costs real bandwidth for a check whose expected answer
        # is "identical" — verify_store_artifact.sh's own stance, kept. What changed is that
        # SKIPPING it is now announced rather than silent, so the choice is made rather than
        # defaulted into. Without this flag READBACK_DONE stays 0 and the exit trap says so;
        # with it, the branch that reports "performed" is reachable instead of dead.
        --read-back) READ_BACK=1; shift ;;
        # An unknown option must NEVER become the tag. `*) break` accepted anything, so
        # `--rollback` on tooling that predates it, or a plain typo like `--dry-runn`, became
        # TAG — and the run then failed several guards later with a message about whatever
        # that guard checks. The guards hold (nothing publishes), but they name the wrong
        # cause, and a recovery path is the worst place to hand someone a misleading error.
        --)         shift; break ;;   # explicit escape hatch for a tag that starts with -
        -*)         echo "publish_all: unknown option: $1" >&2
                    echo "usage: tools/publish_all.sh [--check|--dry-run|--rollback|--read-back] <tag>" >&2
                    echo "       (use -- before a tag that begins with a dash)" >&2
                    exit 2 ;;
        *)          break ;;
    esac
done
TAG="${1:-}"
if [ -z "$TAG" ]; then
    echo "usage: tools/publish_all.sh [--check|--dry-run|--rollback|--read-back] <tag>" >&2
    exit 2
fi

# ── DISK, BEFORE ANYTHING EXPENSIVE ──────────────────────────────────────────────────────
# ⛔ 2026-09-19: v3.33.458-alpha died at EC=4 with `OSError: [Errno 28] No space left on
# device`, and the message the operator got was:
#
#     BLOCKED: tools/check_web_audio_tier.py FAILED ITS OWN SELFTEST.
#
# That is TRUE and it names the wrong subject. The guard was fine; the filesystem was full at
# 958 MB of 3.6 TB. A reader starts on check_web_audio_tier.py -- and the refusal that ran is
# the LAST one in a chain, so the name you get is whichever guard happened to touch the disk
# first, not the thing that is wrong. I reclaimed 14 GB and the same run passed untouched.
#
# The refusal was still CORRECT as a decision: a guard whose selftest cannot run is
# untrustworthy, not absent. What was wrong was the NOUN. So this does not replace that guard,
# it arrives before it and names the fact.
#
# THE NUMBER IS DERIVED, NOT GUESSED. A completed release worktree measured 2026-09-19:
#     tmp/pub458 total 3.4G   =  checkout ~2.3G + build/ 634M + builds/ 190M + .godot 238M
#   plus the web stage (tmp/web_stage, 563M) and a 40k audio tier (~83M) when uncached.
# Call it 4.5G consumed by a clean run; 5G is that plus a slim margin. Below this a publish
# does not fail fast -- it fails ten minutes in, having uploaded nothing, blaming a gate.
#
# ⚠️ This measures the filesystem holding THIS WORKTREE, because that is where the export,
# the stage and the .godot cache are written. On this box it is the same device as $HOME, and
# that is a fact about the box rather than a guarantee.
PUBLISH_MIN_FREE_MB="${PUBLISH_MIN_FREE_MB:-5000}"
_avail_mb="$(df --output=avail -m . 2>/dev/null | tail -1 | tr -d ' ')"
case "$_avail_mb" in
    ''|*[!0-9]*)
        # Refusing to guess. An unreadable df is not "plenty of room".
        echo "[pub] BLOCKED: could not read free space for $(pwd -P) — df returned '${_avail_mb}'." >&2
        echo "[pub]   This check cannot be skipped by failing to run: a publish that fills the" >&2
        echo "[pub]   disk mid-flight blames whichever guard touches it first." >&2
        exit 4 ;;
    *)
        if [ "$_avail_mb" -lt "$PUBLISH_MIN_FREE_MB" ]; then
            echo "[pub] BLOCKED: ${_avail_mb} MB free where a publish needs ${PUBLISH_MIN_FREE_MB} MB." >&2
            echo "[pub]   Derived: a completed release worktree is ~3.4 GB (checkout + build/ +" >&2
            echo "[pub]   builds/ + .godot), plus the web stage and the audio tier when uncached." >&2
            echo "[pub]   NOTHING has been built or uploaded." >&2
            echo "[pub]" >&2
            # ⛔ DO NOT SEND THE READER STRAIGHT AT THIS LANE. Measured 2026-09-19: the whole
            # cowir fleet was 35G of a 3.4T disk -- about 1% -- while single unrelated projects
            # of struktured's held hundreds of gigabytes. Seven lanes each audited their own
            # tmp/ and three broke a standing directive to prune rounding errors, because the
            # question "am I full?" was answered by whoever was asked rather than by where the
            # mass was. An instruction to reap THIS lane, printed at the moment someone is
            # blocked and hurrying, is exactly how that happens again.
            echo "[pub]   FIRST, find out whose bytes these are. This lane is usually not the cause:" >&2
            echo "[pub]     du -sh ~/projects/*/tmp | sort -rh | head -20" >&2
            echo "[pub]   ⚠ That glob expands to ~120 directories and SOME ARE SYMLINKS to each" >&2
            echo "[pub]     other, so du walks one tree twice and the sum double-counts. Confirm" >&2
            echo "[pub]     any big row is a real directory before believing it:  readlink <path>" >&2
            echo "[pub]" >&2
            # ⛔ ASK THE REAPER WHETHER IT COULD HELP, RATHER THAN OFFERING IT AND HOPING.
            # 2026-09-19, 22:2x: the disk was 909 MB against a 5000 MB floor -- a 4091 MB
            # shortfall -- and the reaper had ZERO candidates. The block still printed its two
            # commands, so a reader in a hurry would have run a destructive tool that frees
            # nothing, deleted the publish evidence under _archive, and still been blocked.
            # An instruction that cannot work is worse than no instruction, because following
            # it feels like progress and the second attempt starts from less.
            #
            # `would remove` is the reaper's CONTRACT, not incidental formatting -- its own
            # selftest arms assert that exact string in both directions. Counted from a real
            # file, never a pipeline, because $? across a pipe has bitten this file before.
            _short_mb=$(( PUBLISH_MIN_FREE_MB - _avail_mb ))
            _reap_log="tmp/reap_probe.$$.log"
            mkdir -p tmp
            _reap_ec=0
            timeout 120 ./tools/reap_release_worktrees.sh > "$_reap_log" 2>&1 || _reap_ec=$?
            _cands=0
            if [ -f "$_reap_log" ]; then
                _cands=$(command grep -ac 'would remove' "$_reap_log" || true)
            fi
            case "$_cands" in ''|*[!0-9]*) _cands=0 ;; esac
            if [ "$_reap_ec" -ne 0 ] && [ "$_reap_ec" -ne 1 ]; then
                # Could not ask. Say so and fall back to the old advice rather than inventing
                # a verdict -- "the reaper cannot help" is a CLAIM and an unrunnable probe
                # does not support it.
                echo "[pub]   COULD NOT ASK THE REAPER (exit ${_reap_ec}) whether cleanup here could help." >&2
                echo "[pub]   Treat the next two lines as unverified:" >&2
                echo "[pub]     tools/reap_release_worktrees.sh            # dry run, names what it would remove" >&2
                echo "[pub]     tools/reap_release_worktrees.sh --apply    # only trees rebuildable from a tag on origin" >&2
            elif [ "$_cands" -eq 0 ]; then
                echo "[pub]   ⛔ CLEANUP HERE CANNOT CLEAR THIS FLOOR, SO DO NOT START ONE." >&2
                echo "[pub]     The reaper has 0 removable trees; it would free 0 MB against a" >&2
                echo "[pub]     ${_short_mb} MB shortfall. It is the ONLY cleanup this lane is" >&2
                echo "[pub]     permitted to do, so there is nothing here to reclaim. The space" >&2
                echo "[pub]     is held outside this lane and freeing it is struktured's call." >&2
                echo "[pub]     Probe: ${_reap_log}" >&2
            else
                echo "[pub]   The reaper names ${_cands} removable tree(s) against a ${_short_mb} MB" >&2
                echo "[pub]   shortfall. Whether that is ENOUGH is not known until you read the" >&2
                echo "[pub]   dry run -- the count is trees, not megabytes:" >&2
                echo "[pub]     cat ${_reap_log}                          # what it would remove, already measured" >&2
                echo "[pub]     tools/reap_release_worktrees.sh --apply    # only trees rebuildable from a tag on origin" >&2
            fi
            echo "[pub]" >&2
            echo "[pub]   ⛔ Do NOT delete outside this lane. Those are struktured's other projects" >&2
            echo "[pub]     and the standing directive is: delete nothing of his." >&2
            echo "[pub]   Override with PUBLISH_MIN_FREE_MB=<mb> if you know better than this number." >&2
            exit 4
        fi
        echo "[pub] disk: ${_avail_mb} MB free (floor ${PUBLISH_MIN_FREE_MB} MB)"
        ;;
esac

# ── --rollback refuses HERE, with the reason, not three guards deep ──────────────────────
# MEASURED 2026-09-11, both horns. --rollback cannot be used for its purpose from ANY tree:
#
#   worktree AT the old tag    §3 REQUIRES it (HEAD must equal TAG), and that tree carries its
#                              OWN tooling, which predates the flag. --rollback exists only in
#                              v3.33.294-alpha and newer; v3.33.293-alpha and older have zero
#                              occurrences of ROLLBACK=1. The `*)` arm took the flag AS THE TAG.
#   worktree at HEAD           §2 blocks: this tree calls itself <SEMVER> and you asked to
#                              publish an older label. Correct, and fatal to the attempt.
#
# So the flag is reachable only for tags that already carry it — tags new enough that you would
# never roll back TO them.
#
# ⛔ THE REASON THIS IS A REFUSAL AND NOT A COMMENT. I recorded that finding at the flag's case
# arm this morning and left it there. My own memory entry says a hazard you have documented
# reads as one you have handled — and a comment above a case arm is read by whoever is ALREADY
# three guards deep in a confusing failure, which is the one moment it is no use. The tripwire
# beats the note because it arrives when it applies. (@cowir-overworld shipped a tripwire where
# I shipped a comment; the difference is not visible in a diff.)
# ✅ EXERCISED VIA THE REAL COMMAND LINE 2026-09-11, not by sourcing this block with ROLLBACK=1
# preset. @cowir-overworld: "I checked the direction my change flowed OUT and not the direction
# control flows IN — only the second is about the player." My block tests set the variable
# directly, which never shows that `--rollback` on argv REACHES here.
#
#   ./tools/publish_all.sh --rollback v3.33.293-alpha   EC 2, tripwire fired
#   ./tools/publish_all.sh --rollback <this tree's own>  EC 2, tripwire did NOT fire
#   ./tools/publish_all.sh --check    v3.33.293-alpha    EC 2, tripwire did NOT fire
#
# ⚠ All three exit 2 and only one is this guard — the other two are downstream. A bare exit
# code names one cause and accepts three, so the discriminator is the MESSAGE. (And my first
# run of this reported EC 141: I piped it to `head`, and read SIGPIPE as the script's code.)
if [ "$ROLLBACK" -eq 1 ]; then
    _rb_semver="$(sed -n 's/^[[:space:]]*const[[:space:]]\+SEMVER[[:space:]]*:=[[:space:]]*"\([^"]*\)".*/\1/p' \
                  src/meta/Version.gd 2>/dev/null | head -1)"
    if [ -n "$_rb_semver" ] && [ "v${_rb_semver}" != "$TAG" ]; then
        echo "[pub] BLOCKED: --rollback ${TAG} cannot work from this tree, and cannot work from" >&2
        echo "      the tag's own tree either. Measured, both horns:" >&2
        echo "        here      this worktree is v${_rb_semver}; §2 refuses to publish it as ${TAG}" >&2
        echo "        there     a worktree at ${TAG} carries ${TAG}'s tooling, which predates" >&2
        echo "                  --rollback (it exists only in v3.33.294-alpha and newer), so the" >&2
        echo "                  flag is parsed AS THE TAG NAME" >&2
        echo "      The flag is therefore reachable only for tags new enough that you would never" >&2
        echo "      roll back TO them." >&2
        echo "" >&2
        echo "      ✅ THE ROLLBACK THAT WORKS TODAY needs no new code. From a worktree at ${TAG}," >&2
        echo "         drive that tree's per-channel scripts directly — the supersession gate is" >&2
        echo "         this script's, not theirs:" >&2
        echo "           git worktree add --detach <dir> ${TAG}" >&2
        echo "           cd <dir> && tools/deploy_linux.sh   --publish ${TAG}" >&2
        echo "                       tools/deploy_windows.sh --publish ${TAG}" >&2
        echo "                       tools/deploy_web.sh     --publish ${TAG}" >&2
        echo "         Verified by reaching the butler push with a stubbed binary, 2026-09-11." >&2
        exit 2
    fi
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

# ── THE CHECKSUM IS A WITNESS TO THE ENDPOINTS; THIS IS A WITNESS TO THE INTERVAL ────────────
# `_saves_cksum` is read once before the channels and once after, so it answers "is his data
# the same NOW as it was THEN" and is blind BY CONSTRUCTION to anything that wrote his saves
# and put them back in between. That is not hypothetical bookkeeping: a snapshot/restore with
# `cp -a`, `rsync -a` or `tar` preserves mtime too, so neither the content nor the modification
# time would show it. Measured 2026-09-18:
#
#     cp -a orig snap; echo tampered > orig; cp -a snap orig
#     mtime  1782907200.000000000 -> 1782907200.000000000   IDENTICAL  (hides)
#     ctime  1789725265           -> 1789725266             MOVED      (cannot hide)
#
# ctime is not settable from userspace — `touch -r` and `cp -a` set atime and mtime and always
# bump ctime to now. So it is the one field a well-behaved restore cannot forge.
#
# ⚠️ This reports; it does not gate. It runs after the uploads, so its job is to make a
# touched-and-restored profile VISIBLE rather than to prevent it. A publish-path writer is
# what would need fixing, and today there is none: check_user_data_sandboxed.py reports
# 22 invocations that can write user://, 20 sandboxed, 2 declared (launch.sh, the player's
# own launcher, never on a publish path), 0 UNSANDBOXED.
_saves_ctime_max() {
    local ud="${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/Cowardly Irregular"
    local newest
    [ -d "$ud/saves" ] || { echo "NO_SAVES_DIR"; return; }
    newest="$(find "$ud/saves" -maxdepth 1 -type f -printf '%C@\n' 2>/dev/null | sort -rn | head -1 | cut -d. -f1)"
    # An EMPTY answer must not read as "0 == 0, nothing moved". Say so instead.
    [ -n "$newest" ] || { echo "NO_FILES"; return; }
    echo "$newest"
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
# ⛔ A PRESENT GUARD IS NOT A WORKING ONE. The `else` branch below already refuses a MISSING
# guard — "a missing guard is not a passing one". The same sentence holds one level up and was
# not checked: a guard whose detector has gone dead is present, executable, exit 0, and silent.
#
# Measured 2026-09-11 on check_publish_is_optin.py, real tools/ tree, its --publish detector
# forced dead (one line):
#
#     deploy_desktop.sh  ok  push gated on --publish, flag defaults to off   <- FALSE, and green
#     deploy_linux.sh    ok  never names --publish — forwards untouched      <- FALSE, and green
#     2 script(s) contain a push site · 0 finding(s)                  EC 0
#
# Its selftest catches that instantly — 4 arms red — but NOTHING IN THE PUBLISH PATH RAN THE
# SELFTEST. The arms existed and were unreachable at the only moment they mattered, which is
# the same composition failure as --rollback needing tooling the old tree lacks.
# 0.03s per gate against a ~45min publish.
# Delegated so the decision is exercised by ITS OWN selftest as a subprocess — same reason
# as check_import_ok.sh below, and the same reason a re-implemented copy in a probe proves
# nothing about the shipped code.
if [ -x tools/check_polling_bounded.py ]; then
    if ! _ST=$(./tools/check_polling_bounded.py --selftest 2>&1); then
        printf '%s\n' "$_ST" | tail -25 >&2
        echo "[pub] BLOCKED: tools/check_polling_bounded.py FAILED ITS OWN SELFTEST — the bounded-wait detector" >&2
        echo "      is not answering correctly, so its verdict on this tree means" >&2
        echo "      nothing. A present guard is not a working one." >&2
        exit 4
    fi
    echo "[pub] selftest ok: tools/check_polling_bounded.py (bounded-wait detector) — arms ran and passed"
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

# ── 0a-1b. every godot invocation on the publish path runs under a clock ────
# The sibling of 0a-1, and it exists because the hazard 0a-1 guards against had a twin nobody
# had swept for. 2026-09-19: SEVEN godot invocations on this path, EXACTLY ONE bounded. A wedge
# in any of the other six is worse than an unbounded `until` loop, because this publish runs
# DETACHED — no publish.ec is ever written and `--status` waits on that file forever. A release
# that simply never happens, with no RED, no exit code and no log line.
#
# It BLOCKS on the publish path and INVENTORIES the rest (the fleet's test runner and four
# screenshot tools are genuinely unbounded and are not this lane's to bound tonight); the
# out-of-scope count is printed every run so it is a stated scope rather than a blind spot.
if [ -f tools/check_godot_bounded.py ]; then
    if ! _ST=$(python3 tools/check_godot_bounded.py --selftest 2>&1); then
        printf '%s\n' "$_ST" | tail -25 >&2
        echo "[pub] BLOCKED: tools/check_godot_bounded.py FAILED ITS OWN SELFTEST — the unbounded-godot" >&2
        echo "      detector is not answering correctly, so its verdict on this tree means" >&2
        echo "      nothing. A present guard is not a working one." >&2
        exit 4
    fi
    echo "[pub] selftest ok: tools/check_godot_bounded.py (unbounded-godot detector) — arms ran and passed"
    if ! python3 tools/check_godot_bounded.py; then
        echo "[pub] BLOCKED: a godot invocation on the publish path has no clock on it — see above." >&2
        echo "      Refusing to start a detached batch that can hang instead of failing." >&2
        exit 4
    fi
else
    echo "[pub] BLOCKED: tools/check_godot_bounded.py missing — nothing has checked that this" >&2
    echo "      chain can still time out around godot. A missing guard is not a passing one." >&2
    exit 4
fi

# ── 0a-1c. no `set -e` script captures an exit code it can never read ───────
# THIS GATE EXISTS BECAUSE ITS ABSENCE COST EIGHT RELEASES. v3.33.466-alpha would not publish:
# make_web_audio.sh:185 read `$SEAM_AUDIT … ; _seam_ec=$?` under `set -euo pipefail`, so a
# non-zero audit killed the script BEFORE the assignment and the whole `case` below it was
# unreachable. The audit returned 1 -- "a bed crossed the 12 dB line" -- which the comment three
# lines above it declares NON-BLOCKING, and it blocked every release instead. exit 2's BLOCKED
# message was equally dead. Only the exit-0 path ever ran, so the change was green in testing.
#
# The publish reported "audio tier build failed" with an EMPTY reason, because the gate's own
# output never printed. Three sites existed; two more were in deploy_desktop.sh and deploy_web.sh,
# both documenting "only EC 2 blocks" while unable to print their own BLOCKED diagnostic.
if [ -f tools/check_exit_capture.py ]; then
    if ! _ST=$(python3 tools/check_exit_capture.py --selftest 2>&1); then
        printf '%s\n' "$_ST" | tail -25 >&2
        echo "[pub] BLOCKED: tools/check_exit_capture.py FAILED ITS OWN SELFTEST — the dead-arm" >&2
        echo "      detector is not answering correctly, so its verdict on this tree means" >&2
        echo "      nothing. A present guard is not a working one." >&2
        exit 4
    fi
    echo "[pub] selftest ok: tools/check_exit_capture.py (dead exit-capture detector) — arms ran and passed"
    if ! python3 tools/check_exit_capture.py; then
        echo "[pub] BLOCKED: a guard in this chain captures an exit code it can never read — see above." >&2
        echo "      Refusing to publish behind a case whose non-zero arms are dead code." >&2
        exit 4
    fi
else
    echo "[pub] BLOCKED: tools/check_exit_capture.py missing — nothing has checked that this" >&2
    echo "      chain's error arms are reachable. A missing guard is not a passing one." >&2
    exit 4
fi

# ── 0a-2. every invocation that can write user:// redirects it ───────────────
# 2026-09-16: struktured's live profile took five log rotations from this chain in one day, each
# three seconds before this lane's own archived boot log for .355 · .356 · .357 · .358. Godot
# keeps exactly five, so his own play traces were gone from the ring. The cause was the boot
# gate running the EXPORTED BINARY with no redirect — a line with no `godot` on it, invisible to
# every sandbox rule any lane carries.
#
# This runs BEFORE the batch because it is the publish itself that would do the writing.
if [ -x tools/check_user_data_sandboxed.py ]; then
    if ! _ST=$(./tools/check_user_data_sandboxed.py --selftest 2>&1); then
        printf '%s\n' "$_ST" | tail -25 >&2
        echo "[pub] BLOCKED: tools/check_user_data_sandboxed.py FAILED ITS OWN SELFTEST — the" >&2
        echo "      user:// redirect detector is not answering correctly, so its verdict on this" >&2
        echo "      tree means nothing. A present guard is not a working one." >&2
        exit 4
    fi
    echo "[pub] selftest ok: tools/check_user_data_sandboxed.py (user:// redirect detector) — arms ran and passed"
    if ! ./tools/check_user_data_sandboxed.py; then
        echo "[pub] BLOCKED: a deploy invocation can write struktured's live user:// — see above." >&2
        echo "      Refusing to publish from a chain that would boot the game against his profile." >&2
        exit 4
    fi
else
    echo "[pub] BLOCKED: tools/check_user_data_sandboxed.py missing — nothing has checked that the" >&2
    echo "      deploy chain keeps out of his save directory. A missing guard is not a passing one." >&2
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
    if ! _ST=$(./tools/check_publish_is_optin.py --selftest 2>&1); then
        printf '%s\n' "$_ST" | tail -25 >&2
        echo "[pub] BLOCKED: tools/check_publish_is_optin.py FAILED ITS OWN SELFTEST — the --publish detector" >&2
        echo "      is not answering correctly, so its verdict on this tree means" >&2
        echo "      nothing. A present guard is not a working one." >&2
        exit 4
    fi
    echo "[pub] selftest ok: tools/check_publish_is_optin.py (--publish detector) — arms ran and passed"
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

# ── gate 0c: the raw bytes must be the bytes the tag pins ────────────────────────────
# ⛔ MUST RUN BEFORE ANY --import. Audio is git-lfs; the tracked blob is a pointer and the bytes
# live in the LFS store. Every other gate in this chain reads a RE-DERIVED artifact — the suite
# and check_pck_complete read the .oggstr, the export packs it, and `--import` rebuilds it
# faithfully from whatever bytes are on disk. So a tree with a stale LFS blob produces a
# perfectly coherent build of LAST WEEK'S AUDIO and every downstream gate reports green: the
# instrument and the defect share a cause. Measured 2026-09-11: nothing in tools/ compared a
# pointer's oid to a file's sha256, and the one LFS reference that existed only refused to
# MEASURE a pointer.
#
# 2.29s for 500 files, no network, no godot — against a ~45min publish.
if [ -x tools/check_lfs_blobs_current.py ]; then
    if ! _ST=$(./tools/check_lfs_blobs_current.py --selftest 2>&1); then
        printf '%s\n' "$_ST" | tail -25 >&2
        echo "[pub] BLOCKED: tools/check_lfs_blobs_current.py FAILED ITS OWN SELFTEST — the byte" >&2
        echo "      comparator is not answering correctly, so its verdict on this tree means" >&2
        echo "      nothing. A present guard is not a working one." >&2
        exit 4
    fi
    echo "[pub] selftest ok: tools/check_lfs_blobs_current.py (LFS byte comparator) — arms ran and passed"
    if ! ./tools/check_lfs_blobs_current.py; then
        echo "[pub] BLOCKED: an LFS blob on disk is not the blob this commit pins — see above." >&2
        echo "      Publishing now would ship audio the tag does not name. Fix the BYTES first;" >&2
        echo "      re-importing makes the layer unknowable and the green never arrives." >&2
        exit 4
    fi
else
    echo "[pub] BLOCKED: tools/check_lfs_blobs_current.py missing — nothing has checked that the" >&2
    echo "      audio on disk is the audio this commit pins. Every other gate reads the" >&2
    echo "      re-derived artifact and cannot tell. A missing guard is not a passing one." >&2
    exit 4
fi

# ── 0d. the SHELL guards check themselves too ────────────────────────────────
# Gates 0/0b/0c run three .py guards' selftests. The shell tools on this same path had none
# run by anything — 13 of them carry a --selftest and nothing ever executed one.
#
# ⛔ THE LIST IS EXPLICIT ON PURPOSE. The tempting version discovers it: every tools/*.sh
# containing "--selftest". Do not. `reap_release_worktrees.sh --selftest` used to run a
# repo-global `git worktree prune`, which deregisters ANY worktree whose directory is
# momentarily absent — ~134 of them here, nearly all other lanes'. Discovery would have run
# that as a side effect of checking that a guard works. A selftest is arbitrary code this
# script did not write, and `--selftest` is a naming convention, not a safety contract, so
# running one is a decision this file OWNS rather than one it derives. (@cowir-adhoc)
#
# MEMBERSHIP RULE for the list: the publish chain actually EXECUTES the tool, and its
# selftest is cheap. Derived by walking what publish_all/deploy_* invoke BY BASENAME with
# comments stripped — a literal `tools/x.sh` pattern both invents names out of fixture
# strings and misses `$(dirname "$0")/deploy_desktop.sh`, so it got the corpus wrong in both
# directions before this was checked against what the .340 logs show actually ran.
#
# NOT LISTED, each named with its reason rather than quietly dropped:
#   (verify_store_artifact.sh was exempted here at 36.13s. Its cost was two O(n) -> O(n^2)
#    defects in its own code, not an inherent price: compare() spawned one awk PER FILE to
#    re-scan the whole other manifest, and _manifest() spawned TWO processes per file. Both
#    fixed; the selftest is 0.38s and it is in the list above.)
#   publish_detached.sh       19.32s, and it has already done its job before this runs
#   check_fold_train.sh · rehearse_publish.sh · reap_release_worktrees.sh   OFF the chain
#   publish_all.sh            has NO selftest — it appears in greps for "--selftest" only
#                             because it invokes others', which is how it got miscounted
# Total added: ~2.6s against a chain that runs 45s-45min.
# ⛔ check_tree_unmoved.sh AND release_note.sh WERE MISSING FROM THIS LIST WHILE BEING INVOKED
# BY THIS SCRIPT. Measured 2026-09-17: both carry selftests (11 and 23 arms) and the publish ran
# neither, so their arms were written, committed, and never exercised by the path whose verdict
# depends on them -- the same gap check_web_audio_tier_selftest.py had until gate 3c ran it.
# The list is the thing that decides, so a tool added to the chain without being added here is
# silently unchecked; that is why they are adjacent in this file and why this comment is here.
# ⛔ THIS LIST USED TO BE HAND-WRITTEN, AND A HAND-WRITTEN CORPUS FAILS SILENT.
# I widened it 11 -> 13 on 2026-09-17 because check_tree_unmoved.sh and release_note.sh were
# being INVOKED by this chain with their arms never running. By that evening it was short
# again: export_sandbox.sh, seed_gate_saves.sh and check_hydration_exercised.sh were all
# invoked here and all unchecked. Widening a hand-list by hand is the defect with a fresh date.
#
# export_sandbox.sh is the one that matters: it builds the redirected data root that keeps
# --export-release off struktured's live profile. Its arms had never run on a publish.
#
# Derived instead, from two properties this chain can compute about itself:
#   1. the TRANSITIVE CLOSURE of what publish_all.sh invokes
#   2. AND the tool DISPATCHES on --selftest (not merely mentions it)
#
# (2) is not a substring search. make_web_audio.sh contains the string --selftest three times,
# all of them explaining that it has none -- it takes a bitrate, and says so because passing
# --selftest once created a tier directory named "music_--selftestk". A corpus built on
# `grep -l -- --selftest` includes it and blocks every publish on a usage error.
# Derivation moved OUT of this file 2026-09-18 -> tools/derive_selftest_corpus.py, so that the
# guard deciding which OTHER guards get checked could finally have arms of its own. This file
# is the one script on the path that by convention has no selftest, so anything living inside
# it is untestable by construction. Contract: stdout = the corpus, nonzero = blocked, reason
# on stderr.
#
# The reason is CAPTURED, not left on the terminal: this BLOCKED line used to interpolate
# ${_ST_CORPUS}, which on the failure path is EMPTY by definition -- it promised a reason and
# printed a blank. A label that cannot carry its own content is not reporting.
mkdir -p tmp
_ST_ERRF="tmp/derive_selftest_corpus.err"
_ST_CORPUS="$(python3 tools/derive_selftest_corpus.py 2>"$_ST_ERRF")" || {
    echo "[pub] BLOCKED: could not derive the selftest corpus: $(cat "$_ST_ERRF" 2>&1)" >&2
    exit 4; }
if [ -z "$_ST_CORPUS" ]; then
    echo "[pub] BLOCKED: the derived selftest corpus is EMPTY. An empty corpus runs no arms and" >&2
    echo "      reports the same silence as a corpus that passed." >&2
    exit 4
fi
_ST_N=0
for _t in $_ST_CORPUS; do
    # HOW to run it depends on the convention, and the derivation admits both. A .sh is
    # executed; a .py is handed to python3, so its executable bit is not the question — asking
    # for -x on a python tool would BLOCK the publish over a file mode that means nothing here.
    _st_target="tools/$_t"; _st_kind="exec"
    case "$_t" in
        *.py)
            if [ -f "tools/${_t%.py}_selftest.py" ]; then
                _st_target="tools/${_t%.py}_selftest.py"; _st_kind="py-sibling"
            else
                _st_kind="py-flag"
            fi ;;
    esac
    if [ ! -f "$_st_target" ] || { [ "$_st_kind" = "exec" ] && [ ! -x "$_st_target" ]; }; then
        echo "[pub] BLOCKED: ${_st_target} missing or not runnable — tools/$_t is on the" >&2
        echo "      publish path and nothing has checked that it still works. A missing" >&2
        echo "      guard is not a passing one." >&2
        exit 4
    fi
    case "$_st_kind" in
        exec)       _ST=$(./"$_st_target" --selftest 2>&1) ;;
        py-flag)    _ST=$(python3 "$_st_target" --selftest 2>&1) ;;
        py-sibling) _ST=$(python3 "$_st_target" 2>&1) ;;
    esac
    # shellcheck disable=SC2181
    if [ $? -ne 0 ]; then
        printf '%s\n' "$_ST" | tail -25 >&2
        echo "[pub] BLOCKED: tools/$_t FAILED ITS OWN SELFTEST. It runs on this publish path," >&2
        echo "      so its output cannot be trusted for this build. A present guard is not a" >&2
        echo "      working one." >&2
        exit 4
    fi
    echo "[pub] selftest ok: tools/$_t — arms ran and passed (${_st_kind})"
    _ST_N=$((_ST_N+1))
done
echo "[pub] selftests: $_ST_N tool(s), derived from what this chain invokes (was a hand-list)"

# ── 0d. NO SHELL TOOL MAY EXPAND A VARIABLE IT NEVER ASSIGNS ─────────────────
# v3.33.409-alpha went RED with nothing published on:
#     ./tools/deploy_desktop.sh: line 599: _RAW_TOOLS: unbound variable
# I wrote one gate block and pasted it into two files with different preludes.
# deploy_web.sh defined _RAW_TOOLS; deploy_desktop.sh defined _RAW_CHECK inline
# and never _RAW_TOOLS. Under `set -u` that is fatal, and NOTHING above could
# see it: `bash -n` parses fine because an unbound expansion is a RUNTIME error,
# the selftests exercise the python guards rather than their shell call sites,
# and my own extraction harness SET _RAW_TOOLS in its preamble -- the test
# supplied the precondition the file lacked. It was reachable only on a real
# publish, after the builds were made and past every check on this page.
# So the check has to be static, it has to run here, and it has to cover every
# tool -- the defect is in the CALL SITE, not in the guard being called.
_UV_DIR="$(cd "$(dirname "$0")" && pwd)"
_UV_CHECK="${_UV_DIR}/check_unbound_vars.py"
_UV_SELFTEST="${_UV_DIR}/check_unbound_vars_selftest.py"
if [ ! -f "$_UV_CHECK" ] || [ ! -f "$_UV_SELFTEST" ]; then
    echo "[pub] BLOCKED: tools/check_unbound_vars.py or its selftest is missing. The bug that" >&2
    echo "      killed .409 is invisible to every other check on this page; absence of the" >&2
    echo "      detector is not absence of the defect." >&2
    exit 4
fi
if ! _UV_ST=$(python3 "$_UV_SELFTEST" 2>&1); then
    printf '%s\n' "$_UV_ST" | tail -30 >&2
    echo "[pub] BLOCKED: check_unbound_vars.py FAILED ITS OWN SELFTEST." >&2
    exit 4
fi
echo "[pub] selftest ok: tools/check_unbound_vars.py — $(printf '%s\n' "$_UV_ST" | command grep -oE '[0-9]+ arm\(s\), [0-9]+ refereed by bash' | tail -1)"
# TRACKED files, not a glob. A glob scans whatever happens to be sitting in
# tools/ -- a scratch copy, a half-written probe -- and lets an untracked file
# block a publish. Measured: a truncated probe left in tools/ took this gate to
# exit 4 on a clean tree. git ls-files is also the stronger corpus, because a
# tool that is committed is a tool the chain can invoke.
_UV_REPO="$(cd "$_UV_DIR/.." && pwd)"
_UV_LIST="$(cd "$_UV_REPO" && git ls-files 'tools/*.sh' 2>/dev/null)"
if [ -z "$_UV_LIST" ]; then
    echo "[pub] BLOCKED: could not list tracked shell tools (git ls-files returned nothing)." >&2
    echo "      An empty corpus scans clean, which is the failure this gate exists to stop." >&2
    exit 4
fi
case "$_UV_LIST" in
    *" "*) echo "[pub] BLOCKED: a tracked tool path contains a space; this gate splits on" >&2
           echo "      whitespace and would scan the wrong files." >&2; exit 4 ;;
esac
_UV_OUT=""; _UV_EC=0
# shellcheck disable=SC2086
_UV_OUT=$(cd "$_UV_REPO" && python3 "$_UV_CHECK" $_UV_LIST 2>&1) || _UV_EC=$?
if [ "$_UV_EC" -ne 0 ]; then
    printf '%s\n' "$_UV_OUT" | command grep -E 'UNBOUND' >&2
    echo "[pub] BLOCKED: a shell tool expands a variable it never assigns. Under set -u that" >&2
    echo "      aborts the moment the line is REACHED, which on this chain is after the" >&2
    echo "      builds are made — exactly how .409 published nothing." >&2
    exit 4
fi
# COVERAGE, not a printed number. The first version of this line counted with a
# pattern that never matched and announced "0 shell tool(s) scanned" beside a
# PASS -- an empty corpus scanning clean, which is the exact failure the
# git ls-files guard above refuses, reproduced in the success message. The two
# counts come from different places on purpose: the denominator from the file
# list, the numerator from the tool's own output. A shared source would move
# them together and could not detect a scan that quietly did nothing.
_UV_WANT=$(printf '%s\n' "$_UV_LIST" | command grep -c .)
_UV_GOT=$(printf '%s\n' "$_UV_OUT" | command grep -c '^\[unbound-vars\] ')
if [ "$_UV_GOT" -ne "$_UV_WANT" ]; then
    echo "[pub] BLOCKED: the unbound-vars scan reported on $_UV_GOT tool(s) but $_UV_WANT are" >&2
    echo "      tracked. A file that was not examined cannot have been found clean." >&2
    exit 4
fi
echo "[pub] unbound-vars: $_UV_GOT of $_UV_WANT tracked shell tool(s) scanned, 0 expand a name they never assign"

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

# ── the run's build-SHA label, fixed ONCE ────────────────────────────────────────────────────
# v3.33.312-alpha shipped TWO labels across three channels from one line of deploy_desktop.sh:
# linux got +befbe408 and windows +befbe4083, two minutes apart. `git rev-parse --short` returns
# the shortest length unambiguous AT THAT MOMENT, and that length scales with object count --
# this repo has 125 worktrees with lanes pushing throughout a publish, so it grew 8 -> 9 mid-run.
# Read once here, exported, used verbatim by every chain. The chains still compute it themselves
# when run standalone, which is the documented recovery path at line 281.
PUBLISH_BUILD_SHA="$(./tools/build_sha.sh)" || {
    echo "[pub] BLOCKED: tools/build_sha.sh could not produce a build label." >&2; exit 2; }
export PUBLISH_BUILD_SHA
echo "[pub] build label for this run: ${PUBLISH_BUILD_SHA} (fixed once; every channel uses it)"
if [ "$DIRTY" -ne 0 ]; then
    echo "[pub] BLOCKED: ${DIRTY} uncommitted change(s). The export ships the working tree." >&2
    exit 2
fi
echo "[pub] tree: ${HEAD_SHA:0:8} == ${TAG}, clean"

# ── record the gated tree ────────────────────────────────────────────────────────────────────
# The check above is taken BEFORE any artifact exists; the chains export the working tree ~25
# minutes later. Nothing re-checked it, and the store read-back structurally cannot: it compares
# the store against the LOCAL BUILD, so a tree that moved after the gate produces two agreeing
# sides that are both downstream of the change.
_TREE_REC="tmp/gated_tree.fingerprint"
if [ -x tools/check_tree_unmoved.sh ]; then
    ./tools/check_tree_unmoved.sh --record "$TAG" "$_TREE_REC" || true
fi

SAVES_BEFORE="$(_saves_cksum)"
SAVES_CTIME_BEFORE="$(_saves_ctime_max)"
echo "[pub] his saves before: ${SAVES_BEFORE}"

# ── what the store is superseding ────────────────────────────────────────────────────────────
# Captured BEFORE the upload, because afterwards the answer is this tag. It is passed to
# release_note.sh as --prev so the note describes what a PLAYER is receiving rather than what
# changed since the previous tag.
#
# Those differ whenever supersession skips tags — this lane publishes the NEWEST tag only, and
# a held store accumulates. Measured 2026-09-17 mid-hold, store on .371 with .379 tagged:
# the default note said 2 branches / 7 commits; the range a player actually gets was
# 59 branches / 157 commits / 96 files. A 30x under-description of a release nobody can inspect.
#
# THE OLDEST channel wins, not linux: a partial store means the least-current channel decides
# what some players are still missing, which is the same rule store_status.sh already encodes.
# Unreadable -> empty -> release_note.sh falls back to the previous tag and says so, which is
# the behaviour that shipped for the last eighty releases.
STORE_BEFORE="$(butler status struktured/cowardly-irregular 2>/dev/null \
    | awk -F'|' '/\| *(linux|windows|web) *\|/ {gsub(/[ \t]/,"",$5); sub(/\+.*$/,"",$5); if ($5 != "") print $5}' \
    | sort -V | head -1)"
if [ -n "$STORE_BEFORE" ]; then
    echo "[pub] store is on ${STORE_BEFORE} before this publish (oldest channel)"
else
    echo "[pub] could not read the store's current version — the release note will fall back to the previous TAG" >&2
fi

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
# ⛔ BOUNDED, BECAUSE A WEDGE HERE IS NOT A RED — IT IS NO VERDICT AT ALL AND IT NEVER ENDS.
# 2026-09-19: @cowir-main's fold gate spun 1h57m at 100% on one non-main thread with the log
# frozen, because nothing bounded the godot run. The same shape here is worse: this publish is
# launched DETACHED, so a wedge writes no publish.ec, and `publish_detached.sh --status` waits
# on that file. A hang would present as a release that simply never happens.
#
# ⚠️ THIS WAS AN INLINE `timeout` BLOCK FOR ONE HOUR AND THE INLINE FORM HAD TWO DEFECTS OF ITS
# OWN — it named elapsed and budget when it blocked and said NOTHING when it passed, and its
# message would have landed inside the caller's redirection at the five sibling sites. Both are
# fixed in tools/bounded_godot.sh, which also carries the measurements (uutils timeout cannot
# deliver SIGKILL; the verdict is ELAPSED, never the exit code) in ONE place rather than six.
# 1800s is ~10x the observed import time (161s worst case across nine releases).
PUBLISH_IMPORT_BUDGET="${PUBLISH_IMPORT_BUDGET:-1800}"
IMPORT_EC=0
XDG_DATA_HOME="$PWD/tmp/prewarm_xdg" ./tools/bounded_godot.sh \
    --label "publish import" --budget "$PUBLISH_IMPORT_BUDGET" --log tmp/publish_all_import.log -- \
    godot --headless --audio-driver Dummy --import --quit || IMPORT_EC=$?
if [ "$IMPORT_EC" -eq 124 ]; then
    echo "[pub] BLOCKED: no verdict on the import (see above) — the tree is UNJUDGED, not red." >&2
    echo "[pub]   Raise it with PUBLISH_IMPORT_BUDGET=<seconds> if the box is genuinely slow." >&2
    exit 4
fi
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

# ONE spelling of the bitrate, shared with deploy_web.sh via the environment. This step used to
# say 48 in three places — the message, the argument and the directory it then counted — so a tier
# change that missed one would prebuild one tier and count another, and report the count as proof.
# struktured's ruling 2026-09-16 moved web music to 40k; see deploy_web.sh for why the lever is here.
WEB_AUDIO_KBPS="${WEB_AUDIO_KBPS:-40}"
export WEB_AUDIO_KBPS
echo "[pub] prebuild: ${WEB_AUDIO_KBPS}k audio tier"
if ! ./tools/make_web_audio.sh "$WEB_AUDIO_KBPS" > tmp/publish_all_audio.log 2>&1; then
    echo "[pub] BLOCKED: audio tier build failed — see tmp/publish_all_audio.log" >&2
    exit 4
fi
TIER_N="$(find "tmp/web_audio/music_${WEB_AUDIO_KBPS}k" -name '*.ogg' 2>/dev/null | wc -l)"
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
        # "Published so far: linux windows" above is an EVENT — how far THIS RUN got. What the
        # operator has to act on is the STATE: whether the store is serving two different
        # releases right now. v3.33.422-alpha did exactly that (linux+windows .422, web .421)
        # and the line that said so was indistinguishable from a progress report.
        #
        # ⚠️ REPORTS, NEVER GATES, and the `|| true` is deliberate rather than sloppy: this runs
        # on a path that is ALREADY exiting non-zero for a real reason, and a reporter that
        # failed must not replace that verdict with its own. "A missing guard is not a passing
        # one" is the rule for GUARDS; converting a channel RED into a reporter RED would lose
        # the diagnosis the operator actually needs.
        if [ "$DRY_RUN" -eq 0 ] && [ -x tools/report_split_store.sh ]; then
            ./tools/report_split_store.sh "$TAG" "$PUBLISHED" >&2 || true
        fi
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

# THIS IS NOW THE AUTHORITATIVE CHECK, and it has to ASSERT rather than print.
#
# The per-channel post-push confirmation in deploy_desktop.sh was fatal: on .294 it exited 4
# after ~5 minutes because itch was still processing a push that had in fact succeeded, and
# this batch stopped with the store SPLIT across two versions. That confirmation is now
# advisory — which is only defensible if something store-wide is authoritative, and printing a
# table is not that. A human reads a table; a gate reads an exit code.
#
# store_status.sh checks ALL THREE channels against the newest tag on origin and exits 1 when
# any is behind. That is exactly the question "did this batch land", and it is immune to one
# channel's processing lag because it runs after the last push.
if [ -x tools/store_status.sh ]; then
    if ! ./tools/store_status.sh; then
        echo "[pub] BLOCKED: the store is NOT current after publishing ${PUBLISHED}." >&2
        echo "      One or more channels did not register. If a channel was still processing," >&2
        echo "      re-run tools/store_status.sh in a few minutes before concluding it failed;" >&2
        echo "      if it stays behind, that channel did not ship." >&2
        echo "[pub] his saves after: $(_saves_cksum)  (before: ${SAVES_BEFORE})" >&2
        exit 1
    fi
else
    echo "[pub] BLOCKED: tools/store_status.sh missing — nothing authoritative checked that" >&2
    echo "      this batch actually landed. Refusing to report success." >&2
    exit 2
fi

SAVES_AFTER="$(_saves_cksum)"
SAVES_CTIME_AFTER="$(_saves_ctime_max)"
if [ "$SAVES_AFTER" = "$SAVES_BEFORE" ]; then
    if [ "$SAVES_CTIME_AFTER" = "$SAVES_CTIME_BEFORE" ]; then
        echo "[pub] his saves: ${SAVES_AFTER} unchanged, and untouched during the run"
    else
        echo "[pub] ⚠ his saves are IDENTICAL but were TOUCHED during this publish:"
        echo "      newest ctime ${SAVES_CTIME_BEFORE} -> ${SAVES_CTIME_AFTER}"
        echo "      Content matches, so nothing was lost — but something on the publish path"
        echo "      wrote his saves and restored them. The checksum cannot see that; find the"
        echo "      writer with tools/check_user_data_sandboxed.py before the next release."
    fi
else
    echo "[pub] ⚠ his saves CHANGED: ${SAVES_BEFORE} -> ${SAVES_AFTER}"
    echo "      Not necessarily a fault — he may have been playing. Diff against"
    echo "      tmp/userdata_snapshot/ before concluding anything."
fi
# ── 7. the store read-back, opt-in ───────────────────────────────────────────────────────
# The ONLY check in this lane that crosses the CDN. Everything above tested the local artifact
# or asked butler what it was asked to push.
#
# ✅ EXERCISED 2026-09-11, three directions, with verify_store_artifact.sh stubbed so no network
# or credentials were needed — block extracted byte-exact from this file and verified to occur
# verbatim once:
#     store matches, linux+web            exit 0, READBACK_DONE=1
#     store DIFFERS on one channel        exit 5
#     a published channel's build gone    exit 5
# Recorded because until then this block had been WIRED and never RUN. @cowir-autogrind,
# 2026-09-11: "a dense verification suite around an unreachable edit produces maximum confidence
# and zero information." I had verified the flag parsing, the exit trap, the message text and
# five trap states — all of it about the wiring, none of it executing the thing wired.
if [ "${READ_BACK:-0}" = "1" ] && [ -n "${PUBLISHED:-}" ]; then
    echo "[pub] ─── store read-back ───"
    _rb_fail=0
    for _c in ${PUBLISHED}; do
        case "$_c" in
            web) _rbdir="builds/web" ;;
            *)   _rbdir="build/${_c}" ;;
        esac
        if [ ! -d "$_rbdir" ]; then
            echo "[pub] BLOCKED: ${_c}'s local build ${_rbdir} is gone; nothing to compare." >&2
            _rb_fail=1; continue
        fi
        # The verdict is the tool's, not a summary of its exit status. verify_store_artifact.sh
        # separates 5 (the store differs) from 2 (it could not evaluate — no butler, a missing
        # dir, or the version guard refusing a comparison between two different releases). This
        # used to print "STORE DIFFERS" for both, which accuses the store of serving bad bytes
        # when the truth may be that nothing was compared at all.
        ./tools/verify_store_artifact.sh "$_c" "$_rbdir"; _rbec=$?
        case "$_rbec" in
            0) echo "[pub]   ${_c}: store matches what we built" ;;
            5) echo "[pub]   ${_c}: STORE DIFFERS from what we built — see above" >&2; _rb_fail=1 ;;
            *) echo "[pub]   ${_c}: read-back COULD NOT EVALUATE (exit ${_rbec}) — see above." >&2
               echo "[pub]        This is not a statement about the store; nothing was compared." >&2
               _rb_fail=1 ;;
        esac
    done
    READBACK_DONE=1
    if [ "$_rb_fail" -ne 0 ]; then
        echo "[pub] read-back FAILED for at least one channel." >&2
        exit 5
    fi
fi

echo "[pub] done: ${PUBLISHED}"
exit 0
