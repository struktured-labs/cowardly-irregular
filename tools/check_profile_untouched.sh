#!/usr/bin/env bash
# Prove the combat smoke did not write into struktured's REAL godot profile.
#
# WHY THIS EXISTS
# ---------------
# deploy_desktop.sh gate 3b runs the exported binary FOR REAL — a full battle, under
# xvfb, with $HOME redirected at a throwaway directory so `user://` resolves inside the
# sandbox. It is the only gate allowed to do more than boot, and the entire licence for that
# is the isolation. The gate verified it like this:
#
#     REAL_N_BEFORE=$(find "$USERDATA" -type f | wc -l)
#     ... run the game ...
#     REAL_N_AFTER=$(find "$USERDATA" -type f | wc -l)
#     [ "$REAL_N_BEFORE" -ne "$REAL_N_AFTER" ] && BLOCKED
#     echo "... profile untouched (${REAL_N_BEFORE} files)"
#
# A FILE COUNT. It cannot see a save OVERWRITTEN IN PLACE — the case that matters most,
# because that is what a partially-failed HOME redirection looks like: the game finds an
# existing profile and writes slot files that are already there. Count unchanged, gate green,
# "profile untouched" printed over the top of it, publish proceeds.
#
# This is the same defect as the "masters untouched: N tracks still at 96k" line in
# make_web_stage.sh, which also counted files and claimed content. The stake here is higher:
# that one guarded audio masters, this one guards his save data.
#
# WHAT IT MEASURES INSTEAD
# ------------------------
# A per-file checksum over the whole profile, NUL-safe. Any modification, addition, removal or
# rename changes the signature. A count cannot distinguish those; a signature does not have to.
#
# TELLING "HE WAS PLAYING" FROM "ISOLATION LEAKED"
# ------------------------------------------------
# Both look identical in the real profile: it changed. The discriminator is the SANDBOX. If
# HOME redirection worked, the game's writes are in there; a smoke that ran a whole battle and
# left an EMPTY sandbox did not have a working redirect. So --verify takes the sandbox too and
# reports both, because a human reading a RED needs to know which of the two it is and the
# numbers answer it in one line.
#
# Either way this BLOCKS. Blocking a publish because he happened to be playing costs an hour;
# not blocking because a count could not see an overwrite costs his save file.
#
# Usage:  tools/check_profile_untouched.sh --sig <profile-dir>
#         tools/check_profile_untouched.sh --verify <profile-dir> <sig> [sandbox-dir]
#         tools/check_profile_untouched.sh --selftest
# Exit:   0 unchanged · 3 changed / unreadable (same code gate 3b already uses)

set -uo pipefail

# Per-file and NUL-safe. An unquoted glob here is the false zero that made
# `cat $(ls -1d "$UD/saves"/*)` read 0 bytes and cksum a tidy-looking "4294967295 0" — his
# profile path contains a space ("Cowardly Irregular"), so this is not hypothetical.
# `logs/` IS EXCLUDED, AND THE REASON IS THE SAME PROPERTY THIS FILE EXISTS FOR.
#
# Godot rotates user://logs/ with a fixed cap — measured on his profile: exactly 5 files, a
# new one written on each run and the oldest deleted. So the COUNT never moves while the
# CONTENT changes every time any godot process touches the real profile.
#
# That single property defeats both instruments, in opposite directions:
#   a COUNT check is BLIND to it   (5 -> 5, "profile untouched", and it would be blind to a
#                                   save overwrite for exactly the same reason)
#   a naive SIGNATURE check is NOISY on it (reds on routine log churn, every publish)
#
# Discovered by running the real gate chain rather than reasoning about it: my pre-chain
# baseline and the gate's own baseline disagreed, and the single differing file was a rotated
# log. A whole-profile signature would have shipped a gate that blocks constantly, which gets
# a guard disabled and is worse than the guard it replaced.
#
# Excluding logs/ is not a loosening. Logs are godot's own churn, regenerable and worthless.
# What this gate protects is saves/ and the rest of the profile, and against THAT the
# signature is exact: measured 1864063109 16959 for both gate 0b's snapshot and his live
# directory across a full chain run.
_EXCLUDE='*/logs/*'

