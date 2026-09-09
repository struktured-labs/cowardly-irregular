#!/usr/bin/env bash
# Decide whether a godot --import run that exited non-zero may be trusted.
#
# WHY THIS IS ITS OWN SCRIPT
# --------------------------
# The decision started life inline in publish_all.sh, and I "tested" it by copying the
# condition into a probe function in my shell and running that. Four green arms — which
# proved MY COPY worked and never invoked publish_all.sh at all. A typo in the real block
# would have passed every one of them.
#
# That is cowir-battle's rule (2026-09-09) one step worse than the version they retracted
# for: "a test that calls the repaired function directly cannot tell either." Calling the
# real function at least executes the shipped code. Testing a re-implementation does not
# even do that — it verifies that I can write the same line twice.
#
# So the decision lives here, and --selftest invokes THIS SCRIPT as a subprocess with
# constructed logs. The thing under test is the thing that ships.
#
# WHAT IT DECIDES
# ---------------
# godot segfaults during editor TEARDOWN, after `reimport: end`, with the import cache fully
# built (observed on v3.33.254-alpha and v3.33.276-alpha). Refusing to publish over that
# would block on a clean crash. But the tolerance must check its own stated reason: a crash
# DURING import that still left files behind is NOT the same event, and the previous
# file-count-only guard would have accepted it while its comment said "teardown".
#
# Usage:  tools/check_import_ok.sh <import-log> <exit-code> [min-files] [imported-count]
#         tools/check_import_ok.sh --selftest
# Exit:   0 = proceed · 4 = do not build on this cache

set -uo pipefail

decide() {
    local log="$1" ec="$2" minf="${3:-100}" imported="${4:-}"

    if [ -n "$imported" ] && [ "$imported" -lt "$minf" ]; then
        echo "[import] BLOCKED: only ${imported} imported files (exit ${ec}) — cache is too small to build on." >&2
        return 4
    fi

    if [ "$ec" -eq 0 ]; then
        echo "[import] clean exit${imported:+, ${imported} files}"
        return 0
    fi

    # An unreadable or missing log is NOT evidence of a clean teardown. This is the arm the
    # file-count guard got wrong: it would have accepted a non-zero exit with no log at all.
    if [ ! -s "$log" ]; then
        echo "[import] BLOCKED: exit ${ec} and the log is missing or empty (${log})." >&2
        echo "         Absence of a crash record is not evidence the reimport finished." >&2
        return 4
    fi

    if grep -aq 'reimport: end' "$log" 2>/dev/null; then
        echo "[import] exit ${ec}, but 'reimport: end' is present — known teardown crash, tolerated${imported:+ (${imported} files)}"
        return 0
    fi

    echo "[import] BLOCKED: exit ${ec} and the log does NOT contain 'reimport: end'." >&2
    echo "         The reimport did not finish, so the cache may be partial. This is not the" >&2
    echo "         known teardown crash. See ${log}" >&2
    return 4
}

# ── self-test ────────────────────────────────────────────────────────────────
# Every arm runs THIS FILE as a subprocess. If the shipped decide() breaks, these fail;
# a re-implementation in the test could not tell.
selftest() {
    local dir pass=0 fail=0 saw0=0 saw4=0 self
    self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    dir="$(mktemp -d "${TMPDIR:-/tmp}/importok.XXXXXX")"
    # shellcheck disable=SC2064
    trap "rm -rf '$dir'" EXIT

    arm() { # name, want-exit, exit-code, log-body(or __NOLOG__), imported
        local name="$1" want="$2" ec="$3" body="$4" imported="${5:-2528}" got lf="$dir/imp.log"
        if [ "$body" = "__NOLOG__" ]; then rm -f "$lf"; else printf '%s\n' "$body" > "$lf"; fi
        "$self" "$lf" "$ec" 100 "$imported" >/dev/null 2>&1
        got=$?
        [ "$got" -eq 0 ] && saw0=1
        [ "$got" -eq 4 ] && saw4=1
        if [ "$got" -eq "$want" ]; then
            pass=$((pass+1)); printf '  ok    %-44s exit %s\n' "$name" "$got"
        else
            fail=$((fail+1)); printf '  FAIL  %-44s exit %s (wanted %s)\n' "$name" "$got" "$want"
        fi
    }

    local TEARDOWN='reimport: begin
	reimport: step 812: foo.png
reimport: end
loading_editor_layout: end
handle_crash: Program crashed with signal 11'
    local MIDIMPORT='reimport: begin
	reimport: step 812: foo.png
handle_crash: Program crashed with signal 11'

    arm "teardown crash (real .254/.276 shape)"   0 134 "$TEARDOWN"
    arm "crash DURING import"                     4 134 "$MIDIMPORT"
    arm "clean exit"                              0 0   "$TEARDOWN"
    arm "non-zero exit, log missing"              4 134 "__NOLOG__"
    arm "non-zero exit, log empty"                4 134 ""
    arm "cache too small, even with teardown log" 4 134 "$TEARDOWN" 12
    arm "cache too small, clean exit"             4 0   "$TEARDOWN" 12

    echo
    echo "selftest: ${pass} passed, ${fail} failed"
    if [ "$saw0" -ne 1 ] || [ "$saw4" -ne 1 ]; then
        echo "selftest: BROKEN — outcomes seen: proceed=${saw0} block=${saw4}; both required" >&2
        return 1
    fi
    [ "$fail" -eq 0 ]
}

case "${1:-}" in
    --selftest) selftest ;;
    *)          decide "${1:-}" "${2:-1}" "${3:-100}" "${4:-}" ;;
esac
