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
        # SAY ONLY WHAT WAS CHECKED. The test is an ORDERING test: the reimport reached its end
        # marker before the process died. That makes the CACHE usable, which is the only thing
        # this script is entitled to conclude. It does NOT identify which crash followed, and
        # the previous wording ("known teardown crash") asserted exactly that — an identity
        # claim resting on ordering alone. A constructed log with `reimport: end`, then a failed
        # export template, a null-instance script error and SIGABRT was reported as the known
        # benign teardown and tolerated, exit 0. See the foreign-crash selftest arm below.
        echo "[import] exit ${ec} AFTER 'reimport: end' — reimport completed, so the cache is usable."
        echo "[import]   The crash that followed is UNIDENTIFIED; this is not a claim that it was"
        echo "[import]   the known teardown segfault. Nothing downstream of the cache is vouched for."
        echo "[import]   ${imported:+${imported} files · }see ${log}"
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

    # ── LABEL CONTROL ─────────────────────────────────────────────────────────
    # The arms above are NEGATIVE controls: each plants an input that should make the
    # EXPRESSION fail, and checks it does. They cannot catch a message that claims more than
    # the expression establishes, because on every one of them the expression works. That is
    # exactly how "known teardown crash" survived: `reimport: end` really was present, the
    # cache really was built, exit 0 really was right — and the sentence still asserted an
    # identity nothing had tested.
    #
    # A LABEL control is the other shape: an input that SATISFIES the expression and VIOLATES
    # the label. FOREIGN below is a crash that is emphatically NOT the known teardown segfault
    # — a failed export template, a null-instance script error, SIGABRT — occurring after a
    # completed reimport. The verdict must stay 0 (the cache IS usable; that part was never
    # wrong) while the WORDING must not identify it.
    local FOREIGN='reimport: begin
reimport: end
EXPORT: beginning web export
ERROR: Failed to load export template
SCRIPT ERROR: Invalid call on null instance
handle_crash: Program crashed with signal 6'

    arm "foreign crash after reimport: end"       0 134 "$FOREIGN"

    # Assert on the TEXT, not the exit code, for both crash shapes.
    local lf="$dir/imp.log" out body name
    for name in TEARDOWN FOREIGN; do
        eval "body=\$$name"
        printf '%s\n' "$body" > "$lf"
        out="$("$self" "$lf" 134 100 2528 2>&1)"
        if printf '%s' "$out" | grep -q 'UNIDENTIFIED' && ! printf '%s' "$out" | grep -qi 'known teardown crash'; then
            pass=$((pass+1)); printf '  ok    %-44s names no crash\n' "label: ${name} verdict"
        else
            fail=$((fail+1)); printf '  FAIL  %-44s claims to identify the crash\n' "label: ${name} verdict"
        fi
    done

    # ...and the label assertion must be able to FAIL, or it is the vacuous pass it exists to
    # prevent. Run the exact predicate over the wording this fix replaced.
    local OLDMSG="[import] exit 134, but 'reimport: end' is present — known teardown crash, tolerated (2528 files)"
    if printf '%s' "$OLDMSG" | grep -q 'UNIDENTIFIED' && ! printf '%s' "$OLDMSG" | grep -qi 'known teardown crash'; then
        fail=$((fail+1)); printf '  FAIL  %-44s predicate passed the OLD wording\n' "label control fires"
    else
        pass=$((pass+1)); printf '  ok    %-44s rejects the OLD wording\n' "label control fires"
    fi

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
