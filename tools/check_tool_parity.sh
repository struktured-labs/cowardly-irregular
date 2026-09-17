#!/usr/bin/env bash
# Is the tool I ASK the same tool that will RUN?
#
# WHY THIS EXISTS
# ---------------
# This lane decides whether to publish by running `tools/publish_detached.sh --check` out of a
# working tree, and reports the answer as a fact about what the chain will do. But the chain
# runs from `tmp/pub<N>` AT THE TAG — a different copy of the same file. When they diverge, the
# check answers about a program that is not the one that executes.
#
# It is not hypothetical for this lane: a tool fix ships most hours, so between writing one and
# seeing it folded, the copy I query carries a capability the tag does not. On 2026-09-17 the
# `--check` mode and its capture-growth corroboration existed in my worktree for two hours
# before `.384` folded them — every hold I reported in that window was measured with an
# instrument the chain did not have.
#
# The failure is silent in both directions: a query copy that is AHEAD says CLEAR or HELD for a
# reason the chain cannot apply, and one that is BEHIND misses a refusal the chain will make.
#
# Verified 2026-09-17 after the fold: query copy, origin/main and v3.33.385-alpha all carry
# `_capture_growth` 3x and the `--check` verdict 2x — agreement on the CURRENT tool rather than
# three copies of an old one, which is the check this would otherwise pass vacuously.
#
# Usage:  tools/check_tool_parity.sh <tag>            compare working copy · origin/main · tag
#         tools/check_tool_parity.sh --selftest
# Exit:   0 they agree · 5 they diverge · 2 could not evaluate
set -uo pipefail

TOOLS="${PARITY_TOOLS:-tools/publish_detached.sh tools/tag_gate_evidence.sh tools/store_status.sh tools/verify_store_artifact.sh}"

run() {
    local tag="${1:-}"
    [ -n "$tag" ] || { echo "[parity] usage: $0 <tag>" >&2; return 2; }
    git rev-parse -q --verify "${tag}^{commit}" >/dev/null 2>&1 \
        || { echo "[parity] unknown tag ${tag}" >&2; return 2; }
    local rc=0 f local_h main_h tag_h
    for f in $TOOLS; do
        [ -r "$f" ] || { echo "[parity] BLOCKED: ${f} is not readable here — a comparison that cannot read one side is not a matching one." >&2; rc=2; continue; }
        local_h="$(md5sum < "$f" | cut -d' ' -f1)"
        main_h="$(git show "origin/main:$f" 2>/dev/null | md5sum | cut -d' ' -f1)"
        tag_h="$(git show "${tag}:$f" 2>/dev/null | md5sum | cut -d' ' -f1)"
        if [ "$local_h" = "$tag_h" ]; then
            printf '  ok       %-34s the copy I ask IS the copy that runs\n' "$(basename "$f")"
        else
            local why="differs from ${tag}"
            [ "$local_h" = "$main_h" ] && why="matches origin/main but NOT ${tag} — the tag predates a fold"
            [ "$main_h" = "$tag_h" ] && why="AHEAD of both ${tag} and origin/main — unfolded local work"
            printf '  DIVERGE  %-34s %s\n' "$(basename "$f")" "$why"
            rc=5
        fi
    done
    if [ "$rc" -eq 0 ]; then
        echo "[parity] every decision tool agrees with ${tag}: what I ask is what will run."
    elif [ "$rc" -eq 5 ]; then
        echo "[parity] DIVERGENCE — a --check answer from here is about a different program than the chain will run." >&2
        echo "[parity] That is not necessarily wrong; it is unmeasured. Say which copy you queried." >&2
    fi
    return $rc
}

selftest() {
    local pass=0 fail=0
    _eq() {
        if [ "$2" = "$3" ]; then printf '  ok    %-56s %s\n' "$1" "$2"; pass=$((pass+1))
        else printf '  FAIL  %-56s got %s want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
    }
    _has() { case "$2" in *"$3"*) _eq "$1" yes yes ;; *) _eq "$1" no yes ;; esac; }
    mkdir -p "$HOME/.cache"
    local d; d="$(mktemp -d "$HOME/.cache/parity.XXXXXX")"
    local origin="$d/origin.git" lane="$d/lane"
    git init -q --bare "$origin"; git init -q "$lane"; cd "$lane"
    git config user.email t@t; git config user.name t
    mkdir -p tools; echo "v1" > tools/publish_detached.sh
    git add -A; git commit -qm one; git remote add origin "$origin"; git push -q origin HEAD:main
    git fetch -q origin 2>/dev/null
    git tag -a v9.9.1-alpha -m v9.9.1-alpha

    local out ec
    # 1. all three identical -> agree
    out="$(PARITY_TOOLS='tools/publish_detached.sh' bash "$SELF" v9.9.1-alpha 2>&1)"; ec=$?
    _eq  "identical everywhere AGREES"                  "$ec" "0"
    _has "  ...and says what I ask is what will run"    "$out" "what I ask is what will run"

    # 2. local AHEAD of both -> unfolded local work, the normal mid-hour state
    echo "v2-local" > tools/publish_detached.sh
    out="$(PARITY_TOOLS='tools/publish_detached.sh' bash "$SELF" v9.9.1-alpha 2>&1)"; ec=$?
    _eq  "local AHEAD of tag and main DIVERGES"         "$ec" "5"
    _has "  ...and names it unfolded local work"        "$out" "unfolded local work"

    # 3. local == main but the TAG predates the fold — the case that bit this lane
    git add -A; git commit -qm two; git push -q origin HEAD:main; git fetch -q origin 2>/dev/null
    out="$(PARITY_TOOLS='tools/publish_detached.sh' bash "$SELF" v9.9.1-alpha 2>&1)"; ec=$?
    _eq  "local == main but TAG is older DIVERGES"      "$ec" "5"
    _has "  ...and says the tag predates a fold"        "$out" "predates a fold"

    # 4. ...and once the tag moves with it, they agree again — the floor. Without this, every
    #    arm above is satisfied by a tool that reports DIVERGE unconditionally.
    git tag -a v9.9.2-alpha -m v9.9.2-alpha
    out="$(PARITY_TOOLS='tools/publish_detached.sh' bash "$SELF" v9.9.2-alpha 2>&1)"; ec=$?
    _eq  "  ...and a tag cut AFTER the fold agrees"     "$ec" "0"

    # 5. a tool that is not readable is BLOCKED, never silently skipped
    out="$(PARITY_TOOLS='tools/no_such_tool.sh' bash "$SELF" v9.9.2-alpha 2>&1)"; ec=$?
    _eq  "an unreadable tool is BLOCKED"                "$ec" "2"
    # 6. an unknown tag decides nothing
    out="$(PARITY_TOOLS='tools/publish_detached.sh' bash "$SELF" v0.0.0-nope 2>&1)"; ec=$?
    _eq  "an unknown tag is BLOCKED"                    "$ec" "2"

    cd /; rm -rf "$d"
    printf '\nselftest: %s passed, %s failed\n' "$pass" "$fail"
    [ "$fail" -eq 0 ]
}

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

case "${1:-}" in
    --selftest) selftest; exit $? ;;
    *) run "${1:-}"; exit $? ;;
esac
