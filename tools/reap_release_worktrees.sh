#!/usr/bin/env bash
# Reclaim the disk that per-tag release worktrees consume, without destroying anything that
# is not reconstructible from a tag.
#
# WHY THIS EXISTS
# ---------------
# The deploy lane cuts a fresh worktree per published tag so the export is provably AT the
# tag. Each one costs ~2.1 GB. Measured 2026-09-10 after 35 tags: 54 worktrees, 84 GB, on a
# box at 93% with 267 GB free. At an hourly publish cadence that is ~50 GB/day, so the lane
# whose job is to publish would have exhausted the disk and lost the ability to publish
# inside a week. The mess was mine and manual cleanup guarantees it recurs.
#
# WHAT IS SAFE TO DELETE, AND WHY
# -------------------------------
# A release worktree is DETACHED AT A PUBLISHED TAG with no tracked modifications. Its entire
# tracked content is reconstructible: `git worktree add --detach <path> <tag>` returns it
# byte-identical (verified 2026-09-10: recreated rel-291 from v3.33.291-alpha, `git diff` vs
# the tag = 0 lines). What is NOT in git is the .godot import cache (regenerable), build
# artifacts (regenerable), the deploy logs, and the gate 0b snapshot of struktured's live
# user:// profile.
#
# The logs are the evidence trail behind published claims, so they are ARCHIVED, not deleted
# — 553 of them came to 62 MB against 69 GB reclaimed. The userdata snapshots were 36
# byte-identical copies of a profile that is intact on disk; one is preserved.
#
# FAILURE DIRECTION
# -----------------
# Dry-run is the DEFAULT. Every safety rule is a refusal, and a worktree is removed only when
# every one of them affirmatively passes — absence of a reason to keep is never a reason to
# delete. A path that does not sit under the expected prefix is refused even if git agrees it
# is a worktree.
#
# Usage:  tools/reap_release_worktrees.sh                 dry run, keep 2 newest
#         tools/reap_release_worktrees.sh --apply         actually remove
#         tools/reap_release_worktrees.sh --keep 4 --apply
#         tools/reap_release_worktrees.sh --selftest
# Env:    REAP_PREFIX  (default "tmp/rel-")   REAP_ARCHIVE (default "tmp/_archive")
#         REAP_SCAN    (default "tmp/")       REAP_ROOT    (default this checkout)
#
#         REAP_ROOT points the LOOKING at another checkout's worktrees. It widens nothing:
#         every refusal is per-worktree and none of them reads the root. Needed because
#         this script cd's to its own repo on startup, so without it the reaper can only
#         see its own tmp/ — however the caller invokes it.
#           REAP_ROOT=/home/struktured/projects/cowir-deploy-wt tools/reap_release_worktrees.sh
# Exit:   0 ok · 2 usage/precondition

set -uo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

PREFIX="${REAP_PREFIX:-tmp/rel-}"
# What we LOOK at. Detached worktrees must still sit under PREFIX; SCAN only widens the scan so
# branch worktrees can be CONSIDERED under --merged-branches. Never widen SCAN past tmp/.
SCAN="${REAP_SCAN:-tmp/}"
# ⛔ WHERE we look. This used to be an implicit `$PWD`, which the startup cd has already forced to THIS
# script's own checkout — so the reaper could only ever see its own tmp/, whatever the caller did.
# On 2026-09-18 that put the box at 100% used with 49 release worktrees one level up in
# cowir-deploy-wt/tmp/, which is the same shape that red .431 on ENOSPC: the reaper reported
# "3.4G reclaimed, headroom fine" about two directories while fifty sat outside its reach.
# REAP_ROOT moves the LOOKING only. Every refusal below is per-worktree and reads none of this.
ROOT="${REAP_ROOT:-$PWD}"
ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || {
    echo "[reap] REAP_ROOT is not a directory: ${REAP_ROOT-}" >&2; exit 2; }
MERGED_BRANCHES=0
ARCHIVE="${REAP_ARCHIVE:-tmp/_archive}"
KEEP=2
APPLY=0

while [ $# -gt 0 ]; do
    case "$1" in
        --apply)    APPLY=1; shift ;;
        --keep)     KEEP="${2:-2}"; shift 2 ;;
        --selftest) selftest_requested=1; shift ;;
        --merged-branches) MERGED_BRANCHES=1; shift ;;
        *)          echo "usage: $0 [--apply] [--keep N] [--merged-branches] [--selftest]" >&2; exit 2 ;;
    esac
done

# The remote these calls ask. Indirected ONLY so the selftest can point at a local bare repo
# and stop depending on github being reachable six times; production leaves it as "origin".
ORIGIN="${REAP_ORIGIN:-origin}"

# \u26d4 AN UNREACHABLE ORIGIN IS NOT AN EMPTY TAG SET. These used to be
#     git ls-remote ... 2>/dev/null
# with no exit-code check, so a failed network call returned NOTHING and every caller read that
# as "no tag on origin points at this tree" -- i.e. not reconstructible. Diagnosed 2026-10-13:
# the reaper selftest red 3 arms in 1 run of 6 on a quiet box, and GIT_SSH_COMMAND=/bin/false
# reproduces it on demand (4 arms). It had been recorded as a flake with "cause never found"
# for weeks, because `2>/dev/null` deleted git's "could not read from remote repository" and
# left only arm failures that read as logic errors. CLAUDE.md names the hazard exactly:
# "don't 2>/dev/null a measurement command -- it deletes the warning and keeps the wrong number."
#
# Now: the failure is its own LOUD verdict and it means UNKNOWN, which for a tool that deletes
# worktrees must read as KEEP. Exit 3 is "could not determine", never "nothing is reconstructible".
_remote_unreachable() { # $1 = git's stderr, $2 = exit code
    echo "[reap] BLOCKED: cannot reach ${ORIGIN} — reconstructibility is UNKNOWN." >&2
    echo "       Nothing is reaped. An unreachable remote is not evidence that a tree is" >&2
    echo "       unreconstructible; treating it as such is how a tool that deletes gets it wrong." >&2
    echo "       git ls-remote exited $2: $(printf '%s' "$1" | head -2 | tr '\n' ' ')" >&2
}

