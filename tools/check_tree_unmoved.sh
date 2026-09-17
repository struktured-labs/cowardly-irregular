#!/usr/bin/env bash
# Is the tree that shipped the tree that was gated?
#
# WHY THIS EXISTS
# ---------------
# publish_all.sh verifies HEAD == tag and `git status --porcelain` empty BEFORE the channels,
# and never again. Its own comment says why that matters: "The chains export the WORKING TREE,
# so publishing from a tree that is not at the tag ships something the label does not describe."
# The export happens ~25 minutes after that check.
#
# ⛔ AND THE READ-BACK CANNOT COVER IT, BY CONSTRUCTION. verify_store_artifact.sh compares the
# STORE against the LOCAL BUILD. If the local build came from a tree that moved after the gate,
# both sides are that same moved tree and agree perfectly. The strongest verification this lane
# has is blind to this one thing, because both of its sides are downstream of the change.
#
# The only thing tying the uploaded bytes to the GATED tree is a check taken before any of them
# existed.
#
# Measured on a completed publish (tmp/pub371, v3.33.371-alpha) 2026-09-17: porcelain EMPTY and
# HEAD still at the tag afterwards, so a post-condition does not false-fire. The imports write
# into .godot/ and tmp/, both gitignored, and the .import sidecars are committed — which is what
# tag_gate_evidence.sh means when it says committing them makes a tag gate-clean.
#
# Usage:  tools/check_tree_unmoved.sh --record <tag> <file>    before the channels
#         tools/check_tree_unmoved.sh --verify <tag> <file>    after them
#         tools/check_tree_unmoved.sh --selftest
# Exit:   0 unmoved · 5 the tree moved after the gate · 2 could not evaluate
set -uo pipefail

_fingerprint() {
    local head porcelain
    head="$(git rev-parse HEAD 2>/dev/null)" || return 1
    # A DIGEST of the porcelain, not its line count: a file replaced by another leaves the count
    # unchanged. Sorted, because status order is not guaranteed stable.
    # ⛔ ONE TOKEN. cksum prints "<sum> <bytes>" — a SPACE inside the value — and the record is
    # space-delimited, so `cut -d' ' -f1,2` split this field in half and an UNCHANGED tree
    # compared unequal to itself. Joined with a dash: a value must not contain its own delimiter.
    porcelain="$(git status --porcelain 2>/dev/null | sort | cksum | tr -s ' ' | tr ' ' '-' | sed 's/-$//')"
    printf 'head=%s porcelain=%s' "$head" "$porcelain"
}

run() {
    local mode="${1:-}" tag="${2:-}" file="${3:-}"
    [ -n "$mode" ] && [ -n "$tag" ] && [ -n "$file" ] || { echo "[tree] usage: $0 --record|--verify <tag> <file>" >&2; return 2; }
    local tag_sha; tag_sha="$(git rev-parse -q --verify "${tag}^{commit}" 2>/dev/null)" \
        || { echo "[tree] unknown tag ${tag}" >&2; return 2; }
    local now; now="$(_fingerprint)" || { echo "[tree] not a git worktree" >&2; return 2; }

    case "$mode" in
        --record)
            printf '%s tag=%s\n' "$now" "$tag_sha" > "$file" || { echo "[tree] cannot write ${file}" >&2; return 2; }
            echo "[tree] recorded the gated tree: ${now%% *}"
            return 0 ;;
        --verify)
            [ -r "$file" ] || { echo "[tree] BLOCKED: no record at ${file} — nothing to compare the shipped tree against." >&2; return 2; }
            local before; before="$(cut -d' ' -f1,2 < "$file")"
            if [ "$before" = "$now" ]; then
                echo "[tree] unmoved: the tree that shipped is the tree that was gated."
                return 0
            fi
            echo "[tree] BLOCKED: THE TREE MOVED AFTER THE GATE." >&2
            echo "[tree]   gated:   ${before}" >&2
            echo "[tree]   shipped: ${now}" >&2
            echo "[tree]   The chains export the WORKING TREE, so the uploaded artifacts may not" >&2
            echo "[tree]   be the gated commit. The store read-back cannot see this: it compares" >&2
            echo "[tree]   the store against the LOCAL BUILD, and both are downstream of the change." >&2
            return 5 ;;
        *) echo "[tree] unknown mode ${mode}" >&2; return 2 ;;
    esac
}

