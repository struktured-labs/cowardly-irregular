#!/usr/bin/env bash
# Arms for report_split_store.sh, driven as a SUBPROCESS so the thing under test is the thing
# that ships — check_import_ok.sh's header argues this and it is the same mistake to avoid:
# a re-implemented copy in a probe proves the copy works and never executes the shipped file.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
TOOL=./tools/report_split_store.sh
pass=0; fail=0

# arm <name> <want_ec> <want_substring> <must_NOT_contain> [args...]
arm() {
    local name="$1" want_ec="$2" want="$3" nope="$4"; shift 4
    local out ec
    out=$("$TOOL" "$@" 2>&1); ec=$?
    local ok=1
    [ "$ec" = "$want_ec" ] || ok=0
    printf '%s' "$out" | command grep -qF "$want" || ok=0
    if [ -n "$nope" ] && printf '%s' "$out" | command grep -qF "$nope"; then ok=0; fi
    if [ "$ok" = 1 ]; then
        pass=$(( pass + 1 )); printf '  ok    %-28s EC=%s\n' "$name" "$ec"
    else
        fail=$(( fail + 1 ))
        printf '  FAIL  %-28s EC=%s (want %s) want:%s notwant:%s\n' "$name" "$ec" "$want_ec" "$want" "$nope"
        printf '%s\n' "$out" | sed 's/^/          | /' | head -6
    fi
}

echo "[selftest] report_split_store.sh"

# Nothing live => NOT a split. The vacuity arm: an empty channel set printing a SPLIT warning
# would be this lane's own "0 tools scanned beside a PASS" bug.
arm nothing-published      0 "nothing was published" "INCONSISTENT" v3.33.999-alpha ""
arm whitespace-only        0 "nothing was published" "INCONSISTENT" v3.33.999-alpha "   "

# Something live => a split, and it must NAME what is live.
arm one-channel-live       0 "live at v3.33.999-alpha: linux" "nothing was published" v3.33.999-alpha "linux"
arm two-channels-live      0 "live at v3.33.999-alpha: linux windows" "" v3.33.999-alpha "linux windows"

# The label must VARY with the input. A verdict broader than its code is not reporting —
# so prove the one-channel and two-channel messages are not the same string.
_one=$("$TOOL" v3.33.999-alpha "linux" 2>&1)
_two=$("$TOOL" v3.33.999-alpha "linux windows" 2>&1)
if [ "$_one" != "$_two" ]; then
    pass=$(( pass + 1 )); printf '  ok    %-28s the message tracks the channel set\n' "label-varies"
else
    fail=$(( fail + 1 )); printf '  FAIL  %-28s identical output for different inputs\n' "label-varies"
fi

# The tag must reach the output too, or "live at <tag>" is decoration.
arm tag-is-reported        0 "live at v3.33.111-alpha" "" v3.33.111-alpha "web"

# Usage errors BLOCK (2). A reporter that silently accepts a missing argument would print a
# split with no tag in it.
arm missing-channels-arg   2 "usage:" "" v3.33.999-alpha
arm no-args                2 "usage:" ""

echo "[selftest] $(( pass + fail )) arm(s), $fail failed"
[ "$fail" -eq 0 ]