# The newest tag PROTECTS the worktree at it, so a short ls-remote reply (ec 0, tags after .616
# or .674 missing -- measured 2026-10-23) would move that guard onto an older tree. Resolved by
# tools/origin_tags.sh with this repo's own newest local tag as the FLOOR: we only ever learn a
# v3.33.* tag from origin, so origin naming an older "newest" is a stale reply, not news.
# A stale reply is UNKNOWN (3) and the reap refuses, the same as an unreachable remote.
# ⚠️ A local tag that origin has since DELETED trips the same FLOOR permanently; check it with
#    `git ls-remote origin refs/tags/<tag>`. That fails toward refusing, which is the safe side.
# shellcheck source=origin_tags.sh
. "$(dirname "${BASH_SOURCE[0]}")/origin_tags.sh" || {
    echo "[reap] BLOCKED: $(dirname "${BASH_SOURCE[0]}")/origin_tags.sh is missing, unreadable or did not parse. It is the" >&2
    echo "      newest-tag resolver this script sources. Without it no tag verdict is possible, and" >&2
    echo "      continuing would turn 'command not found' into a misleading refusal." >&2
    exit 3; }
# A lib that is PRESENT but defines nothing (zero bytes, a truncated copy, a conflict leftover)
# sources with status 0 and slips past the `||` above, so check the function itself. Found by
# @cowir-main: an empty lib gave store_status "command not found" + "no tag to compare against".
declare -F origin_newest_tag >/dev/null || {
    echo "[reap] BLOCKED: $(dirname "${BASH_SOURCE[0]}")/origin_tags.sh loaded but defined no origin_newest_tag" >&2
    echo "      (empty or truncated copy?). No tag verdict is possible without it." >&2
    exit 3; }
_newest_tag_on_origin() {
    local floor ec=0
    floor="$(git tag -l 'v3.33.*' --sort=-v:refname | head -1)"
    OT_REMOTE="$ORIGIN" origin_newest_tag reap "" "$floor" || ec=$?
    case "$ec" in
        0|2) return 0 ;;   # 2 = reachable, no v3.33.* tags: an empty newest, as before
        1)   _remote_unreachable "(origin_tags.sh printed git's own message above)" 1; return 3 ;;
        *)   echo "[reap] BLOCKED: origin's tag list contradicts this repo's (newest local ${floor})" >&2
             echo "       -- newest tag UNKNOWN, so the newest-tag guard cannot be placed. Nothing is reaped." >&2
             return 3 ;;
    esac
}

_origin_tags() {
    local out ec
    out="$(git ls-remote --tags "$ORIGIN" 'refs/tags/*' 2>&1)"; ec=$?
    [ "$ec" -eq 0 ] || { _remote_unreachable "$out" "$ec"; return 3; }
    printf '%s\n' "$out" | grep -v '\^{}' | awk '{print $2}' | sed 's#refs/tags/##'
}

# Reconstructible: HEAD is pointed at by a tag that EXISTS ON ORIGIN, so
#     git worktree add --detach <path> <tag>
# rebuilds the tree byte-identically. THAT is the property `tmp/rel-` was standing in for.
# A path prefix is a naming convention, and the publish flow's `tmp/pub<N>` trees are every
# bit as reconstructible as a `rel-` one -- they were refused for their NAME, not for
# anything true about their commit. Measured 2026-09-18 on the live lane: pub442..445 all
# sat on tags `git ls-remote --tags origin` lists, and all four were kept as "may be
# referenced by nothing else".
#
# NOTE this does NOT widen PREFIX. publish_all.sh is explicit that widening the prefix is the
# wrong repair, and it is right for the reason it gives. This asks the safety question
# directly instead of by naming convention.
#
# WARNING fails CLOSED. An unreachable origin yields an empty tag list, so nothing is
# reconstructible and every detached tree outside PREFIX is kept exactly as it was before
# this check existed. A network failure can only ever keep more, never remove more.
_recon_tag() {
    local wt="$1" tags="$2" h t
    [ -n "$tags" ] || return 0
    h="$(git -C "$wt" rev-parse HEAD 2>/dev/null)" || return 0
    [ -n "$h" ] || return 0
    for t in $(git tag --points-at "$h" 2>/dev/null); do
        if printf '%s\n' "$tags" | grep -Fxq -- "$t"; then printf '%s\n' "$t"; return 0; fi
    done
    return 0
}

# Worktrees under PREFIX, newest-numeric last. A rel-<sha> name has no ordinal, so it sorts
# before every numbered one and is therefore never mistaken for recent.
_candidates() {
    git worktree list --porcelain 2>/dev/null \
        | awk '/^worktree /{w=$2} /^detached/{print w" DETACHED"} /^branch /{print w" "$2}' \
        | while read -r p state; do
              case "$p" in
                  "$ROOT/$SCAN"*) printf '%s\t%s\n' "$p" "$state" ;;
              esac
          done | sort -V
}

