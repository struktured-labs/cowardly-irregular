#!/usr/bin/env bash
# Prove the 96k music masters in assets/audio/music were not modified by a build.
#
# WHY THIS EXISTS
# ---------------
# make_web_stage.sh ended its run with:
#
#     echo "[stage] masters untouched: $(find assets/audio/music -name '*.ogg' | wc -l) tracks
#            still at 96k in assets/"
#
# That COUNTS FILES and claims two things it never measures. It would print the identical
# sentence if every master had been transcoded to 48k in place, or overwritten with silence
# — which is the exact event the line exists to rule out. The count is real; "untouched" and
# "96k" are decoration attached to it.
#
# "96k" was also a literal that could not vary. Measured 2026-09-09, the 163 masters run
# 59-93 kbps VBR (a nominal 96k encode), so the printed number never described what is on
# disk. A label that cannot change when its input changes is not reporting that input.
#
# WHAT IS ACTUALLY AT STAKE
# -------------------------
# Not the web build — that ships the 48 kbps tier on purpose. DESKTOP. linux and windows
# export from the real tree, so anything that writes into assets/audio/music degrades those
# two channels, and the old line would have called it untouched. The staging script's
# `rm -f "$STAGE"/assets/audio/music/*.ogg` is one keystroke away from that directory; today
# STAGE is a hardcoded literal under `set -u` so the accident is not reachable, which is a
# property of the current source and not a guarantee about the next edit.
#
# FAILURE DIRECTION
# -----------------
# Any doubt blocks. A missing directory, an empty set, an unreadable file and a changed
# signature are all exit 4. An unmeasured bitrate reports itself as unmeasured and never
# borrows the appearance of a measurement.
#
# Usage:  tools/check_masters_untouched.sh --sig [dir]              -> "<count> <cksum> <bytes>"
#         tools/check_masters_untouched.sh --verify <dir> <sig>     -> 0 unchanged · 4 changed
#         tools/check_masters_untouched.sh --bitrate [dir]          -> measured range, or why not
#         tools/check_masters_untouched.sh --selftest
# Exit:   0 = unchanged · 4 = changed, unreadable, or empty

set -uo pipefail

DEFAULT_DIR="assets/audio/music"

# Per-file and NUL-safe. An unquoted glob here is the false zero that made
# `cat $(ls -1d "$UD/saves"/*)` read 0 bytes and cksum a tidy-looking "4294967295 0" —
# a wrong answer that looks like a right one.
_sig() {
    local dir="${1:-$DEFAULT_DIR}" n
    n="$(find "$dir" -name '*.ogg' -type f 2>/dev/null | wc -l)"
    if [ "$n" -eq 0 ]; then
        echo "0 EMPTY"
        return 0
    fi
    printf '%s ' "$n"
    find "$dir" -name '*.ogg' -type f -print0 2>/dev/null | sort -z \
        | while IFS= read -r -d '' f; do printf '%s ' "${f##*/}"; cksum < "$f"; done \
        | cksum | awk '{print $1, $2}'
}

_bitrate() {
    local dir="${1:-$DEFAULT_DIR}"
    if ! command -v ffprobe >/dev/null 2>&1; then
        echo "bitrate not measured — ffprobe absent"
        return 0
    fi
    local out
    out="$(find "$dir" -name '*.ogg' -type f -print0 2>/dev/null | sort -z \
        | while IFS= read -r -d '' f; do ffprobe -v error -show_entries format=bit_rate -of csv=p=0 "$f" 2>/dev/null; done \
        | awk 'NF && $1+0>0 {k=int($1/1000); if(n==0||k<lo)lo=k; if(k>hi)hi=k; s+=k; n++}
               END{if(n) printf "%d-%d kbps (mean %d, n=%d)", lo, hi, s/n, n; else printf "bitrate unreadable"}')"
    echo "${out:-bitrate unreadable}"
}