selftest() {
    local pass=0 fail=0
    _eq() {
        if [ "$2" = "$3" ]; then printf '  ok    %-56s %s\n' "$1" "$2"; pass=$((pass+1))
        else printf '  FAIL  %-56s got %s want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
    }
    _has() { case "$2" in *"$3"*) _eq "$1" yes yes ;; *) _eq "$1" no yes ;; esac; }
    mkdir -p "$HOME/.cache"
    local d; d="$(mktemp -d "$HOME/.cache/treemoved.XXXXXX")"
    local r="$d/repo"; git init -q "$r"; cd "$r"
    git config user.email t@t; git config user.name t
    echo "src" > a.gd; echo "tmp/" > .gitignore; git add -A; git commit -qm one
    git tag -a v9.9.1-alpha -m v9.9.1-alpha
    local rec="$d/rec"

    local out ec
    out="$(bash "$SELF" --record v9.9.1-alpha "$rec" 2>&1)"; ec=$?
    _eq "recording a clean tree succeeds"                "$ec" "0"
    out="$(bash "$SELF" --verify v9.9.1-alpha "$rec" 2>&1)"; ec=$?
    _eq "an UNCHANGED tree verifies"                     "$ec" "0"
    _has "  ...and says so"                              "$out" "the tree that shipped is the tree that was gated"

    # ⛔ the case this exists for: a tracked file edited AFTER the record
    echo "tampered" > a.gd
    out="$(bash "$SELF" --verify v9.9.1-alpha "$rec" 2>&1)"; ec=$?
    _eq "a tracked file edited after the gate is CAUGHT"  "$ec" "5"
    _has "  ...and names the read-back's blind spot"      "$out" "both are downstream of the change"
    git checkout -q -- a.gd

    # HEAD moving is the other half — an import cannot do it, a checkout can
    echo "two" > b.gd; git add b.gd; git commit -qm two
    out="$(bash "$SELF" --verify v9.9.1-alpha "$rec" 2>&1)"; ec=$?
    _eq "HEAD moving after the gate is CAUGHT"           "$ec" "5"
    git reset -q --hard v9.9.1-alpha

    # ⚠️ IGNORED paths are what the publish itself writes (.godot/, tmp/). If those tripped it,
    # the check would fire on every publish and be deleted within a day.
    mkdir -p tmp && echo "build output" > tmp/artifact.bin
    out="$(bash "$SELF" --verify v9.9.1-alpha "$rec" 2>&1)"; ec=$?
    _eq "IGNORED build output does NOT trip it"          "$ec" "0"

    # ...and the floor: it must still be able to say MOVED in that same state, or the arm above
    # is satisfied by a check that has stopped working.
    echo "tampered again" > a.gd
    out="$(bash "$SELF" --verify v9.9.1-alpha "$rec" 2>&1)"; ec=$?
    _eq "  ...and it can still CATCH a real change then" "$ec" "5"
    git checkout -q -- a.gd; rm -rf tmp

    # a REPLACEMENT that keeps the line count — why the fingerprint is a digest, not a count
    echo "x" > new.gd
    bash "$SELF" --record v9.9.1-alpha "$d/rec2" >/dev/null 2>&1
    rm -f new.gd; echo "y" > other.gd
    out="$(bash "$SELF" --verify v9.9.1-alpha "$d/rec2" 2>&1)"; ec=$?
    _eq "a same-COUNT replacement is CAUGHT"             "$ec" "5"
    rm -f other.gd

    out="$(bash "$SELF" --verify v9.9.1-alpha "$d/missing" 2>&1)"; ec=$?
    _eq "a missing record is BLOCKED, not passed"        "$ec" "2"
    out="$(bash "$SELF" --verify v0.0.0-nope "$rec" 2>&1)"; ec=$?
    _eq "an unknown tag is BLOCKED"                      "$ec" "2"

    cd /; rm -rf "$d"
    printf '\nselftest: %s passed, %s failed\n' "$pass" "$fail"
    [ "$fail" -eq 0 ]
}

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

case "${1:-}" in
    --selftest) selftest; exit $? ;;
    *) run "$@"; exit $? ;;
esac