reap() {
    local newest_tag total=0 kept=0 removed=0 refused=0
    # \u26d4 ABORT, do not proceed with an unknown. Exit 3 from either call means the remote could
    # not be reached, and with no tag list every tree outside PREFIX silently stops being
    # reconstructible -- which in a --apply run is the difference between "keep it, I cannot tell"
    # and "delete it, I found no tag". The verdict has already been printed by the helper.
    local _tec=0
    newest_tag="$(_newest_tag_on_origin)" || _tec=$?
    local origin_tags _oec=0
    origin_tags="$(_origin_tags)" || _oec=$?
    if [ "$_tec" -eq 3 ] || [ "$_oec" -eq 3 ]; then
        echo "[reap] refusing to judge ${total:-0} worktree(s) against a remote it cannot read." >&2
        return 3
    fi
    # A reachable origin that genuinely has no tags is a different thing and stays a note.
    [ -z "$origin_tags" ] && echo "[reap] note: no tags readable from ${ORIGIN} — every detached worktree outside ${PREFIX} will be kept" >&2

    local rows; rows="$(_candidates)"
    if [ -z "$rows" ]; then
        # ⛔ SAY WHAT WAS LOOKED AT, NOT JUST THAT NOTHING WAS FOUND. The old line named PREFIX
        # while the filter is ROOT/SCAN, so a run rooted at the wrong tree printed a clean-looking
        # "no worktrees" that is indistinguishable from a tidy box — which is exactly how 49
        # worktrees accumulated while the tool reported success. A zero is only information once
        # it says which population it is a zero over.
        local registered; registered="$(git worktree list --porcelain 2>/dev/null \
            | command grep -ac '^worktree ' || true)"
        echo "[reap] no worktrees under ${ROOT}/${SCAN} — 0 of ${registered:-0} registered worktree(s) are under this root"
        [ "${registered:-0}" -gt 1 ] && echo "[reap] if the population you meant lives elsewhere, set REAP_ROOT=<dir>"
        return 0
    fi
    total="$(printf '%s\n' "$rows" | wc -l)"

    # The newest KEEP entries are protected by position alone.
    # ⛔ Computed over DETACHED worktrees under PREFIX only. SCAN widening must not let a
    # branch worktree occupy one of the protected slots and push a release tree out of them —
    # that would silently weaken the rule this line exists to enforce.
    local protected
    # ⛔ The ADMITTED set feeds the protected slots, not the prefix. If a reconstructible
    # tree can be REMOVED it must also be able to be PROTECTED -- otherwise admitting it
    # strips the newest-KEEP guard from exactly the trees this change started reaping, which
    # is the failure the note above warns about arriving by the other door. With nothing
    # reconstructible outside PREFIX this yields precisely the old awk's list.
    protected="$(printf '%s\n' "$rows" | while IFS="$(printf '\t')" read -r _p _s; do
        [ "$_s" = "DETACHED" ] || continue
        case "$_p" in "$ROOT/$PREFIX"*) printf '%s\n' "$_p"; continue ;; esac
        [ -n "$(_recon_tag "$_p" "$origin_tags")" ] && printf '%s\n' "$_p"
    done | tail -n "$KEEP")"

    printf '%s\n' "$rows" | while IFS="$(printf '\t')" read -r p state; do
        local n; n="$(basename "$p")"
        local reason=""

        case "$protected" in *"$p"*) reason="among the ${KEEP} newest" ;; esac
        # A branch worktree is refused unless --merged-branches AND every one of three
        # affirmative checks passes. Absence of a reason to keep is never a reason to delete:
        # the branch must be FULLY MERGED into origin/main (its content survives in main) and
        # PUSHED (its ref survives on origin), so removing the worktree loses nothing that is
        # not regenerable. Removing a worktree never deletes the branch.
        if [ -z "$reason" ] && [ "$state" != "DETACHED" ]; then
            local br="${state#refs/heads/}"
            if [ "$MERGED_BRANCHES" -ne 1 ]; then
                reason="on a branch (${br}) — may hold unpushed work; --merged-branches to consider it"
            elif ! git merge-base --is-ancestor "$br" origin/main 2>/dev/null; then
                reason="branch ${br} is NOT merged into origin/main"
            elif ! git ls-remote --exit-code --heads "$ORIGIN" "$br" >/dev/null 2>&1; then
                reason="branch ${br} is not on origin — its ref would be local-only"
            fi
        fi
        if [ -z "$reason" ]; then
            # ⛔ `git status --porcelain` COUNTS UNTRACKED FILES, so a single count reported as
            # "tracked modification(s)" is wrong whenever the dirt is untracked -- and untracked
            # is the case that matters most here. Measured 2026-09-19: three worktrees under
            # cowir-deploy-wt/tmp/ reported "1-3 tracked modification(s)" with `git diff
            # --shortstat` EMPTY; the dirt was three untracked `tools/store_shot_*.gd` files,
            # one of which (`store_shot_storm.gd`, 207 lines) had never been committed anywhere
            # and carried a measured finding. The refusal was right and its SENTENCE was not:
            # it sent the reader to a diff that shows nothing.
            #
            # The distinction is load-bearing for a tool that removes directories. A tracked
            # modification is recoverable from the tag; an untracked file exists on this disk
            # and nowhere else, so it is the stronger reason to refuse, and it should say so.
            local d u
            d="$(cd "$p" 2>/dev/null && git status --porcelain 2>/dev/null | awk '!/^\?\?/{n++} END{print n+0}')"
            u="$(cd "$p" 2>/dev/null && git status --porcelain 2>/dev/null | awk '/^\?\?/{n++} END{print n+0}')"
            if [ "${d:-0}" -ne 0 ] && [ "${u:-0}" -ne 0 ]; then
                reason="${d} tracked modification(s) and ${u} UNTRACKED file(s) — the untracked ones exist nowhere else"
            elif [ "${d:-0}" -ne 0 ]; then
                reason="${d} tracked modification(s)"
            elif [ "${u:-0}" -ne 0 ]; then
                reason="${u} UNTRACKED file(s) — unbacked, and removing this worktree destroys them"
            fi
        fi
        if [ -z "$reason" ] && [ -n "$newest_tag" ]; then
            local h t; h="$(cd "$p" 2>/dev/null && git rev-parse HEAD 2>/dev/null)"
            t="$(git rev-parse "${newest_tag}^{commit}" 2>/dev/null)"
            [ -n "$h" ] && [ "$h" = "$t" ] && reason="is at the newest tag on origin (${newest_tag})"
        fi
        # Belt and braces: never act on a path outside the expected prefix, whatever git said.
        case "$p" in
            "$ROOT/$SCAN"*) : ;;
            *) reason="path outside ${SCAN} — refusing on principle" ;;
        esac
        if [ "$state" = "DETACHED" ]; then
            case "$p" in
                "$ROOT/$PREFIX"*) : ;;
                *)
                    local rt; rt="$(_recon_tag "$p" "$origin_tags")"
                    if [ -z "$rt" ]; then
                        reason="detached outside ${PREFIX} and not at a tag on origin — its commit may be referenced by nothing else"
                    fi
                    ;;
            esac
        fi

        if [ -n "$reason" ]; then
            printf '  KEEP    %-24s %s\n' "$n" "$reason"
        elif [ "$APPLY" -eq 0 ]; then
            printf '  would remove %-19s %s\n' "$n" "$(du -sh "$p" 2>/dev/null | awk '{print $1}')"
        else
            mkdir -p "$ARCHIVE/logs/$n"
            find "$p/tmp" -maxdepth 1 -name '*.log' -print0 2>/dev/null \
                | while IFS= read -r -d '' f; do cp "$f" "$ARCHIVE/logs/$n/" 2>/dev/null; done
            if git worktree remove --force "$p" 2>/dev/null; then
                printf '  removed %-24s (logs archived)\n' "$n"
            else
                printf '  FAILED  %-24s git worktree remove refused\n' "$n"
            fi
        fi
    done

    # NO `git worktree prune` HERE. Every removal above went through `git worktree remove
    # --force`, which deregisters the worktree itself -- so a prune adds nothing for our own
    # candidates. What it DOES add is a repo-global sweep with no grace period: it
    # deregisters ANY worktree whose directory is momentarily absent, and this repo carries
    # ~134 registered worktrees that belong to other lanes. Measured in an isolated repo:
    # move a worktree's directory aside, prune, and its registration is gone -- moving the
    # directory back does NOT restore it, and `git worktree repair` does not either.
    # A removal that failed above is not helped by a prune anyway: its directory still exists.
    echo "[reap] ${total} candidate(s) under ${SCAN} (release prefix ${PREFIX}); keep=${KEEP}; apply=${APPLY}"
    [ "$APPLY" -eq 0 ] && echo "[reap] DRY RUN — nothing removed. Re-run with --apply."
    return 0
}