_sig() {
    local dir="$1" n
    n="$(find "$dir" -type f -not -path "$_EXCLUDE" 2>/dev/null | wc -l)"
    if [ "$n" -eq 0 ]; then
        echo "0 EMPTY"
        return 0
    fi
    printf '%s ' "$n"
    find "$dir" -type f -not -path "$_EXCLUDE" -print0 2>/dev/null | sort -z \
        | while IFS= read -r -d '' f; do printf '%s ' "${f#"$dir"/}"; cksum < "$f"; done \
        | cksum | awk '{print $1, $2}'
}

_changed_files() {
    local dir="$1" limit="${2:-8}"
    find "$dir" -type f -newermt '-2 hours' 2>/dev/null | head -"$limit"
}

verify() {
    local dir="$1" want="$2" sandbox="${3:-}" got

    if [ ! -d "$dir" ]; then
        echo "[profile] BLOCKED: ${dir} does not exist. A missing profile is not an unchanged one." >&2
        return 3
    fi
    if [ -z "$want" ]; then
        echo "[profile] BLOCKED: no baseline signature — nothing to compare against." >&2
        return 3
    fi
    got="$(_sig "$dir")"
    if [ "$got" = "0 EMPTY" ]; then
        echo "[profile] BLOCKED: his profile now holds no files at all." >&2
        return 3
    fi
    if [ "$got" = "$want" ]; then
        echo "[profile] verified unchanged: ${got}"
        return 0
    fi

    echo "[profile] BLOCKED: struktured's REAL profile CHANGED during the combat smoke." >&2
    echo "          before: ${want}" >&2
    echo "          after:  ${got}" >&2
    if [ -n "$sandbox" ] && [ -d "$sandbox" ]; then
        local sn; sn="$(find "$sandbox" -type f 2>/dev/null | wc -l)"
        echo "          sandbox holds ${sn} file(s)." >&2
        if [ "$sn" -eq 0 ]; then
            echo "          ⛔ THE SANDBOX IS EMPTY — a battle ran and wrote nothing there, so HOME" >&2
            echo "             redirection did NOT work. Treat this as a real leak." >&2
        else
            echo "          The redirect appears to have worked (writes landed in the sandbox), so this" >&2
            echo "             is more likely struktured playing during the deploy than a leak. Confirm" >&2
            echo "             before publishing anyway — 'more likely' is not 'verified'." >&2
        fi
    fi
    echo "          recently modified in his profile:" >&2
    _changed_files "$dir" | sed 's/^/            /' >&2
    return 3
}

