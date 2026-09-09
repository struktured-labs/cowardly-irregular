#!/usr/bin/env bash
# Is the store actually current? Answers across ALL THREE channels, not one.
#
# WHY THIS EXISTS
# ---------------
# Every hour on 2026-09-09 I answered "is the store behind?" with:
#
#     LIVE=$(butler status … | grep '^| linux' | grep -oE 'v3\.33\.[0-9]+-alpha')
#     [ "$TAG" = "$LIVE" ] && echo CURRENT
#
# That reads ONE channel and calls it the store. During the .265-.267 window, when web was
# blocked on a RED and sat three tags behind linux for hours, this would have printed CURRENT
# every time. It also printed CURRENT mid-publish, with linux and windows on the new tag and
# web still on the old one — which is how it was finally caught.
#
# The failure direction is the bad one: it under-reports work to be done. A lane whose job is
# "notice the store is behind" had a currency check that could not see two thirds of the store.
#
# THE RULE IT ENCODES
# -------------------
# CURRENT means every channel is on the newest tag. Anything else names the laggards. A
# partial store is a distinct state from a current one and from a behind-one — mid-publish and
# blocked-channel look identical from the outside, so the tool reports the split and lets the
# reader decide.
#
# Usage:  tools/store_status.sh                      query butler and origin live
#         tools/store_status.sh <status-file> <tag>  judge a captured status against a tag
#         tools/store_status.sh --selftest
# Exit:   0 all channels current · 1 one or more behind · 2 could not determine

set -uo pipefail

CHANNELS="linux windows web"
TARGET="struktured/cowardly-irregular"

_newest_tag() {
    git ls-remote --tags origin 'refs/tags/v3.33.*' 2>/dev/null \
        | grep -v '\^{}' | awk '{print $2}' | sed 's#refs/tags/##' | sort -V | tail -1
}

judge() {
    local status_file="$1" tag="$2"

    if [ -z "$tag" ]; then
        echo "[store] BLOCKED: no tag to compare against — cannot determine currency." >&2
        return 2
    fi
    if [ ! -s "$status_file" ]; then
        echo "[store] BLOCKED: butler status produced nothing (${status_file})." >&2
        echo "        An empty status is not an up-to-date store." >&2
        return 2
    fi

    local behind="" seen=0 ch ver
    for ch in $CHANNELS; do
        # Anchored on the channel column so a version appearing anywhere else in the table —
        # butler's own upgrade banner carries version strings — cannot be mistaken for a build.
        ver="$(grep -aE "^\| *${ch} " "$status_file" | grep -oE 'v3\.33\.[0-9]+-alpha' | head -1)"
        if [ -z "$ver" ]; then
            echo "[store] BLOCKED: channel '${ch}' not found in the status output." >&2
            echo "        A missing channel is not a current one." >&2
            return 2
        fi
        seen=$((seen+1))
        if [ "$ver" = "$tag" ]; then
            printf '[store]   %-8s %s\n' "$ch" "$ver"
        else
            printf '[store]   %-8s %s   <- BEHIND (%s)\n' "$ch" "$ver" "$tag"
            behind="${behind}${behind:+ }${ch}"
        fi
    done

    if [ "$seen" -ne 3 ]; then
        echo "[store] BLOCKED: read ${seen} channels, expected 3." >&2
        return 2
    fi
    if [ -n "$behind" ]; then
        echo "[store] BEHIND at ${tag}: ${behind}"
        return 1
    fi
    echo "[store] CURRENT: all 3 channels at ${tag}"
    return 0
}

