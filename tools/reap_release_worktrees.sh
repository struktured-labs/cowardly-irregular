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
# Exit:   0 ok · 2 usage/precondition

set -uo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

PREFIX="${REAP_PREFIX:-tmp/rel-}"
# What we LOOK at. Detached worktrees must still sit under PREFIX; SCAN only widens the scan so
# branch worktrees can be CONSIDERED under --merged-branches. Never widen SCAN past tmp/.
SCAN="${REAP_SCAN:-tmp/}"
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

# Worktrees under PREFIX, newest-numeric last. A rel-<sha> name has no ordinal, so it sorts
# before every numbered one and is therefore never mistaken for recent.
_candidates() {
    git worktree list --porcelain 2>/dev/null \
        | awk '/^worktree /{w=$2} /^detached/{print w" DETACHED"} /^branch /{print w" "$2}' \
        | while read -r p state; do
              case "$p" in
                  "$PWD/$SCAN"*) printf '%s\t%s\n' "$p" "$state" ;;
              esac
          done | sort -V
}

reap() {
    local newest_tag total=0 kept=0 removed=0 refused=0
    newest_tag="$(_newest_tag_on_origin)"

    local rows; rows="$(_candidates)"
    if [ -z "$rows" ]; then
        echo "[reap] no worktrees under ${PREFIX}"
        return 0
    fi
    total="$(printf '%s\n' "$rows" | wc -l)"

    # The newest KEEP entries are protected by position alone.
    # ⛔ Computed over DETACHED worktrees under PREFIX only. SCAN widening must not let a
    # branch worktree occupy one of the protected slots and push a release tree out of them —
    # that would silently weaken the rule this line exists to enforce.
    local protected
    protected="$(printf '%s\n' "$rows" | awk -F'\t' -v pfx="$PWD/$PREFIX" \
        '$2=="DETACHED" && index($1,pfx)==1 {print $1}' | tail -n "$KEEP")"

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
            local d; d="$(cd "$p" 2>/dev/null && git status --porcelain 2>/dev/null | wc -l)"
            [ "$d" -ne 0 ] && reason="${d} tracked modification(s)"
        fi
        if [ -z "$reason" ] && [ -n "$newest_tag" ]; then
            local h t; h="$(cd "$p" 2>/dev/null && git rev-parse HEAD 2>/dev/null)"
            t="$(git rev-parse "${newest_tag}^{commit}" 2>/dev/null)"
            [ -n "$h" ] && [ "$h" = "$t" ] && reason="is at the newest tag on origin (${newest_tag})"
        fi
        # Belt and braces: never act on a path outside the expected prefix, whatever git said.
        case "$p" in
            "$PWD/$SCAN"*) : ;;
            *) reason="path outside ${SCAN} — refusing on principle" ;;
        esac
        if [ "$state" = "DETACHED" ]; then
            case "$p" in
                "$PWD/$PREFIX"*) : ;;
                *) reason="detached outside ${PREFIX} — its commit may be referenced by nothing else" ;;
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

    [ "$APPLY" -eq 1 ] && git worktree prune
    echo "[reap] ${total} candidate(s) under ${SCAN} (release prefix ${PREFIX}); keep=${KEEP}; apply=${APPLY}"
    [ "$APPLY" -eq 0 ] && echo "[reap] DRY RUN — nothing removed. Re-run with --apply."
    return 0
}

# ── self-test ────────────────────────────────────────────────────────────────
# Builds throwaway worktrees under a DIFFERENT prefix and runs THIS SCRIPT against them, so
# the real release worktrees are never a candidate. Both outcomes required: something kept
# for each distinct reason, and something actually removed.
selftest() {
    local pass=0 fail=0 pfx="tmp/reaptest-rel-" tags t self
    self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

    tags="$(git tag -l 'v3.33.*' | sort -V | tail -6 | head -4)"
    if [ "$(printf '%s\n' "$tags" | wc -l)" -lt 4 ]; then
        echo "selftest: SKIPPED — need 4 tags to build fixtures" >&2
        return 2
    fi

    rm -rf "${pfx}"* 2>/dev/null; git worktree prune
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
    git worktree add -b reaptest/branch "${pfx}0" HEAD >/dev/null 2>&1 || true
    echo "scratch" > "${pfx}2/REAPTEST_DIRTY.md" 2>/dev/null
    ( cd "${pfx}2" && git add REAPTEST_DIRTY.md >/dev/null 2>&1 )

    local out
    out="$(REAP_PREFIX="$pfx" "$self" --keep 1 2>&1)"

    chk() { # name, pattern, want(0=present,1=absent)
        if printf '%s' "$out" | grep -q "$2"; then [ "$3" -eq 0 ] && { pass=$((pass+1)); printf '  ok    %s\n' "$1"; return; }
        else [ "$3" -eq 1 ] && { pass=$((pass+1)); printf '  ok    %s\n' "$1"; return; }; fi
        fail=$((fail+1)); printf '  FAIL  %s\n' "$1"
    }
    chk "dry run removes nothing"            "DRY RUN"                          0
    chk "a dirty worktree is kept"           "KEEP.*reaptest-rel-2.*modification" 0
    chk "a branch worktree is kept"          "KEEP.*reaptest-rel-0.*branch"     0
    chk "the newest is kept by position"     "KEEP.*among the 1 newest"         0
    chk "at least one is reapable"           "would remove"                     0
    chk "real rel- worktrees untouched"      "would remove rel-"                1

    # now actually apply, and confirm the protected ones survive
    out="$(REAP_PREFIX="$pfx" "$self" --keep 1 --apply 2>&1)"
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

    out="$(REAP_PREFIX="$pfx" "$self" --keep 1 --merged-branches 2>&1)"
    chk "unmerged branch refused EVEN WITH the flag"  "KEEP.*reaptest-rel-1.*NOT merged"        0
    chk "unpushed branch refused EVEN WITH the flag"  "KEEP.*reaptest-rel-0.*not on origin"     0
    if [ -n "$mb" ]; then
        chk "merged+pushed+clean branch IS reapable"  "would remove reaptest-rel-8"             0
    else
        fail=$((fail+1)); printf '  FAIL  no merged+pushed branch available to build the positive fixture\n'
    fi
    # ⛔ Without the flag the same tree must be refused — otherwise the flag is decorative and
    # these arms would pass against a build that reaps branch worktrees unconditionally.
    out="$(REAP_PREFIX="$pfx" "$self" --keep 1 2>&1)"
    chk "…and refused again with the flag absent"     "would remove reaptest-rel-8"             1

    for d in "${pfx}1" "${pfx}8"; do [ -d "$d" ] && git worktree remove --force "$d" >/dev/null 2>&1; done
    git branch -D reaptest/unmerged >/dev/null 2>&1
    [ -n "$mb" ] && { git rev-parse --verify -q "$mb" >/dev/null && pass=$((pass+1)) && printf '  ok    the derived branch itself survived removal of its worktree\n'; }

    # cleanup fixtures
    ( cd "${pfx}2" 2>/dev/null && git reset -q HEAD REAPTEST_DIRTY.md 2>/dev/null; rm -f REAPTEST_DIRTY.md )
    for d in "${pfx}"*; do [ -d "$d" ] && git worktree remove --force "$d" >/dev/null 2>&1; done
    git worktree prune; git branch -D reaptest/branch >/dev/null 2>&1

    echo
    echo "selftest: ${pass} passed, ${fail} failed"
    [ "$fail" -eq 0 ]
}

if [ "${selftest_requested:-0}" = "1" ]; then selftest; else reap; fi
