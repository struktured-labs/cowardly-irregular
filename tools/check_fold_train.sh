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
# TWO SELECTORS, MATCHED AS A UNION, AND THE REASON IS A LIVE INSTANCE OF THE DEFECT
# ----------------------------------------------------------------------------------
# This originally derived the train from the `Claude-Session:` trailer. On 2026-09-11 my commit
# attribution changed and that trailer STOPPED BEING EMITTED. The tool was not wrong and no
# branch was lost — but the selection rule acquired an expiry date it did not have when
# written, and the failure would have been SILENT: a branch pushed after the change simply
# would not appear in the train, and a missing row looks exactly like a short list.
#
# So the selector is now a union: a branch is mine if its tip carries EITHER the legacy session
# trailer OR a `Lane: <name>` trailer I control and will keep emitting. Spanning the transition
# rather than swapping at it means the pre-change branches stay findable by the same tool that
# finds the post-change ones, and the output names WHICH marker matched so the changeover is
# visible rather than inferred.
#
# Usage:  tools/check_fold_train.sh --lane <lane-name> [--session <trailer-substring>]
#         tools/check_fold_train.sh <session-trailer-substring>      (legacy, still works)
#         tools/check_fold_train.sh --selftest
# Exit:   0 clean · 4 a conflict · 5 a selftest failed on the merged tree · 2 unusable

set -uo pipefail

_repo_root() { git rev-parse --show-toplevel 2>/dev/null; }

