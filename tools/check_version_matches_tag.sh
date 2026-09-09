#!/usr/bin/env bash
# Refuse to publish a build whose OWN displayed version disagrees with the label it will
# carry on the store.
#
# WHY THIS EXISTS
# ---------------
# v3.33.247-alpha shipped to all three channels on 2026-09-09 with `Version.gd` still
# reading 3.33.246-alpha. It was a tools-only re-cut and the semver bump was missed, so the
# store said .247 and the title screen said .246. Nothing in the deploy chain looked, and I
# published it three times over — once per channel.
#
# The fold's own test_version_display_regression caught the same slip at merge time, which
# is what surfaced it. That test protects the REPOSITORY. This protects the PUBLISH, and
# they are different moments: a tag can be cut, gated and pushed between the two, which is
# exactly what happened.
#
# WHY IT MATTERS BEYOND TIDINESS
# ------------------------------
# The version on screen is the only thing a player can quote in a bug report. When it
# disagrees with the store label, every report from that build points at the wrong tree —
# and the mismatch is invisible from either side alone. It is also the exact provenance
# claim the deploy lane exists to keep honest: `+sha` in the userversion says which commit
# was exported, and SEMVER says what the build will tell a human it is. Both or neither.
#
# THE FAILURE DIRECTION
# ---------------------
# Blocking is the safe outcome, so anything short of a proven match blocks: a mismatch, an
# unreadable Version.gd, a missing SEMVER line, an empty parse. An empty parse must NEVER
# read as agreement — that is the shape that let five other instruments pass vacuously
# across this codebase, and here it would be a silent green on a file the script could not
# even find.
#
# Usage:  tools/check_version_matches_tag.sh <label>     e.g. v3.33.248-alpha  or  3.33.248-alpha
#         tools/check_version_matches_tag.sh --selftest
# Exit:   0 = proven match · 1 = mismatch · 2 = could not read the version (also blocks)

set -uo pipefail

VERSION_FILE="${VERSION_FILE:-src/meta/Version.gd}"

_semver_in_tree() {
    # The single source of truth is `const SEMVER := "x.y.z-tag"`. Anchored on that
    # declaration rather than a loose version-shaped regex: a bare pattern would also match
    # a version mentioned in a comment or a docstring, and the first such match would win.
    sed -n 's/^[[:space:]]*const[[:space:]]\+SEMVER[[:space:]]*:=[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$VERSION_FILE" 2>/dev/null | head -1
}

check() {
    local label="$1"
    if [ -z "$label" ]; then
        echo "[version] BLOCKED: no version label given — nothing to compare against" >&2
        return 2
    fi
    if [ ! -f "$VERSION_FILE" ]; then
        echo "[version] BLOCKED: ${VERSION_FILE} not found. The source of truth moved; fix this" >&2
        echo "          check rather than letting a publish proceed unverified." >&2
        return 2
    fi

    local in_tree want
    in_tree="$(_semver_in_tree)"
    want="${label#v}"          # the store label carries a leading v, SEMVER does not

    if [ -z "$in_tree" ]; then
        echo "[version] BLOCKED: could not read 'const SEMVER := \"...\"' from ${VERSION_FILE}." >&2
        echo "          An unreadable version is NOT a matching one — the declaration's shape" >&2
        echo "          changed, and a looser parse here would start matching comments." >&2
        return 2
    fi

    if [ "$in_tree" != "$want" ]; then
        echo "[version] BLOCKED: this build calls itself ${in_tree}, but it would publish as ${want}." >&2
        echo "          The store label and the title screen would disagree, so every bug report" >&2
        echo "          from this build would name the wrong tree. Bump ${VERSION_FILE} or tag the" >&2
        echo "          version the tree actually claims." >&2
        echo "          (v3.33.247-alpha shipped this way to all three channels, 2026-09-09.)" >&2
        return 1
    fi

    echo "[version] ${in_tree} in ${VERSION_FILE} == ${want} on the store label"
    return 0
}

# ── self-test ────────────────────────────────────────────────────────────────
# A check that only ever sees matching input proves nothing, so every arm below names its
# expected exit and BOTH outcomes must occur — a check hardwired to 0 passes every match
# case, and one hardwired to 1 passes every block case.
selftest() {
    local dir pass=0 fail=0 saw_ok=0 saw_block=0
    dir="$(mktemp -d "${TMPDIR:-/tmp}/vercheck.XXXXXX")"
    # shellcheck disable=SC2064
    trap "rm -rf '$dir'" EXIT
    mkdir -p "$dir/src/meta"

    arm() { # name, expected-exit, file-contents (or __MISSING__), label
        local name="$1" want="$2" body="$3" label="$4" got
        if [ "$body" = "__MISSING__" ]; then rm -f "$dir/src/meta/Version.gd"
        else printf '%s\n' "$body" > "$dir/src/meta/Version.gd"; fi
        ( cd "$dir" && VERSION_FILE="src/meta/Version.gd" check "$label" ) >/dev/null 2>&1
        got=$?
        [ "$got" -eq 0 ] && saw_ok=1 || saw_block=1
        if [ "$got" -eq "$want" ]; then
            pass=$((pass+1)); printf '  ok    %-40s exit %s\n' "$name" "$got"
        else
            fail=$((fail+1)); printf '  FAIL  %-40s exit %s (expected %s)\n' "$name" "$got" "$want"
        fi
    }

    local GOOD='extends RefCounted
class_name Version
const SEMVER := "3.33.248-alpha"'

    arm "match, label with v"        0 "$GOOD" "v3.33.248-alpha"
    arm "match, label without v"     0 "$GOOD" "3.33.248-alpha"
    arm "MISMATCH (the .247 case)"   1 "$GOOD" "v3.33.247-alpha"
    arm "no label given"             2 "$GOOD" ""
    arm "Version.gd missing"         2 "__MISSING__" "v3.33.248-alpha"
    arm "no SEMVER line"             2 'class_name Version
const OTHER := "3.33.248-alpha"' "v3.33.248-alpha"
    # A version-shaped string in a COMMENT must not satisfy the check. A loose regex would
    # match it and report agreement against a file that declares nothing.
    arm "SEMVER only in a comment"   2 '## shipped as 3.33.248-alpha last week
class_name Version' "v3.33.248-alpha"
    # ...and the same file WITH a real declaration must still read the declaration, not the
    # comment, even though the comment appears first.
    arm "comment first, real decl after" 0 '## was 3.33.111-alpha once
class_name Version
const SEMVER := "3.33.248-alpha"' "v3.33.248-alpha"

    echo
    echo "selftest: ${pass} passed, ${fail} failed"
    if [ "$saw_ok" -ne 1 ] || [ "$saw_block" -ne 1 ]; then
        echo "selftest: BROKEN — outcomes observed: pass=${saw_ok} block=${saw_block}; both are required" >&2
        return 1
    fi
    [ "$fail" -eq 0 ]
}

case "${1:-}" in
    --selftest) selftest ;;
    *)          check "${1:-}" ;;
esac