# ── self-test ────────────────────────────────────────────────────────────────
# Every arm runs THIS FILE as a subprocess against constructed directories. Never against his
# real profile: a test that writes into the thing it protects is not a test.
selftest() {
    local dir pass=0 fail=0 saw0=0 saw3=0 self
    self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    dir="$(mktemp -d "${TMPDIR:-/tmp}/profile.XXXXXX")"
    # shellcheck disable=SC2064
    trap "rm -rf '$dir'" EXIT
    # The space is deliberate: his real path is "Cowardly Irregular", and the bug this file
    # cites is an unquoted glob splitting on exactly that.
    local P="$dir/Cowardly Irregular"
    mkdir -p "$P/saves" "$P/screenshots" "$dir/sandbox"

    printf 'slot one\n'   > "$P/saves/slot1.json"
    printf 'slot two\n'   > "$P/saves/slot2.json"
    printf 'PNGDATA\n'    > "$P/screenshots/a.png"
    local BASE; BASE="$("$self" --sig "$P")"

    arm() { # name want-exit sig [sandbox]
        local name="$1" want="$2" got
        "$self" --verify "$P" "$3" "${4:-}" >/dev/null 2>&1
        got=$?
        [ "$got" -eq 0 ] && saw0=1
        [ "$got" -eq 3 ] && saw3=1
        if [ "$got" -eq "$want" ]; then pass=$((pass+1)); printf '  ok    %-50s exit %s\n' "$name" "$got"
        else fail=$((fail+1)); printf '  FAIL  %-50s exit %s (wanted %s)\n' "$name" "$got" "$want"; fi
    }

    arm "untouched"                                        0 "$BASE"

    # THE CASE THE COUNT COULD NOT SEE: same file count, same names, different bytes.
    printf 'OVERWRITTEN BY THE SMOKE\n' > "$P/saves/slot1.json"
    arm "a save OVERWRITTEN IN PLACE (count unchanged)"    3 "$BASE"
    printf 'slot one\n' > "$P/saves/slot1.json"
    arm "restored"                                         0 "$BASE"

    printf 'new\n' > "$P/saves/slot3.json"
    arm "a save added"                                     3 "$BASE"
    rm -f "$P/saves/slot3.json"

    mv "$P/saves/slot2.json" "$P/saves/slot9.json"
    arm "a save renamed, bytes identical"                  3 "$BASE"
    mv "$P/saves/slot9.json" "$P/saves/slot2.json"

    rm -f "$P/screenshots/a.png"
    arm "a file deleted"                                   3 "$BASE"
    printf 'PNGDATA\n' > "$P/screenshots/a.png"

    # LOG CHURN MUST NOT RED. This is the arm that keeps the gate usable: godot rewrites
    # user://logs/ on every run with a fixed file cap, so if this tripped, the gate would
    # block every publish and be disabled within a day.
    mkdir -p "$P/logs"
    printf 'run one\n' > "$P/logs/godot.log"
    local BASE_L; BASE_L="$("$self" --sig "$P")"
    printf 'run two, different bytes, same count\n' > "$P/logs/godot.log"
    arm "a rotated log changed (must NOT red)"             0 "$BASE_L"
    printf 'a whole new log\n' > "$P/logs/godot2026.log"
    arm "a log ADDED (must NOT red)"                       0 "$BASE_L"
    # ...and the exclusion must not hide a real save change happening at the same time.
    printf 'OVERWRITTEN WHILE LOGS ALSO CHURNED\n' > "$P/saves/slot1.json"
    arm "save overwritten WHILE logs churn (must red)"     3 "$BASE_L"
    printf 'slot one\n' > "$P/saves/slot1.json"
    rm -rf "$P/logs"

    arm "no baseline given"                                3 ""
    "$self" --verify "$dir/nope" "$BASE" >/dev/null 2>&1
    local g=$?; [ "$g" -eq 3 ] && saw3=1
    if [ "$g" -eq 3 ]; then pass=$((pass+1)); printf '  ok    %-50s exit %s\n' "profile directory missing" "$g"
    else fail=$((fail+1)); printf '  FAIL  %-50s exit %s (wanted 3)\n' "profile directory missing" "$g"; fi

    # The leak-vs-playing discriminator must actually say different things.
    printf 'OVERWRITTEN\n' > "$P/saves/slot1.json"
    local empty_out full_out
    empty_out="$("$self" --verify "$P" "$BASE" "$dir/sandbox" 2>&1)"
    printf 'sandbox wrote this\n' > "$dir/sandbox/user_data.bin"
    full_out="$("$self" --verify "$P" "$BASE" "$dir/sandbox" 2>&1)"
    printf 'slot one\n' > "$P/saves/slot1.json"

    if printf '%s' "$empty_out" | grep -q 'SANDBOX IS EMPTY'; then
        pass=$((pass+1)); printf '  ok    %-50s\n' "empty sandbox -> named as a real leak"
    else fail=$((fail+1)); printf '  FAIL  %-50s\n' "empty sandbox -> not identified as a leak"; fi
    if printf '%s' "$full_out" | grep -q 'more likely struktured playing'; then
        pass=$((pass+1)); printf '  ok    %-50s\n' "written sandbox -> named as probably playing"
    else fail=$((fail+1)); printf '  FAIL  %-50s\n' "written sandbox -> not distinguished"; fi
    # ...and the two messages must not be the same message.
    if [ "$empty_out" != "$full_out" ]; then
        pass=$((pass+1)); printf '  ok    %-50s\n' "the two diagnoses differ"
    else fail=$((fail+1)); printf '  FAIL  %-50s (a verdict that cannot vary)\n' "the two diagnoses are identical"; fi

    echo
    echo "selftest: ${pass} passed, ${fail} failed"
    if [ "$saw0" -ne 1 ] || [ "$saw3" -ne 1 ]; then
        echo "selftest: BROKEN — outcomes seen: unchanged=${saw0} changed=${saw3}; both required" >&2
        return 1
    fi
    [ "$fail" -eq 0 ]
}

case "${1:-}" in
    --selftest) selftest ;;
    --sig)      _sig "${2:-}" ;;
    --verify)   verify "${2:-}" "${3:-}" "${4:-}" ;;
    *)          echo "usage: $0 --sig <dir> | --verify <dir> <sig> [sandbox] | --selftest" >&2; exit 2 ;;
esac
