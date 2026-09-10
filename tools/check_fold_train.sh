#!/usr/bin/env bash
# Re-establish "my branches fold clean" as a MEASUREMENT instead of a remembered claim.
#
# WHY THIS EXISTS
# ---------------
# I told the integrator "all branches fold-ready, verified clean" for ten hours. It was false
# for five of them: two of my own branches both anchored on the same line of
# make_web_stage.sh — one REPLACING it, one INSERTING before it — and conflicted. Nobody would
# have found out until the fold train hit it.
#
# The claim was true when first measured. It decayed because every new branch invalidates it
# and nothing re-derived it, so re-stating from memory was cheaper than re-running. That is
# the whole failure: **a claim that is expensive to re-check gets repeated instead.** This
# makes re-checking one command.
#
# DERIVED, NOT LISTED
# -------------------
# A hardcoded branch list is a second source of truth that rots on the next push. The train is
# derived: refs on origin that are NOT ancestors of main and whose tip commit carries the given
# Claude-Session trailer. Verified 2026-09-10 — that selects exactly this session's ten
# branches, and a control confirms it excludes other lanes' work.
#
# ARCHIVE BRANCHES ARE REPORTED, NOT SILENTLY DROPPED. Only `lane/*` enters the train;
# anything else carrying the trailer (store-assets, which must never be folded) is listed as
# EXCLUDED. A filter that quietly removes things is how a branch goes missing from a fold and
# nobody notices — the omission has to be visible to be checkable.
#
# WHAT IT PROVES, AND WHAT IT DOES NOT
#   proves    the tips AS OF NOW merge onto main individually and together, and every
#             tools/*.sh --selftest passes on the merged tree
#   does NOT  prove they will tomorrow. The output names the tips it measured; if ls-remote
#             disagrees, this run is stale and re-running it is the author's job.
#
# Usage:  tools/check_fold_train.sh <session-trailer-substring>
#         tools/check_fold_train.sh --selftest
# Exit:   0 clean · 4 a conflict · 5 a selftest failed on the merged tree · 2 unusable

set -uo pipefail

_repo_root() { git rev-parse --show-toplevel 2>/dev/null; }