selftest() {
    local dir pass=0 fail=0 saw0=0 saw1=0 saw2=0 self
    self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    dir="$(mktemp -d "${TMPDIR:-/tmp}/storestatus.XXXXXX")"
    # shellcheck disable=SC2064
    trap "rm -rf '$dir'" EXIT

    # Fixtures carry butler's real furniture — the upgrade banner holds version-shaped strings
    # that a loose grep would happily read as a build version.
    local BANNER='+-----------------------------------+
|       New version available       |
| Current version: 15.24.0 (stable) |
+-----------------------------------+
| CHANNEL  |  UPLOAD   |    BUILD    |   VERSION   |'

    mk() { printf '%s\n%s\n' "$BANNER" "$1" > "$dir/status.txt"; }

    arm() { # name want-exit status-body tag
        local name="$1" want="$2" got
        mk "$3"
        "$self" "$dir/status.txt" "$4" >/dev/null 2>&1
        got=$?
        [ "$got" -eq 0 ] && saw0=1; [ "$got" -eq 1 ] && saw1=1; [ "$got" -eq 2 ] && saw2=1
        if [ "$got" -eq "$want" ]; then pass=$((pass+1)); printf '  ok    %-40s exit %s\n' "$name" "$got"
        else fail=$((fail+1)); printf '  FAIL  %-40s exit %s (wanted %s)\n' "$name" "$got" "$want"; fi
    }

    local ALL279='| linux    | #1 | ✓ #9 | v3.33.279-alpha+aaa |
| web      | #2 | ✓ #9 | v3.33.279-alpha+aaa |
| windows  | #3 | ✓ #9 | v3.33.279-alpha+aaa |'
    local WEBLAGS='| linux    | #1 | ✓ #9 | v3.33.279-alpha+aaa |
| web      | #2 | ✓ #9 | v3.33.276-alpha+bbb |
| windows  | #3 | ✓ #9 | v3.33.279-alpha+aaa |'
    local ONLYLINUX='| linux    | #1 | ✓ #9 | v3.33.279-alpha+aaa |'

    arm "all three current"                 0 "$ALL279"   v3.33.279-alpha
    arm "web behind (the .265-.267 case)"   1 "$WEBLAGS"  v3.33.279-alpha
    arm "all three behind"                  1 "$ALL279"   v3.33.280-alpha
    arm "a channel missing from the table"  2 "$ONLYLINUX" v3.33.279-alpha
    arm "no tag given"                      2 "$ALL279"   ""

    printf '%s\n' "$BANNER" > "$dir/status.txt"   # banner only, no channel rows
    "$self" "$dir/status.txt" v3.33.279-alpha >/dev/null 2>&1
    local g=$?; [ "$g" -eq 2 ] && saw2=1
    if [ "$g" -eq 2 ]; then pass=$((pass+1)); printf '  ok    %-40s exit %s\n' "banner only — versions must not match" "$g"
    else fail=$((fail+1)); printf '  FAIL  %-40s exit %s (wanted 2)\n' "banner only — versions must not match" "$g"; fi

    : > "$dir/status.txt"
    "$self" "$dir/status.txt" v3.33.279-alpha >/dev/null 2>&1
    g=$?; [ "$g" -eq 2 ] && saw2=1
    if [ "$g" -eq 2 ]; then pass=$((pass+1)); printf '  ok    %-40s exit %s\n' "empty status file" "$g"
    else fail=$((fail+1)); printf '  FAIL  %-40s exit %s (wanted 2)\n' "empty status file" "$g"; fi

    echo
    echo "selftest: ${pass} passed, ${fail} failed"
    if [ "$saw0" -ne 1 ] || [ "$saw1" -ne 1 ] || [ "$saw2" -ne 1 ]; then
        echo "selftest: BROKEN — outcomes seen: current=${saw0} behind=${saw1} undetermined=${saw2}; all three required" >&2
        return 1
    fi
    [ "$fail" -eq 0 ]
}

case "${1:-}" in
    --selftest) selftest ;;
    "")         tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
                butler status "$TARGET" > "$tmp" 2>&1
                judge "$tmp" "$(_newest_tag)" ;;
    *)          judge "$1" "${2:-}" ;;
esac
