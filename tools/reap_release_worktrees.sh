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

_newest_tag_on_origin() {
    git ls-remote --tags origin 'refs/tags/v3.33.*' 2>/dev/null \
        | grep -v '\^{}' | awk '{print $2}' | sed 's#refs/tags/##' | sort -V | tail -1
}

_origin_tags() {
    git ls-remote --tags origin 'refs/tags/*' 2>/dev/null \
        | grep -v '\^{}' | awk '{print $2}' | sed 's#refs/tags/##'
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
    newest_tag="$(_newest_tag_on_origin)"
    local origin_tags; origin_tags="$(_origin_tags)"
    [ -z "$origin_tags" ] && echo "[reap] note: no tags readable from origin — every detached worktree outside ${PREFIX} will be kept" >&2

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
            elif ! git ls-remote --exit-code --heads origin "$br" >/dev/null 2>&1; then
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
    local pass=0 fail=0 scan="tmp/reapself/" pfx="tmp/reapself/reaptest-rel-" tags t self
    self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

    tags="$(git tag -l 'v3.33.*' | sort -V | tail -6 | head -4)"
    if [ "$(printf '%s\n' "$tags" | wc -l)" -lt 4 ]; then
        echo "selftest: SKIPPED — need 4 tags to build fixtures" >&2
        return 2
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
        git worktree add --detach "${pfx}${i}" "$t" >/dev/null 2>&1 || true
        i=$((i+1))
    done
    # ⛔ CUT FROM origin/main, NOT HEAD. This fixture exists to exercise the UNPUSHED rule, and
    # the ladder checks merged-into-origin/main FIRST. From HEAD the arm only reaches the
    # unpushed check when HEAD happens to BE origin/main — so the moment you run --selftest on a
    # branch carrying one local commit it reds on "NOT merged" and reads as a regression you
    # caused. The arm was passing on where HEAD sat rather than on the rule it names.
    git worktree add -b reaptest/branch "${pfx}0" origin/main >/dev/null 2>&1 || true
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
    git worktree add -b reaptest/unmerged "${pfx}1" HEAD >/dev/null 2>&1 || true
    ( cd "${pfx}1" && git commit --allow-empty -qm "reaptest: not in origin/main" >/dev/null 2>&1 )

    local mb="" b
    for b in $(git for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null); do
        case "$b" in reaptest/*) continue ;; esac
        git merge-base --is-ancestor "$b" origin/main 2>/dev/null || continue
        git ls-remote --exit-code --heads origin "$b" >/dev/null 2>&1 || continue
        git worktree list --porcelain 2>/dev/null | grep -qx "branch refs/heads/$b" && continue
        mb="$b"; break
    done
    if [ -n "$mb" ]; then
        git worktree add "${pfx}8" "$mb" >/dev/null 2>&1 || true
    fi

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
    git branch -D reaptest/unmerged >/dev/null 2>&1
    [ -n "$mb" ] && { git rev-parse --verify -q "$mb" >/dev/null && pass=$((pass+1)) && printf '  ok    the derived branch itself survived removal of its worktree\n'; }

    # ── REAP_ROOT: the LOOKING moves, the REFUSALS do not ────────────────────────────────
    # These fixtures sit outside the default ROOT/SCAN combination. Before REAP_ROOT the filter
    # was "$PWD/tmp/"* with $PWD forced to this script's own checkout by the startup cd, so a
    # population under any other checkout was unreachable however the tool was invoked — which is
    # how 49 release worktrees accumulated while the reaper reported "headroom fine".
    # ⛔ THE NEST MUST SIT OUTSIDE $PWD/$SCAN OR THESE ARMS CANNOT FAIL. First version put it at
    # tmp/reaproot-nest/, which still matches the BUGGY "$PWD/tmp/"* filter — so reverting the fix
    # left every new arm green. A fixture inside the defective corpus tests nothing.
    local nest=".reaptest-nest"
    local firsttag; firsttag="$(printf '%s\n' $tags | head -1)"
    # Fixtures sit at <nest>/tmp/rel-… so the DEFAULT SCAN and PREFIX apply unchanged at the new
    # root — the same shape as cowir-deploy-wt/tmp/. Note ${REAP_SCAN:-tmp/} substitutes on EMPTY
    # as well as unset, so REAP_SCAN="" cannot be used to flatten the scan.
    mkdir -p "$nest/tmp"
    git worktree add --detach "${nest}/tmp/rel-9001" "$firsttag" >/dev/null 2>&1 || true
    git worktree add -b reaptest/rootbranch "${nest}/tmp/other-9002" HEAD >/dev/null 2>&1 || true

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
    git branch -D reaptest/rootbranch >/dev/null 2>&1
    rm -rf "$nest"

    # -- reconstructibility: a detached tree outside PREFIX is judged by its COMMIT ---------
    # Three fixtures differing ONLY in what their HEAD is reachable from. Same shape, same
    # scan root, all outside PREFIX -- so an arm passing for a reason other than
    # reconstructibility would have to pass for all three, and they disagree.
    local rtag="" c u1="" u2=""
    for t in $tags; do
        git ls-remote --exit-code --tags origin "$t" >/dev/null 2>&1 && rtag="$t"
    done
    for c in $(git rev-list --max-count=60 origin/main 2>/dev/null); do
        [ -n "$(git tag --points-at "$c" 2>/dev/null)" ] && continue
        if   [ -z "$u1" ]; then u1="$c"
        elif [ -z "$u2" ]; then u2="$c"; break; fi
    done
    if [ -z "$rtag" ] || [ -z "$u1" ] || [ -z "$u2" ]; then
        fail=$((fail+1)); printf '  FAIL  could not build the reconstructibility fixtures (rtag=%s u1=%s u2=%s)\n' "${rtag:-none}" "${u1:-none}" "${u2:-none}"
    else
        git tag reaptest-localonly "$u1" >/dev/null 2>&1 || true
        git worktree add --detach "${scan}"reaptest-recon-9    "$rtag"            >/dev/null 2>&1 || true
        git worktree add --detach "${scan}"reaptest-localtag-9 reaptest-localonly >/dev/null 2>&1 || true
        git worktree add --detach "${scan}"reaptest-scratch-9  "$u2"              >/dev/null 2>&1 || true

        out="$(REAP_SCAN="$scan" REAP_PREFIX="$pfx" "$self" --keep 1 2>&1)"
        chk "at a tag ON ORIGIN outside PREFIX is reapable" "would remove reaptest-recon-9"                      0
        chk "a LOCAL-ONLY tag is NOT reconstructible"       "KEEP.*reaptest-localtag-9.*not at a tag on origin"  0
        chk "an untagged detached tree is kept"             "KEEP.*reaptest-scratch-9.*not at a tag on origin"   0

        # DECOY: reconstructible, detached, at a tag on origin -- identical in every respect
        # to a real publish worktree, and parked OUTSIDE the fixture scan. If a selftest run
        # ever names it, the confinement has failed and the destructive arms are pointed at
        # this lane's real worktrees again.
        git worktree add --detach tmp/reaptest-decoy-9 "$rtag" >/dev/null 2>&1 || true

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
        git tag -d reaptest-localonly >/dev/null 2>&1
    fi

    # cleanup fixtures
    ( cd "${pfx}2" 2>/dev/null && git reset -q HEAD REAPTEST_DIRTY.md 2>/dev/null; rm -f REAPTEST_DIRTY.md )
    for d in "${pfx}"*; do [ -e "$d" ] && _drop_fixture "$d"; done
    git branch -D reaptest/branch >/dev/null 2>&1
    rmdir "$scan" 2>/dev/null || true

    echo
    echo "selftest: ${pass} passed, ${fail} failed"
    [ "$fail" -eq 0 ]
}

if [ "${selftest_requested:-0}" = "1" ]; then selftest; else reap; fi