train() {
    local sess="${1:-}" lane="${2:-}"
    if [ -z "$sess" ] && [ -z "$lane" ]; then
        echo "[train] BLOCKED: no selector given. Pass --lane <name> and/or a session trailer." >&2
        return 2
    fi
    local root; root="$(_repo_root)" || { echo "[train] BLOCKED: not a git repo." >&2; return 2; }
    cd "$root" || return 2
    git fetch origin --quiet 2>/dev/null || true
    git rev-parse --verify -q origin/main >/dev/null || {
        echo "[train] BLOCKED: origin/main not found." >&2; return 2; }

    local mine=() excluded=() marks=()
    while read -r r; do
        local b="${r#origin/}"
        [ "$b" = "HEAD" ] && continue
        git merge-base --is-ancestor "$r" origin/main 2>/dev/null && continue
        local msg mark=""
        msg="$(git log -1 --format='%B' "$r" 2>/dev/null)"
        if [ -n "$lane" ] && printf '%s' "$msg" | grep -qE "^Lane:[[:space:]]*${lane}[[:space:]]*$"; then
            mark="Lane"
        elif [ -n "$sess" ] && printf '%s' "$msg" | grep -q "$sess"; then
            mark="session"
        else
            continue
        fi
        case "$b" in
            lane/*) mine+=("$b"); marks+=("$mark") ;;
            *)      excluded+=("$b") ;;
        esac
    done < <(git for-each-ref --format='%(refname:short)' refs/remotes/origin)

    if [ "${#mine[@]}" -eq 0 ]; then
        echo "[train] BLOCKED: no lane/* branches match the selector(s) and are off main." >&2
        echo "        Either the trailer is wrong or everything is folded — those are" >&2
        echo "        different states and this cannot tell them apart, so it refuses." >&2
        return 2
    fi

    echo "[train] ${#mine[@]} branch(es) in the train, tips as measured now:"
    local b i=0
    for b in "${mine[@]}"; do
        printf '[train]   %-44s %-9s via %s\n' "$b" "$(git rev-parse --short "origin/$b")" "${marks[$i]}"
        i=$((i+1))
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
    # THREE BUCKETS, because "could not evaluate" is not "failed" and neither is "passed".
    # The first version counted any suite without a parseable "N passed, 0 failed" line as
    # FAILING, and immediately red-flagged tools/audit_whoop.py — another lane's tool, which
    # uses "selftest: PASS" and needs a python module absent from this box. It was not broken;
    # my predicate was. But an unevaluable suite must not be silently dropped either: it is
    # reported, named, and counted separately so it cannot be mistaken for a pass.
    local failed=0 ran=0 unknown=0 t out ec base cmd
    for t in "$wt"/tools/*.sh "$wt"/tools/*.py; do
        [ -f "$t" ] || continue
        base="$(basename "$t")"
        grep -q -- '--selftest' "$t" 2>/dev/null || continue
        case "$base" in *.py) cmd="python3 tools/$base" ;; *) [ -x "$t" ] || continue; cmd="./tools/$base" ;; esac
        out="$( cd "$wt" && $cmd --selftest 2>&1 )"; ec=$?
        if printf '%s' "$out" | grep -aq 'selftest: [0-9]* passed, 0 failed'; then
            printf '[train]   PASS    %-28s %s\n' "$base" "$(printf '%s' "$out" | grep -a 'selftest:' | tail -1)"
            ran=$((ran+1))
        elif printf '%s' "$out" | grep -aq 'selftest: [0-9]* passed, [0-9]* failed'; then
            printf '[train]   FAIL    %-28s %s\n' "$base" "$(printf '%s' "$out" | grep -a 'selftest:' | tail -1)" >&2
            failed=$((failed+1)); ran=$((ran+1))
        else
            printf '[train]   UNKNOWN %-28s exit %s, no parseable result (%s)\n' "$base" "$ec" \
                "$(printf '%s' "$out" | tail -1 | cut -c1-52)"
            unknown=$((unknown+1))
        fi
    done
    echo "[train] ${ran} suite(s) evaluated, ${failed} failing, ${unknown} unevaluable"
    if [ "$unknown" -gt 0 ]; then
        echo "[train]   unevaluable suites are NOT counted as passing. They are another lane's"
        echo "[train]   format or a missing dependency on this box — check them by hand before"
        echo "[train]   treating this run as complete."
    fi
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
    # A branch carrying ONLY the Lane trailer — i.e. pushed AFTER the attribution change.
    mk_lane() {
        git checkout -q -b "$1" main
        printf '%s\n' "$3" > "$2"; git add -A
        git commit -q -m "$1

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Lane: testlane"
        git push -q origin "$1"; git checkout -q main
    }
    mk lane/a a.txt alpha                 # session trailer only (pre-change)
    mk lane/b b.txt beta                  # session trailer only (pre-change)
    mk_lane lane/newer n.txt newer        # Lane trailer only  (post-change)
    mk store-archive arch.txt archive     # carries the trailer, NOT under lane/
    git fetch -q origin

    arm() { local name="$1" want="$2" got; shift 2; "$@" >/dev/null 2>&1; got=$?
        if [ "$got" -eq "$want" ]; then pass=$((pass+1)); printf '  ok    %-46s exit %s\n' "$name" "$got"
        else fail=$((fail+1)); printf '  FAIL  %-46s exit %s (wanted %s)\n' "$name" "$got" "$want"; fi; }

    arm "a clean train (union selector)"   0 "$self" --lane testlane --session "$SESS"

    # THE TRANSITION IS THE POINT: each selector alone must find only its own branches, and
    # the union must find both. A tool that swapped one marker for the other would pass a
    # "finds my branches" arm while silently dropping everything from the other side of the
    # changeover — which is exactly the failure this rewrite exists to prevent.
    local s_only; s_only="$("$self" --session "$SESS" 2>&1)"
    if printf '%s' "$s_only" | grep -q 'lane/a' && ! printf '%s' "$s_only" | grep -q 'lane/newer'; then
        pass=$((pass+1)); printf '  ok    %-46s pre-change only\n' "--session alone"
    else fail=$((fail+1)); printf '  FAIL  %-46s\n' "--session alone picked up a Lane-only branch"; fi
    local lo; lo="$("$self" --lane testlane 2>&1)"
    if printf '%s' "$lo" | grep -q 'lane/newer' && ! printf '%s' "$lo" | grep -q 'lane/a'; then
        pass=$((pass+1)); printf '  ok    %-46s post-change only\n' "--lane alone"
    else fail=$((fail+1)); printf '  FAIL  %-46s\n' "--lane alone picked up a session-only branch"; fi

    local out; out="$("$self" --lane testlane --session "$SESS" 2>&1)"
    if printf '%s' "$out" | grep -q 'lane/a' && printf '%s' "$out" | grep -q 'lane/newer'; then
        pass=$((pass+1)); printf '  ok    %-46s both sides found\n' "union spans the changeover"
    else fail=$((fail+1)); printf '  FAIL  %-46s\n' "union missed one side of the changeover"; fi
    if printf '%s' "$out" | grep -q 'via Lane' && printf '%s' "$out" | grep -q 'via session'; then
        pass=$((pass+1)); printf '  ok    %-46s reported per branch\n' "which marker matched"
    else fail=$((fail+1)); printf '  FAIL  %-46s\n' "matched marker not reported"; fi
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
    arm "two branches conflicting"          4 "$self" --lane testlane --session "$SESS"

    arm "no selector given"                 2 "$self" ""
    arm "a selector nothing carries"        2 "$self" --lane nosuchlane

    echo
    echo "selftest: ${pass} passed, ${fail} failed"
    [ "$fail" -eq 0 ]
}

SESS=""; LANE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --selftest) selftest; exit $? ;;
        --lane)     LANE="${2:-}"; shift 2 ;;
        --session)  SESS="${2:-}"; shift 2 ;;
        "")         shift ;;
        *)          SESS="$1"; shift ;;   # legacy positional
    esac
done
if [ -z "$SESS" ] && [ -z "$LANE" ]; then
    echo "usage: $0 --lane <name> [--session <trailer>] | <session-trailer> | --selftest" >&2
    exit 2
fi
train "$SESS" "$LANE"