train() {
    local sess="$1"
    [ -n "$sess" ] || { echo "[train] BLOCKED: no session trailer given." >&2; return 2; }
    local root; root="$(_repo_root)" || { echo "[train] BLOCKED: not a git repo." >&2; return 2; }
    cd "$root" || return 2
    git fetch origin --quiet 2>/dev/null || true
    git rev-parse --verify -q origin/main >/dev/null || {
        echo "[train] BLOCKED: origin/main not found." >&2; return 2; }

    local mine=() excluded=()
    while read -r r; do
        local b="${r#origin/}"
        [ "$b" = "HEAD" ] && continue
        git merge-base --is-ancestor "$r" origin/main 2>/dev/null && continue
        git log -1 --format='%B' "$r" 2>/dev/null | grep -q "$sess" || continue
        case "$b" in
            lane/*) mine+=("$b") ;;
            *)      excluded+=("$b") ;;
        esac
    done < <(git for-each-ref --format='%(refname:short)' refs/remotes/origin)

    if [ "${#mine[@]}" -eq 0 ]; then
        echo "[train] BLOCKED: no lane/* branches carry that trailer and are off main." >&2
        echo "        Either the trailer is wrong or everything is folded — those are" >&2
        echo "        different states and this cannot tell them apart, so it refuses." >&2
        return 2
    fi

    echo "[train] ${#mine[@]} branch(es) in the train, tips as measured now:"
    local b
    for b in "${mine[@]}"; do
        printf '[train]   %-46s %s\n' "$b" "$(git rev-parse --short "origin/$b")"
    done
    if [ "${#excluded[@]}" -gt 0 ]; then
        echo "[train] EXCLUDED (carry the trailer, not under lane/ — archive branches):"
        for b in "${excluded[@]}"; do
            printf '[train]   %-46s %s\n' "$b" "$(git rev-parse --short "origin/$b")"
        done
    fi

    local wt; wt="$(mktemp -d "${TMPDIR:-/tmp}/foldtrain.XXXXXX")"
    rm -rf "$wt"
    git worktree add --detach "$wt" origin/main >/dev/null 2>&1 || {
        echo "[train] BLOCKED: could not create a scratch worktree." >&2; return 2; }
    # shellcheck disable=SC2064
    trap "git worktree remove --force '$wt' >/dev/null 2>&1; git worktree prune >/dev/null 2>&1" RETURN

    local rc=0 conflicts=()
    ( cd "$wt" || exit 2
      for b in "${mine[@]}"; do
          git merge --no-edit -q "origin/$b" >/dev/null 2>&1 || {
              echo "CONFLICT:$b:$(git diff --name-only --diff-filter=U | tr '\n' ' ')"
              git merge --abort 2>/dev/null
          }
      done ) > "$wt.merges" 2>/dev/null

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        case "$line" in CONFLICT:*)
            local nb="${line#CONFLICT:}"; local bn="${nb%%:*}"; local files="${nb#*:}"
            echo "[train] ⛔ CONFLICT ${bn} — ${files}" >&2
            conflicts+=("$bn"); rc=4 ;;
        esac
    done < "$wt.merges"
    rm -f "$wt.merges"

    if [ "$rc" -eq 0 ]; then
        # re-merge for real in the worktree we keep, since the subshell above ran in the same
        # directory but we need the merged state present for the selftests
        ( cd "$wt" && for b in "${mine[@]}"; do git merge --no-edit -q "origin/$b" >/dev/null 2>&1; done )
        echo "[train] all ${#mine[@]} merged clean · combined tree $(cd "$wt" && git rev-parse --short HEAD) · dirty $(cd "$wt" && git status --porcelain | wc -l)"
    fi

    # CONTROL: the merge predicate must be able to say CONFLICT. Without this, N clean merges
    # are N readings from an instrument never shown capable of the other answer.
    local ctl
    ctl="$( cd "$wt" && git reset -q --hard origin/main >/dev/null 2>&1
            printf 'A\n' > _FOLDTRAIN_CANARY.md && git add _FOLDTRAIN_CANARY.md && git commit -q -m a
            A=$(git rev-parse HEAD); git reset -q --hard HEAD~1
            printf 'B\n' > _FOLDTRAIN_CANARY.md && git add _FOLDTRAIN_CANARY.md && git commit -q -m b
            if git merge --no-edit -q "$A" >/dev/null 2>&1; then echo BROKEN; else echo OK; fi
            git merge --abort 2>/dev/null; git reset -q --hard origin/main >/dev/null 2>&1 )"
    if [ "$ctl" = "OK" ]; then
        echo "[train] control: a constructed add/add still CONFLICTS — the predicate can fire"
    else
        echo "[train] ⛔ CONTROL FAILED: an add/add merged clean. Every result above is suspect." >&2
        return 2
    fi

    if [ "$rc" -ne 0 ]; then
        echo "[train] ${#conflicts[@]} conflict(s). The train does NOT fold as one." >&2
        return $rc
    fi

    # selftests on the merged tree
    ( cd "$wt" && for b in "${mine[@]}"; do git merge --no-edit -q "origin/$b" >/dev/null 2>&1; done )
    local failed=0 ran=0 t out
    for t in "$wt"/tools/*.sh; do
        [ -x "$t" ] || continue
        grep -q -- '--selftest' "$t" 2>/dev/null || continue
        out="$( cd "$wt" && "./tools/$(basename "$t")" --selftest 2>&1 )"
        printf '[train]   %-30s %s\n' "$(basename "$t")" "$(printf '%s' "$out" | grep -a 'selftest:' | tail -1)"
        printf '%s' "$out" | grep -aq 'selftest: [0-9]* passed, 0 failed' || failed=$((failed+1))
        ran=$((ran+1))
    done
    for t in "$wt"/tools/*.py; do
        [ -f "$t" ] || continue
        grep -q -- '--selftest' "$t" 2>/dev/null || continue
        out="$( cd "$wt" && python3 "tools/$(basename "$t")" --selftest 2>&1 )"
        printf '[train]   %-30s %s\n' "$(basename "$t")" "$(printf '%s' "$out" | grep -a 'selftest:' | tail -1)"
        printf '%s' "$out" | grep -aq 'selftest: [0-9]* passed, 0 failed' || failed=$((failed+1))
        ran=$((ran+1))
    done
    echo "[train] ${ran} selftest suite(s) run on the merged tree, ${failed} failing"
    if [ "$ran" -eq 0 ]; then
        echo "[train] ⛔ BLOCKED: no selftests found on the merged tree. Zero suites passing is" >&2
        echo "        not the same as zero suites failing." >&2
        return 2
    fi
    [ "$failed" -eq 0 ] || { echo "[train] ${failed} suite(s) failed on the merged tree." >&2; return 5; }
    echo "[train] TRAIN IS CLEAN as of these tips. If ls-remote disagrees, this is stale."
    return 0
}

# ── self-test ────────────────────────────────────────────────────────────────
# Builds a throwaway repo with real branches and real trailers, so the derivation, the merge
# and the conflict detection are exercised against git rather than against a mock.
selftest() {
    local d pass=0 fail=0 self
    self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    d="$(mktemp -d "${TMPDIR:-/tmp}/traintest.XXXXXX")"
    # shellcheck disable=SC2064
    trap "rm -rf '$d'" EXIT
    local SESS="session_TESTONLY_abc123"

    ( cd "$d" && git init -q origin.git --bare ) >/dev/null 2>&1
    ( cd "$d" && git clone -q origin.git work ) >/dev/null 2>&1
    cd "$d/work" || return 2
    git config user.email t@t; git config user.name t
    mkdir -p tools
    printf '#!/usr/bin/env bash\ncase "${1:-}" in --selftest) echo "selftest: 1 passed, 0 failed";; esac\n' > tools/ok.sh
    chmod +x tools/ok.sh
    printf 'base\n' > shared.txt
    git add -A && git commit -q -m "base"
    git branch -M main && git push -q origin main

    mk() { # branch, file, content
        git checkout -q -b "$1" main
        printf '%s\n' "$3" > "$2"; git add -A
        git commit -q -m "$1

Claude-Session: https://claude.ai/code/$SESS"
        git push -q origin "$1"; git checkout -q main
    }
    mk lane/a a.txt alpha
    mk lane/b b.txt beta
    mk store-archive arch.txt archive     # carries the trailer, NOT under lane/
    git fetch -q origin

    arm() { local name="$1" want="$2" got; shift 2; "$@" >/dev/null 2>&1; got=$?
        if [ "$got" -eq "$want" ]; then pass=$((pass+1)); printf '  ok    %-46s exit %s\n' "$name" "$got"
        else fail=$((fail+1)); printf '  FAIL  %-46s exit %s (wanted %s)\n' "$name" "$got" "$want"; fi; }

    arm "a clean train"                    0 "$self" "$SESS"

    local out; out="$("$self" "$SESS" 2>&1)"
    if printf '%s' "$out" | grep -q 'EXCLUDED' && printf '%s' "$out" | grep -q 'store-archive'; then
        pass=$((pass+1)); printf '  ok    %-46s reported, not dropped\n' "non-lane branch EXCLUDED"
    else fail=$((fail+1)); printf '  FAIL  %-46s not reported\n' "non-lane branch EXCLUDED"; fi
    if printf '%s' "$out" | grep -q 'lane/a' && printf '%s' "$out" | grep -q 'lane/b'; then
        pass=$((pass+1)); printf '  ok    %-46s both listed\n' "derivation selects the lane branches"
    else fail=$((fail+1)); printf '  FAIL  %-46s\n' "derivation missed a lane branch"; fi
    if printf '%s' "$out" | grep -q 'control: a constructed add/add still CONFLICTS'; then
        pass=$((pass+1)); printf '  ok    %-46s present\n' "conflict control ran"
    else fail=$((fail+1)); printf '  FAIL  %-46s absent\n' "conflict control ran"; fi

    # a REAL conflict between two branches in the train
    mk lane/c shared.txt "from-c"
    git checkout -q -b lane/d main
    printf 'from-d\n' > shared.txt; git add -A
    git commit -q -m "lane/d

Claude-Session: https://claude.ai/code/$SESS"
    git push -q origin lane/d; git checkout -q main; git fetch -q origin
    arm "two branches conflicting"          4 "$self" "$SESS"

    arm "no trailer given"                  2 "$self" ""
    arm "a trailer nothing carries"         2 "$self" "session_NOSUCH_zzz"

    echo
    echo "selftest: ${pass} passed, ${fail} failed"
    [ "$fail" -eq 0 ]
}

case "${1:-}" in
    --selftest) selftest ;;
    "")         echo "usage: $0 <session-trailer-substring> | --selftest" >&2; exit 2 ;;
    *)          train "$1" ;;
esac