# ── self-test ────────────────────────────────────────────────────────────────
# Builds throwaway worktrees under a DIFFERENT prefix and runs THIS SCRIPT against them, so
# the real release worktrees are never a candidate. Both outcomes required: something kept
# for each distinct reason, and something actually removed.
# ⛔ NEVER `git worktree prune` FROM HERE. This selftest builds and tears down fixture
# worktrees, and the obvious cleanup for a directory removed with `rm -rf` is a prune. But
# prune is REPO-GLOBAL and has NO grace period: it deregisters EVERY worktree whose directory
# is momentarily absent, not only ours. This repo carries ~127 registered worktrees, nearly
# all of them other lanes', and a peer mid-move or on an unmounted path loses its
# registration -- after which `git worktree repair` was measured FAILING, so they must
# re-create the worktree and copy files back. A selftest must not be able to do that.
#
# So: deregister fixtures ONE AT A TIME, BY PATH. `git worktree remove --force` is already
# scoped. Only when the directory is already gone (a crashed earlier run) do we clear the
# admin entry, and then only the entry whose name matches THAT fixture.
_drop_fixture() {
    local d="$1" name
    [ -n "$d" ] || return 0
    git worktree remove --force "$d" >/dev/null 2>&1 && return 0
    name="$(basename "$d")"
    rm -rf "$d" 2>/dev/null
    rm -rf "$(git rev-parse --git-common-dir)/worktrees/${name}" 2>/dev/null
    return 0
}

# ⛔ A FIXTURE THAT FAILS TO BUILD MUST SAY SO. Every `git worktree add` below used to end in
# `>/dev/null 2>&1 || true`, so a failed add produced NO fixture and the behavioural arm about it
# failed under its own name — "at a tag ON ORIGIN outside PREFIX is reapable" reads as a defect in
# the reaping rule when the truth is that the tree was never created.
#
# MEASURED 2026-10-12, by me and independently by @cowir-main: this selftest is NONDETERMINISTIC on
# this box. My three runs failed 3, 2 and 0 arms; their six failed 5, 0, 3, 2, 1, 1 — different arms
# each time. It is in the publish corpus, so gate 0d blocks a publish on a coin flip.
#
# ⚠️ I COULD NOT REPRODUCE IT AFTERWARDS and I am not claiming a cause. Ruled out by measurement:
# my own instrumentation (original and instrumented both 3/3 clean later), two CONCURRENT runs in
# different worktrees (both 30/30), and registry churn during the failing window (226 worktrees,
# stable across 30s of sampling). So the trigger is still unnamed.
#
# What this change does is make the NEXT occurrence diagnostic instead of misleading: the add's
# error is captured and the arms that depend on a missing fixture are reported VOID, by name, with
# git's own message. The selftest still exits nonzero — a guard whose fixtures cannot be built is
# untrustworthy, not absent, which is the chain's own rule — but it now blocks under the correct
# noun. A flake that explains itself is one bug report away from a fix; this one has cost two lanes
# an afternoon of guessing.
_VOID_FIXTURES=0
_wt_add() { # label -- then the git worktree add arguments
    local label="$1"; shift
    local err
    if err="$(git worktree add "$@" 2>&1)"; then
        return 0
    fi
    _VOID_FIXTURES=$((_VOID_FIXTURES+1))
    printf '  VOID  fixture %-46s could not be built\n' "$label"
    printf '%s\n' "$err" | head -3 | sed 's/^/          git: /'
    return 1
}