verify() {
    local dir="$1" want="$2" got
    if [ ! -d "$dir" ]; then
        echo "[masters] BLOCKED: ${dir} does not exist. A missing masters directory is not an" >&2
        echo "          unchanged one." >&2
        return 4
    fi
    if [ -z "$want" ]; then
        echo "[masters] BLOCKED: no baseline signature given — nothing to compare against." >&2
        return 4
    fi
    got="$(_sig "$dir")"
    case "$got" in
        "0 EMPTY")
            echo "[masters] BLOCKED: no .ogg masters found in ${dir}. An empty set has a stable" >&2
            echo "          signature and would otherwise compare equal to itself forever." >&2
            return 4 ;;
    esac
    if [ "$got" != "$want" ]; then
        echo "[masters] BLOCKED: the masters in ${dir} CHANGED during this build." >&2
        echo "          before: ${want}" >&2
        echo "          after:  ${got}" >&2
        echo "          Desktop exports read this directory. Do not publish from this tree." >&2
        return 4
    fi
    echo "[masters] verified unchanged: ${got} · $(_bitrate "$dir")"
    return 0
}

# ── self-test ────────────────────────────────────────────────────────────────
# Every arm invokes THIS FILE as a subprocess against a constructed directory. The point of
# the extraction is that the thing under test is the thing make_web_stage.sh calls — a copy
# of the comparison re-typed into a probe would pass while the shipped line was broken, which
# is how the import tolerance got four green arms that never ran it.
selftest() {
    local dir pass=0 fail=0 saw0=0 saw4=0 self
    self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    dir="$(mktemp -d "${TMPDIR:-/tmp}/masters.XXXXXX")"
    # shellcheck disable=SC2064
    trap "rm -rf '$dir'" EXIT
    mkdir -p "$dir/music"

    printf 'OggS-pretend-master-one\n'   > "$dir/music/a.ogg"
    printf 'OggS-pretend-master-two\n'   > "$dir/music/b.ogg"
    printf 'OggS-pretend-master-three\n' > "$dir/music/c.ogg"
    local BASE; BASE="$("$self" --sig "$dir/music")"

    arm() { # name, want-exit, sig-to-compare
        local name="$1" want="$2" sig="$3" got
        "$self" --verify "$dir/music" "$sig" >/dev/null 2>&1
        got=$?
        [ "$got" -eq 0 ] && saw0=1
        [ "$got" -eq 4 ] && saw4=1
        if [ "$got" -eq "$want" ]; then pass=$((pass+1)); printf '  ok    %-46s exit %s\n' "$name" "$got"
        else fail=$((fail+1)); printf '  FAIL  %-46s exit %s (wanted %s)\n' "$name" "$got" "$want"; fi
    }

    arm "untouched"                                0 "$BASE"

    # The case the old line could not see: same count, same names, DIFFERENT CONTENT.
    printf 'OggS-transcoded-to-48k\n' > "$dir/music/b.ogg"
    arm "one master transcoded in place"           4 "$BASE"
    printf 'OggS-pretend-master-two\n' > "$dir/music/b.ogg"
    arm "restored"                                 0 "$BASE"

    mv "$dir/music/c.ogg" "$dir/music/c.ogg.bak"
    arm "one master deleted"                       4 "$BASE"
    mv "$dir/music/c.ogg.bak" "$dir/music/c.ogg"

    printf 'OggS-stray\n' > "$dir/music/d.ogg"
    arm "a master added"                           4 "$BASE"
    rm -f "$dir/music/d.ogg"

    # A rename with identical bytes must still trip: the count matches and the content
    # matches, but the export packs files BY NAME.
    mv "$dir/music/a.ogg" "$dir/music/z.ogg"
    arm "a master renamed, bytes identical"        4 "$BASE"
    mv "$dir/music/z.ogg" "$dir/music/a.ogg"

    arm "no baseline given"                        4 ""
    rm -f "$dir"/music/*.ogg
    arm "masters directory emptied"                4 "$BASE"
    printf 'OggS-pretend-master-one\n'   > "$dir/music/a.ogg"
    printf 'OggS-pretend-master-two\n'   > "$dir/music/b.ogg"
    printf 'OggS-pretend-master-three\n' > "$dir/music/c.ogg"

    "$self" --verify "$dir/nope" "$BASE" >/dev/null 2>&1
    local g=$?; [ "$g" -eq 4 ] && saw4=1
    if [ "$g" -eq 4 ]; then pass=$((pass+1)); printf '  ok    %-46s exit %s\n' "directory missing entirely" "$g"
    else fail=$((fail+1)); printf '  FAIL  %-46s exit %s (wanted 4)\n' "directory missing entirely" "$g"; fi

    # LABEL ARM. The verdict text must not assert a bitrate it did not measure. These
    # fixtures are not real oggs, so ffprobe cannot read them — and the line must SAY that
    # rather than print a number-shaped reassurance.
    local out; out="$("$self" --verify "$dir/music" "$BASE" 2>&1)"
    if printf '%s' "$out" | grep -q '96k'; then
        fail=$((fail+1)); printf '  FAIL  %-46s asserts 96k it never measured\n' "label: no unmeasured bitrate"
    else
        pass=$((pass+1)); printf '  ok    %-46s claims no bitrate it lacks\n' "label: no unmeasured bitrate"
    fi
    if printf '%s' "$out" | grep -qE 'unreadable|not measured|kbps'; then
        pass=$((pass+1)); printf '  ok    %-46s states its own measurability\n' "label: bitrate provenance"
    else
        fail=$((fail+1)); printf '  FAIL  %-46s silent about the bitrate\n' "label: bitrate provenance"
    fi
    # ...and that label predicate must be able to FAIL, or it is a vacuous pass.
    local OLDMSG="[stage] masters untouched: 163 tracks still at 96k in assets/"
    if printf '%s' "$OLDMSG" | grep -q '96k'; then
        pass=$((pass+1)); printf '  ok    %-46s rejects the OLD wording\n' "label control fires"
    else
        fail=$((fail+1)); printf '  FAIL  %-46s passed the OLD wording\n' "label control fires"
    fi

    # ── ABSENCE ARM ──────────────────────────────────────────────────────────
    # THE LINE THIS SCRIPT REPLACED CAME BACK, AND EVERY CHECK I RAN WAS BLIND TO IT.
    #
    # make_web_stage.sh used to print "masters untouched: N tracks still at 96k" — a file
    # count asserting a bitrate it never measured. This script replaced it. Two branches then
    # collided on that exact line (one REPLACING it, one INSERTING before it); I resolved the
    # conflict, verified `bash -n`, verified both guards present and ordered, ran both
    # selftests — four checks, all green — and the deleted echo came back from the other side
    # of the hunk and shipped to main. Every web build printed "still at 96k" directly above
    # this script measuring 59-93 kbps.
    #
    # I asserted the PRESENCE of what I added and never the ABSENCE of what I removed. A
    # deletion leaves no positive artifact to check for, so it needs an arm of its own or the
    # next merge resurrects it silently. This is that arm.
    local stage_sh; stage_sh="$(cd "$(dirname "$0")" && pwd)/make_web_stage.sh"
    if [ -f "$stage_sh" ]; then
        local stale_n; stale_n="$(grep -c 'still at 96k' "$stage_sh" 2>/dev/null || true)"
        if [ "${stale_n:-0}" -eq 0 ]; then
            pass=$((pass+1)); printf '  ok    %-50s absent\n' "the replaced 96k claim stays deleted"
        else
            fail=$((fail+1)); printf '  FAIL  %-50s %s occurrence(s) — a merge resurrected it\n' "the replaced 96k claim is BACK" "$stale_n"
        fi
        # ...and the arm must be able to fail, or it is the vacuous pass it exists to prevent.
        local probe; probe="$(mktemp "${TMPDIR:-/tmp}/staleprobe.XXXXXX")"
        printf 'echo "[stage] masters untouched: 163 tracks still at 96k in assets/"\n' > "$probe"
        if [ "$(grep -c 'still at 96k' "$probe")" -eq 1 ]; then
            pass=$((pass+1)); printf '  ok    %-50s fires on a planted copy\n' "absence arm CONTROL"
        else
            fail=$((fail+1)); printf '  FAIL  %-50s blind to a planted copy\n' "absence arm CONTROL"
        fi
        rm -f "$probe"
    else
        fail=$((fail+1)); printf '  FAIL  %-50s cannot check\n' "make_web_stage.sh not found beside this script"
    fi

    echo
    echo "selftest: ${pass} passed, ${fail} failed"
    if [ "$saw0" -ne 1 ] || [ "$saw4" -ne 1 ]; then
        echo "selftest: BROKEN — outcomes seen: unchanged=${saw0} changed=${saw4}; both required" >&2
        return 1
    fi
    [ "$fail" -eq 0 ]
}

case "${1:-}" in
    --selftest) selftest ;;
    --sig)      _sig "${2:-$DEFAULT_DIR}" ;;
    --bitrate)  _bitrate "${2:-$DEFAULT_DIR}" ;;
    --verify)   verify "${2:-$DEFAULT_DIR}" "${3:-}" ;;
    *)          echo "usage: $0 --sig|--bitrate|--verify <dir> <sig>|--selftest" >&2; exit 2 ;;
esac