selftest() {
    # SELFTEST FIXTURES LIVE UNDER THEIR OWN SCAN ROOT, AND THAT IS LOAD-BEARING.
    # This selftest calls --apply. While admission was decided by a path PREFIX, real
    # worktrees outside it were unreachable BY CONSTRUCTION and scanning tmp/ was safe --
    # a safety nobody had written down, because nothing needed it. Admission now also asks
    # whether a commit is RECONSTRUCTIBLE, which is a property of the COMMIT, so a real
    # publish worktree parked in tmp/ qualifies. Measured 2026-09-18: a --selftest run
    # removed pub442/443/444 before this was caught (recoverable, tags on origin, logs
    # already archived, and not the point). Confining SCAN is what makes the destructive
    # arms safe; the decoy fixture below is what keeps it confined.
    # ⛔ EVERY GLOBAL NAME THIS SELFTEST CREATES IS NAMESPACED BY $$, AND THAT IS NOT HYGIENE.
    # 2026-09-20: this selftest failed 2, then 4, then 12 arms on three consecutive runs --
    # different arms each time -- and blocked the v3.33.469-alpha publish (EC=4). The cause is
    # that BRANCHES AND TAGS ARE REPO-GLOBAL while the fixture names were CONSTANTS. Two
    # overlapping runs (two lanes publishing, or the fork chain that was live that night) each
    # create `reaptest/branch-${sfx}` and each DELETE it at cleanup, so one run tears down the ref the
    # other is still asserting on. The four arms that failed were all BRANCH arms, every time.
    #
    # ⚠️ I FIRST BLAMED THE WORKTREE REGISTRY AND THAT WAS WRONG -- measured here: adding two
    # worktrees with the SAME basename in different directories both return 0, and git creates
    # admin entries `dupname` and `dupname1`. Worktree names were never the collision; the
    # global refs were. Same class as the run_tests.sh NUL-hole (shared mutable state keyed by
    # nothing) and the same cure ($$), but a different shared object than the one I named.
    local sfx="$$"
    local pass=0 fail=0 scan="tmp/reapself-${sfx}/" pfx="tmp/reapself-${sfx}/reaptest-rel-" tags t self
    self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

    tags="$(git tag -l 'v3.33.*' | sort -V | tail -6 | head -4)"
    if [ "$(printf '%s\n' "$tags" | wc -l)" -lt 4 ]; then
        echo "selftest: SKIPPED — need 4 tags to build fixtures" >&2
        return 2
    fi

    # \u26d4 THE SELFTEST MUST NOT NEED THE NETWORK. This is a gate-0d check: when it asked github
    # six times, one lost call red 3 arms and blocked a publish on a sound build (1 run in 6,
    # measured 2026-10-13). A local bare clone gives the same refs over a filesystem path, so the
    # arms are deterministic and say something about the TOOL rather than about connectivity.
    # --local hardlinks the object store, so this costs no meaningful disk or time.
    local _bare="tmp/reapself-${sfx}-origin.git"
    if git clone --bare --local --quiet . "$_bare" 2>/dev/null; then
        export REAP_ORIGIN="$_bare"
        ORIGIN="$_bare"
        echo "[reap] selftest: origin = local bare clone (no network)"
    else
        echo "[reap] selftest: could not build the local bare origin — falling back to the real" >&2
        echo "       remote, so these arms depend on connectivity and may red on a lost call." >&2
    fi

    mkdir -p "$scan"
    for _d in "${pfx}"*; do [ -e "$_d" ] && _drop_fixture "$_d"; done
    # a crashed earlier run can leave an admin entry with no directory; clear ONLY ours
    for _e in "$(git rev-parse --git-common-dir)/worktrees/"$(basename "$pfx")*; do
        [ -e "$_e" ] && rm -rf "$_e"
    done
    # FIXTURE ORDERING IS PART OF THE TEST. These sort with `sort -V`, and the newest-KEEP
    # rule is evaluated BEFORE the branch and dirty rules. The first version of this selftest
    # put the branch fixture at index 5, where it sorted last and was kept as "among the 1
    # newest" — so the branch rule was never exercised and the arm still would have passed
    # had it only asked whether the directory survived. It asserts on the REASON for that
    # reason. Branch fixture sorts FIRST, dirty next, detached tags fill the rest.
    local i=2
    for t in $tags; do
        _wt_add "${pfx}${i}" --detach "${pfx}${i}" "$t" || true
        i=$((i+1))
    done
    # ⛔ CUT FROM origin/main, NOT HEAD. This fixture exists to exercise the UNPUSHED rule, and
    # the ladder checks merged-into-origin/main FIRST. From HEAD the arm only reaches the
    # unpushed check when HEAD happens to BE origin/main — so the moment you run --selftest on a
    # branch carrying one local commit it reds on "NOT merged" and reads as a regression you
    # caused. The arm was passing on where HEAD sat rather than on the rule it names.
    _wt_add "${pfx}0 (branch)" -b reaptest/branch-${sfx} "${pfx}0" origin/main || true
    echo "scratch" > "${pfx}2/REAPTEST_DIRTY.md" 2>/dev/null
    ( cd "${pfx}2" && git add REAPTEST_DIRTY.md >/dev/null 2>&1 )

    local out
    out="$(REAP_SCAN="$scan" REAP_PREFIX="$pfx" "$self" --keep 1 2>&1)"

    chk() { # name, pattern, want(0=present,1=absent)
        if printf '%s' "$out" | grep -q "$2"; then [ "$3" -eq 0 ] && { pass=$((pass+1)); printf '  ok    %s\n' "$1"; return; }
        else [ "$3" -eq 1 ] && { pass=$((pass+1)); printf '  ok    %s\n' "$1"; return; }; fi
        fail=$((fail+1)); printf '  FAIL  %s\n' "$1"
    }
    chk "dry run removes nothing"            "DRY RUN"                          0
    chk "a dirty worktree is kept"           "KEEP.*reaptest-rel-2.*modification" 0
    # ⛔ AN UNTRACKED-ONLY WORKTREE MUST SAY "UNTRACKED", NOT "tracked modification(s)".
    # The rel-2 fixture above is `git add`ed, so it exercises only the tracked half and
    # passed happily while the label was wrong for every untracked case. This arm is the
    # untracked half, and it asserts the WORD because the count was never the defect.
    printf 'scratch\n' > "${pfx}3/REAPTEST_UNTRACKED.md" 2>/dev/null
    out="$(REAP_SCAN="$scan" REAP_PREFIX="$pfx" "$self" --keep 1 2>&1)"
    chk "an UNTRACKED-only worktree is kept"      "KEEP.*reaptest-rel-3.*UNTRACKED"   0
    chk "  ...and is NOT called a tracked mod"    "reaptest-rel-3.*tracked modification" 1
    # ⛔ THE COMBINED CASE HAD NO ARM AND I FOUND IT BY MUTATING MY OWN FIX. Disabling the
    # `d != 0 && u != 0` branch outright left the selftest at 28/28 green -- so the message
    # that names BOTH counts had never been produced by a test. The two pure branches were
    # covered (their mutations red); the one that exists because a worktree can be dirty AND
    # carry unbacked files was a clause that never ran. That is the defect family this whole
    # fix belongs to, sitting inside the fix.
    printf 'scratch\n' > "${pfx}2/REAPTEST_UNTRACKED.md" 2>/dev/null
    out="$(REAP_SCAN="$scan" REAP_PREFIX="$pfx" "$self" --keep 1 2>&1)"
    chk "tracked AND untracked names BOTH"       "reaptest-rel-2.*tracked modification.*and.*UNTRACKED" 0
    chk "  ...and still refuses to remove it"    "would remove reaptest-rel-2"      1
    rm -f "${pfx}2/REAPTEST_UNTRACKED.md"
    chk "a branch worktree is kept"          "KEEP.*reaptest-rel-0.*branch"     0
    chk "the newest is kept by position"     "KEEP.*among the 1 newest"         0
    chk "at least one is reapable"           "would remove"                     0
    chk "real rel- worktrees untouched"      "would remove rel-"                1

    # now actually apply, and confirm the protected ones survive
    out="$(REAP_SCAN="$scan" REAP_PREFIX="$pfx" "$self" --keep 1 --apply 2>&1)"
    chk "apply removes something"            "removed"                          0
    [ -d "${pfx}2" ] && { pass=$((pass+1)); printf '  ok    dirty worktree survived --apply\n'; } \
                     || { fail=$((fail+1)); printf '  FAIL  dirty worktree was destroyed\n'; }
    [ -d "${pfx}0" ] && { pass=$((pass+1)); printf '  ok    branch worktree survived --apply\n'; } \
                     || { fail=$((fail+1)); printf '  FAIL  branch worktree was destroyed\n'; }

    # ── --merged-branches: the affirmative path, and the two refusals that guard it ──────
    # Fixtures for the three branch states. The reapable one is DERIVED — any local branch
    # already merged into origin/main, present on origin, and not checked out anywhere — so
    # this arm cannot quietly become a skip if one hardcoded branch is ever deleted.
    _wt_add "${pfx}1 (unmerged branch)" -b reaptest/unmerged-${sfx} "${pfx}1" HEAD || true
    ( cd "${pfx}1" && git commit --allow-empty -qm "reaptest: not in origin/main" >/dev/null 2>&1 )

    # ⛔ THIS FIXTURE NEEDS A *REAL* BRANCH -- merged into origin/main, pushed, and not already
    # checked out -- so it cannot be namespaced like the others. It is therefore the one arm
    # that races on a SHARED resource: a branch this repo genuinely has. Picking the first
    # candidate and hoping is what made it flaky -- measured 2026-09-20, two concurrent
    # selftests, the loser's `git worktree add` failed under `|| true` and its arm reported a
    # defect that did not exist. This repo carries 70+ worktrees across every lane, so another
    # lane holding the branch produces the identical false failure with no concurrency at all.
    #
    # So: TRY candidates until one is actually checked out, rather than testing the first and
    # assuming. The `|| continue` is the whole fix -- a failed add now costs the next candidate
    # instead of the arm.
    local mb="" b
    for b in $(git for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null); do
        case "$b" in reaptest/*) continue ;; esac
        git merge-base --is-ancestor "$b" origin/main 2>/dev/null || continue
        git ls-remote --exit-code --heads "$ORIGIN" "$b" >/dev/null 2>&1 || continue
        git worktree list --porcelain 2>/dev/null | grep -qx "branch refs/heads/$b" && continue
        git worktree add "${pfx}8" "$b" >/dev/null 2>&1 || continue
        mb="$b"; break
    done

    out="$(REAP_SCAN="$scan" REAP_PREFIX="$pfx" "$self" --keep 1 --merged-branches 2>&1)"
    chk "unmerged branch refused EVEN WITH the flag"  "KEEP.*reaptest-rel-1.*NOT merged"        0
    chk "unpushed branch refused EVEN WITH the flag"  "KEEP.*reaptest-rel-0.*not on origin"     0
    if [ -n "$mb" ]; then
        chk "merged+pushed+clean branch IS reapable"  "would remove reaptest-rel-8"             0
    else
        fail=$((fail+1)); printf '  FAIL  no merged+pushed branch available to build the positive fixture\n'
    fi
    # ⛔ Without the flag the same tree must be refused — otherwise the flag is decorative and
    # these arms would pass against a build that reaps branch worktrees unconditionally.
    out="$(REAP_SCAN="$scan" REAP_PREFIX="$pfx" "$self" --keep 1 2>&1)"
    chk "…and refused again with the flag absent"     "would remove reaptest-rel-8"             1

    for d in "${pfx}1" "${pfx}8"; do [ -d "$d" ] && git worktree remove --force "$d" >/dev/null 2>&1; done
    git branch -D reaptest/unmerged-${sfx} >/dev/null 2>&1
    [ -n "$mb" ] && { git rev-parse --verify -q "$mb" >/dev/null && pass=$((pass+1)) && printf '  ok    the derived branch itself survived removal of its worktree\n'; }

    # ── REAP_ROOT: the LOOKING moves, the REFUSALS do not ────────────────────────────────
    # These fixtures sit outside the default ROOT/SCAN combination. Before REAP_ROOT the filter
    # was "$PWD/tmp/"* with $PWD forced to this script's own checkout by the startup cd, so a
    # population under any other checkout was unreachable however the tool was invoked — which is
    # how 49 release worktrees accumulated while the reaper reported "headroom fine".
    # ⛔ THE NEST MUST SIT OUTSIDE $PWD/$SCAN OR THESE ARMS CANNOT FAIL. First version put it at
    # tmp/reaproot-nest/, which still matches the BUGGY "$PWD/tmp/"* filter — so reverting the fix
    # left every new arm green. A fixture inside the defective corpus tests nothing.
    # Namespaced for the same reason as the refs above: the widened-root arms deliberately
    # scan a BROADER directory, so with a constant name two concurrent runs see each other's
    # fixtures and the population assertions ("the newest is still protected") break.
    local nest=".reaptest-nest-${sfx}"
    local firsttag; firsttag="$(printf '%s\n' $tags | head -1)"
    # Fixtures sit at <nest>/tmp/rel-… so the DEFAULT SCAN and PREFIX apply unchanged at the new
    # root — the same shape as cowir-deploy-wt/tmp/. Note ${REAP_SCAN:-tmp/} substitutes on EMPTY
    # as well as unset, so REAP_SCAN="" cannot be used to flatten the scan.
    mkdir -p "$nest/tmp"
    _wt_add "rel-9001 (widened root)" --detach "${nest}/tmp/rel-9001" "$firsttag" || true
    _wt_add "other-9002 (widened root, branch)" -b reaptest/rootbranch-${sfx} "${nest}/tmp/other-9002" HEAD || true

    # A zero must name the population it is a zero over. The old message said "no worktrees under
    # ${PREFIX}" while the filter is ROOT/SCAN, so a run rooted at the wrong tree was indistinguishable
    # from a tidy box — the false-clean that cost the disk.
    out="$(REAP_SCAN="reaptest-no-such-dir/" "$self" --keep 1 2>&1)"
    chk "an empty scan names the population, not a bare zero" "0 of [0-9]* registered worktree" 0

    out="$(REAP_ROOT="$PWD/$nest" "$self" --keep 0 2>&1)"
    # ⛔ ASSERT THE AFFIRMATIVE OUTCOME, NOT MERE PRESENCE. "rel-9001" appears under a broken root
    # too — as `KEEP rel-9001 path outside` — so a presence pin passes on the defect it names.
    # "would remove" is reached only when the candidate scan, the belt-and-braces check and the
    # detached-under-PREFIX check ALL agree at the widened root.
    chk "REAP_ROOT reaches a population outside this checkout"  "would remove rel-9001"       0
    # ⛔ THE SAFETY CLAIM. Widening WHERE we look must buy no removal the rules would refuse. The
    # branch fixture is refused for being on a branch at the new root exactly as at the old one —
    # if a widened root ever let a refusal lapse, this is the arm that reds.
    chk "a branch worktree is still refused at a widened root"  "KEEP.*other-9002.*branch"    0
    chk "a widened root still removes nothing on a dry run"     "DRY RUN"                     0
    # ⛔ THE KEEP-NEWEST RULE AT A WIDENED ROOT. `protected` is computed against ROOT/PREFIX, and
    # at --keep 0 that computation is unreachable — so without this arm the substitution there is
    # untested and a widened root would reap the NEWEST release worktree, which is the one copy of
    # what players are running. Needs its own invocation because the arms above use --keep 0.
    out="$(REAP_ROOT="$PWD/$nest" "$self" --keep 1 2>&1)"
    chk "the newest is still protected at a widened root"       "KEEP.*rel-9001.*newest"      0

    # A bogus root must fail LOUDLY. Scanning nothing silently is the defect, not the fallback.
    out="$(REAP_ROOT="$PWD/${nest}/definitely-absent" "$self" --keep 1 2>&1)"; local rootec=$?
    if [ "$rootec" -eq 2 ]; then pass=$((pass+1)); printf '  ok    a bogus REAP_ROOT exits 2 rather than scanning nothing\n'
    else fail=$((fail+1)); printf '  FAIL  a bogus REAP_ROOT exits %s, want 2\n' "$rootec"; fi

    for d in "${nest}/tmp/rel-9001" "${nest}/tmp/other-9002"; do
        [ -d "$d" ] && git worktree remove --force "$d" >/dev/null 2>&1
    done
    git branch -D reaptest/rootbranch-${sfx} >/dev/null 2>&1
    rm -rf "$nest"

    # -- reconstructibility: a detached tree outside PREFIX is judged by its COMMIT ---------
    # Three fixtures differing ONLY in what their HEAD is reachable from. Same shape, same
    # scan root, all outside PREFIX -- so an arm passing for a reason other than
    # reconstructibility would have to pass for all three, and they disagree.
    local rtag="" c u1="" u2=""
    for t in $tags; do
        git ls-remote --exit-code --tags "$ORIGIN" "$t" >/dev/null 2>&1 && rtag="$t"
    done
    for c in $(git rev-list --max-count=60 origin/main 2>/dev/null); do
        [ -n "$(git tag --points-at "$c" 2>/dev/null)" ] && continue
        if   [ -z "$u1" ]; then u1="$c"
        elif [ -z "$u2" ]; then u2="$c"; break; fi
    done
    if [ -z "$rtag" ] || [ -z "$u1" ] || [ -z "$u2" ]; then
        fail=$((fail+1)); printf '  FAIL  could not build the reconstructibility fixtures (rtag=%s u1=%s u2=%s)\n' "${rtag:-none}" "${u1:-none}" "${u2:-none}"
    else
        git tag reaptest-localonly-${sfx} "$u1" >/dev/null 2>&1 || true
        _wt_add "reaptest-recon-9 (tag on origin)" --detach "${scan}"reaptest-recon-9 "$rtag" || true
        _wt_add "reaptest-localtag-9 (local-only tag)" --detach "${scan}"reaptest-localtag-9 reaptest-localonly-${sfx} || true
        _wt_add "reaptest-scratch-9 (untagged)" --detach "${scan}"reaptest-scratch-9 "$u2" || true

        out="$(REAP_SCAN="$scan" REAP_PREFIX="$pfx" "$self" --keep 1 2>&1)"
        chk "at a tag ON ORIGIN outside PREFIX is reapable" "would remove reaptest-recon-9"                      0
        chk "a LOCAL-ONLY tag is NOT reconstructible"       "KEEP.*reaptest-localtag-9.*not at a tag on origin"  0
        chk "an untagged detached tree is kept"             "KEEP.*reaptest-scratch-9.*not at a tag on origin"   0

        # DECOY: reconstructible, detached, at a tag on origin -- identical in every respect
        # to a real publish worktree, and parked OUTSIDE the fixture scan. If a selftest run
        # ever names it, the confinement has failed and the destructive arms are pointed at
        # this lane's real worktrees again.
        _wt_add "reaptest-decoy-9 (confinement decoy)" --detach tmp/reaptest-decoy-9 "$rtag" || true

        # The protected slots must cover the ADMITTED set, not the prefix. With a prefix that
        # matches nothing, every position-based KEEP has to come from reconstructibility --
        # empty output under the old prefix-only awk, non-empty under the new loop.
        # Dry run only: it must never remove anything.
        out="$(REAP_SCAN="$scan" REAP_PREFIX=tmp/nosuchprefix- "$self" --keep 1 2>&1)"
        chk "reconstructible trees can hold a protected slot" "KEEP.*among the 1 newest"  0
        chk "...and that dry run still removed nothing"       "DRY RUN"                   0
        chk "a reconstructible tree OUTSIDE the scan is unreachable" "reaptest-decoy-9"   1

        for d in "${scan}"reaptest-recon-9 "${scan}"reaptest-localtag-9 "${scan}"reaptest-scratch-9 tmp/reaptest-decoy-9; do
            [ -e "$d" ] && _drop_fixture "$d"
        done
        git tag -d reaptest-localonly-${sfx} >/dev/null 2>&1
    fi

    # cleanup fixtures
    ( cd "${pfx}2" 2>/dev/null && git reset -q HEAD REAPTEST_DIRTY.md 2>/dev/null; rm -f REAPTEST_DIRTY.md )
    for d in "${pfx}"*; do [ -e "$d" ] && _drop_fixture "$d"; done
    git branch -D reaptest/branch-${sfx} >/dev/null 2>&1
    rmdir "$scan" 2>/dev/null || true

    echo
    # \u26d4 THE ONE ARM THAT MUST STILL TOUCH THE UNREACHABLE PATH. Every arm above now runs
    # against a local bare clone, which is what makes them deterministic -- but a selftest that
    # can no longer reach the failure mode cannot prove the fix for it. So: force an unreachable
    # remote and assert the LOUD verdict, not an empty tag set quietly reclassifying every tree.
    # A bad path is the right forcing here; GIT_SSH_COMMAND only bites a remote that uses ssh,
    # and with a local origin it does nothing.
    local _un _uec=0
    _un="$(REAP_ORIGIN=/nonexistent/origin.git "$self" 2>&1)" || _uec=$?
    if printf '%s' "$_un" | grep -q 'BLOCKED: cannot reach .* reconstructibility is UNKNOWN'; then
        pass=$((pass+1)); printf '  ok    %s\n' "an unreachable origin is a BLOCKED verdict"
    else
        fail=$((fail+1)); printf '  FAIL  %s\n' "an unreachable origin is a BLOCKED verdict"
    fi
    if [ "$_uec" -eq 3 ]; then
        pass=$((pass+1)); printf '  ok    %s\n' "  ...and exits 3 (unknown), never 0"
    else
        fail=$((fail+1)); printf '  FAIL  %s (exit %s, wanted 3)\n' "  ...and exits 3 (unknown), never 0" "$_uec"
    fi
    # And it must NOT claim anything about reconstructibility while it cannot read the remote.
    if printf '%s' "$_un" | grep -q 'would remove'; then
        fail=$((fail+1)); printf '  FAIL  %s\n' "an unreachable origin proposes no removals"
    else
        pass=$((pass+1)); printf '  ok    %s\n' "an unreachable origin proposes no removals"
    fi

    echo "selftest: ${pass} passed, ${fail} failed"
    if [ "$_VOID_FIXTURES" -gt 0 ]; then
        echo "selftest: ⛔ ${_VOID_FIXTURES} FIXTURE(S) COULD NOT BE BUILT — the failures above are" >&2
        echo "          about missing test worktrees, NOT about the reaping rules. Fix the build" >&2
        echo "          problem (git's message is printed beside each VOID line) before reading any" >&2
        echo "          arm above as a defect in this tool." >&2
        return 1
    fi
    [ "$fail" -eq 0 ]
}

if [ "${selftest_requested:-0}" = "1" ]; then selftest; else reap; fi
