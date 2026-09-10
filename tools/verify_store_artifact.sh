#!/usr/bin/env bash
# Read the published build BACK from itch and compare it to what we built.
#
# WHY THIS EXISTS
# ---------------
# Every verification this lane performs stops at the moment of upload:
#
#   the gates      test the LOCAL artifact  (suite, export, boot smoke, combat, web smoke)
#   butler push    uploads it
#   butler status  reports a VERSION STRING and a build number
#
# Nothing has ever looked at what the store actually SERVES. `butler status` saying
# `v3.33.293-alpha+317f2ec9` is butler's record of what it was asked to push — it is not a
# statement about the bytes a player downloads. Between our smoke and the player there is an
# upload, an ignore-filter, a build pipeline on itch's side and a CDN, and this lane has
# published 36 times without reading back across any of it.
#
# THE FAILURE IT CATCHES, and it is not upload corruption. Butler checksums its own transfers,
# so a corrupted push is unlikely. The realistic case is a MISSING FILE: an `--ignore` pattern,
# a stray `.itchignore`, or a partially-failed push that drops `index.wasm` while the version
# string still reports correctly. The web smoke cannot see it — the smoke runs against the
# LOCAL directory, before butler decides what to send. The game would simply not load, and
# every gate we own would be green.
#
# FIRST RUN, 2026-09-10, against ALL THREE live channels at v3.33.293-alpha:
#   web      9 files, 206.83 MiB · set identical · all 9 cksums identical
#   linux    1 file,  327,626,960 B · cksum 665032545  identical
#   windows  1 file,  355,459,072 B · cksum 2465118453 identical
#   The store serves exactly what we built — measured rather than assumed, for the first time
#   in 36 publishes. Desktop is one self-contained binary per channel (the pck is embedded),
#   so the SET comparison there is trivial and the checksum is doing all the work.
#
#   CONTROL on the real fetch path, not just on compare(): fetching the WINDOWS channel and
#   comparing it against the LINUX build reports both directions — .x86_64 in local not on
#   store, .exe on store not in local — exit 5. The selftest exercises compare() only, so
#   without this the fetch half had never been shown capable of failing.
#
# COST, stated because it is why this is NOT wired into every publish:
#   a full fetch is ~207 MiB for web and ~312 MiB for a desktop channel. At an hourly publish
#   cadence that is real bandwidth for a check whose expected answer is "identical". Run it
#   after a publish that mattered, after any butler or ignore-pattern change, and when a
#   player reports a build that will not load.
#
# WHAT IS TESTED AND WHAT IS NOT
#   compare()  — the comparison logic. Exercised by --selftest, both directions.
#   fetch      — a thin wrapper over `butler fetch`. NOT exercised by the selftest: it needs
#                the network and struktured's credentials, and a test that needs both is a
#                test that gets skipped. The split is deliberate so the untested part stays
#                as small as possible.
#
# Usage:  tools/verify_store_artifact.sh <channel> <local-build-dir>
#         tools/verify_store_artifact.sh --compare <dir-a> <dir-b>
#         tools/verify_store_artifact.sh --selftest
# Exit:   0 identical · 5 the store differs from what we built · 2 could not evaluate

set -uo pipefail

TARGET="struktured/cowardly-irregular"

# Per-file and NUL-safe, and the SET is compared before the contents: a file present on one
# side only has no checksum to disagree about, so a contents-only comparison would skip it
# silently — the shape that made "masters untouched" blind to an overwrite.
_manifest() {
    local dir="$1"
    find "$dir" -type f -print0 2>/dev/null | sort -z \
        | while IFS= read -r -d '' f; do printf '%s ' "${f#"$dir"/}"; cksum < "$f" | awk '{print $1}'; done
}

compare() {
    local a="$1" b="$2" alabel="${3:-local}" blabel="${4:-store}"
    if [ ! -d "$a" ]; then echo "[store-verify] BLOCKED: ${alabel} dir ${a} does not exist." >&2; return 2; fi
    if [ ! -d "$b" ]; then echo "[store-verify] BLOCKED: ${blabel} dir ${b} does not exist." >&2; return 2; fi

    local ma mb na nb
    ma="$(_manifest "$a")"; mb="$(_manifest "$b")"
    na="$(printf '%s' "$ma" | grep -c . || true)"; nb="$(printf '%s' "$mb" | grep -c . || true)"
    if [ "$na" -eq 0 ] || [ "$nb" -eq 0 ]; then
        echo "[store-verify] BLOCKED: ${alabel} has ${na} file(s), ${blabel} has ${nb}." >&2
        echo "               An empty side is not a matching one." >&2
        return 2
    fi

    # REAL FILES, NOT PROCESS SUBSTITUTION. uutils `comm` issues a single read() on a
    # non-seekable fd and does not loop to EOF, so `comm -23 <(...) <(...)` silently
    # truncates — worst case reporting ZERO differences for lists that genuinely differ,
    # which reads as a clean audit. This is in my own notes and I wrote the forbidden form
    # anyway; the selftest could never have caught it because 3-file fixtures are far below
    # the truncation point. Sorted real files, and grep -Fxv rather than comm.
    local tmpd; tmpd="$(mktemp -d "${TMPDIR:-/tmp}/svcmp.XXXXXX")"
    printf '%s\n' "$ma" | awk 'NF{print $1}' | sort > "$tmpd/a.names"
    printf '%s\n' "$mb" | awk 'NF{print $1}' | sort > "$tmpd/b.names"
    local only_a only_b diff_files=0
    only_a="$(grep -Fxv -f "$tmpd/b.names" "$tmpd/a.names" | tr '\n' ' ')"
    only_b="$(grep -Fxv -f "$tmpd/a.names" "$tmpd/b.names" | tr '\n' ' ')"
    rm -rf "$tmpd"

    local rc=0
    if [ -n "${only_a// }" ]; then
        echo "[store-verify] BLOCKED: in ${alabel} but NOT ${blabel}: ${only_a}" >&2
        echo "               A file we built that the store does not serve is the shape a" >&2
        echo "               dropped index.wasm takes, and the version string still reads right." >&2
        rc=5
    fi
    if [ -n "${only_b// }" ]; then
        echo "[store-verify] BLOCKED: on ${blabel} but NOT in ${alabel}: ${only_b}" >&2
        rc=5
    fi

    # contents, for the files present on both sides
    while read -r name sum; do
        [ -z "$name" ] && continue
        local other; other="$(printf '%s\n' "$mb" | awk -v n="$name" '$1==n {print $2}')"
        if [ -n "$other" ] && [ "$other" != "$sum" ]; then
            echo "[store-verify] BLOCKED: ${name} differs — ${alabel}=${sum} ${blabel}=${other}" >&2
            diff_files=$((diff_files+1)); rc=5
        fi
    done <<< "$ma"

    if [ "$rc" -eq 0 ]; then
        echo "[store-verify] identical: ${na} file(s), every checksum matches"
        echo "[store-verify]   the store serves exactly what we built"
    elif [ "$diff_files" -gt 0 ]; then
        echo "[store-verify] ${diff_files} file(s) differ in content" >&2
    fi
    # Deliberately silent when rc!=0 and diff_files==0. The cross-channel control printed
    # "0 file(s) differ in content" underneath two BLOCKED set-difference lines — accurate
    # (no file was present on both sides to disagree) and readable as reassurance by anyone
    # skimming for a number. A zero next to a failure is the wrong thing to volunteer.
    return $rc
}

fetch_and_compare() {
    local channel="$1" local_dir="$2"
    case "$channel" in
        web|linux|windows) : ;;
        *) echo "[store-verify] BLOCKED: unknown channel '${channel}' (web|linux|windows)" >&2; return 2 ;;
    esac
    command -v butler >/dev/null || { echo "[store-verify] BLOCKED: butler not on PATH." >&2; return 2; }
    [ -d "$local_dir" ] || { echo "[store-verify] BLOCKED: local build dir ${local_dir} not found." >&2; return 2; }

    local out; out="$(mktemp -d "${TMPDIR:-/tmp}/storeverify.XXXXXX")"
    # shellcheck disable=SC2064
    trap "rm -rf '$out'" RETURN
    echo "[store-verify] fetching ${TARGET}:${channel} (this downloads the whole build)"
    if ! butler fetch "${TARGET}:${channel}" "$out" >/dev/null 2>&1; then
        echo "[store-verify] BLOCKED: butler fetch failed for ${channel}. A failed read is not" >&2
        echo "               evidence the store is correct." >&2
        return 2
    fi
    compare "$local_dir" "$out" "local" "store"
}

# ── self-test ────────────────────────────────────────────────────────────────
# Exercises compare() only — see the header on why fetch is out of scope. Both outcomes are
# required, and the arms cover the case a contents-only comparison would miss.
selftest() {
    local d pass=0 fail=0 saw0=0 saw5=0 self
    self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    d="$(mktemp -d "${TMPDIR:-/tmp}/sv.XXXXXX")"
    # shellcheck disable=SC2064
    trap "rm -rf '$d'" EXIT
    mkdir -p "$d/a" "$d/b"
    for n in index.html index.wasm index.pck; do
        printf 'content of %s\n' "$n" > "$d/a/$n"
        printf 'content of %s\n' "$n" > "$d/b/$n"
    done

    arm() { # name want
        local name="$1" want="$2" got
        "$self" --compare "$d/a" "$d/b" >/dev/null 2>&1; got=$?
        [ "$got" -eq 0 ] && saw0=1; [ "$got" -eq 5 ] && saw5=1
        if [ "$got" -eq "$want" ]; then pass=$((pass+1)); printf '  ok    %-46s exit %s\n' "$name" "$got"
        else fail=$((fail+1)); printf '  FAIL  %-46s exit %s (wanted %s)\n' "$name" "$got" "$want"; fi
    }

    arm "identical builds" 0

    printf 'TAMPERED\n' > "$d/b/index.pck"
    arm "a file differs in content" 5
    printf 'content of index.pck\n' > "$d/b/index.pck"
    arm "restored" 0

    # THE CASE A CONTENTS-ONLY COMPARISON MISSES: a file the store does not serve has no
    # checksum to disagree with, so it vanishes from a naive loop instead of failing.
    rm -f "$d/b/index.wasm"
    arm "store is MISSING a file we built" 5
    printf 'content of index.wasm\n' > "$d/b/index.wasm"

    printf 'stray\n' > "$d/b/extra.js"
    arm "store serves a file we did not build" 5
    rm -f "$d/b/extra.js"

    rm -f "$d"/b/*
    arm "store side empty" 2
    for n in index.html index.wasm index.pck; do printf 'content of %s\n' "$n" > "$d/b/$n"; done

    # ── SCALE ARM ────────────────────────────────────────────────────────────
    # The arms above use 3-file fixtures, which is FAR below the point where uutils `comm`
    # short-reads a process substitution — so they passed happily while this script used the
    # forbidden form, and would pass again if anyone reintroduced it. Measured threshold on
    # this box: ~4078 lines from a fast producer. 5000 files puts a single planted difference
    # beyond it, where a truncating comparison returns ZERO differences and reads as clean.
    mkdir -p "$d/big_a" "$d/big_b"
    python3 - "$d" <<'PYGEN'
import sys, os
d = sys.argv[1]
for side in ("big_a", "big_b"):
    for i in range(5000):
        open(os.path.join(d, side, f"f{i:05d}.bin"), "w").write(f"payload {i}\n")
# The planted difference must be a NAME-SET difference, not a content one. comm compares
# NAME SETS only; a tampered file is caught by the separate content loop, which never
# touches comm — so a content-difference fixture passes even with the forbidden form and
# proves nothing. Measured: it did exactly that. DELETE the file instead, at the END of
# sorted order where a truncated read cannot reach it.
os.remove(os.path.join(d, "big_b", "f04999.bin"))
PYGEN
    # ASSERT ON *WHICH* DIFFERENCE, NOT ON THE EXIT CODE. Exit 5 does not discriminate here:
    # measured, the forbidden comm+procsub form reports 3830 SPURIOUS differences on this
    # fixture where the truth is 1 — so it also exits 5, and an exit-code arm passes for both
    # the correct and the broken implementation, for opposite reasons. The count is the only
    # thing that separates them.
    local out_s; out_s="$("$self" --compare "$d/big_a" "$d/big_b" 2>&1)"
    local gs=$?; [ "$gs" -eq 5 ] && saw5=1
    local named; named="$(printf '%s' "$out_s" | grep -o 'f0[0-9]*\.bin' | sort -u | tr '\n' ' ')"
    local ncount; ncount="$(printf '%s' "$named" | wc -w)"
    if [ "$gs" -eq 5 ] && [ "$ncount" -eq 1 ] && [ "${named% }" = "f04999.bin" ]; then
        pass=$((pass+1)); printf '  ok    %-46s names exactly f04999.bin\n' "5000 files: reports the ONE real difference"
    else
        fail=$((fail+1)); printf '  FAIL  %-46s exit %s, named %s file(s): %s\n' "5000 files: reports the ONE real difference" "$gs" "$ncount" "${named:0:60}"
    fi
    rm -rf "$d/big_a" "$d/big_b"

    "$self" --compare "$d/a" "$d/nope" >/dev/null 2>&1
    local g=$?; [ "$g" -eq 2 ] && { pass=$((pass+1)); printf '  ok    %-46s exit %s\n' "store dir missing entirely" "$g"; } \
        || { fail=$((fail+1)); printf '  FAIL  %-46s exit %s (wanted 2)\n' "store dir missing entirely" "$g"; }

    echo
    echo "selftest: ${pass} passed, ${fail} failed"
    if [ "$saw0" -ne 1 ] || [ "$saw5" -ne 1 ]; then
        echo "selftest: BROKEN — outcomes seen: identical=${saw0} differs=${saw5}; both required" >&2
        return 1
    fi
    [ "$fail" -eq 0 ]
}

case "${1:-}" in
    --selftest) selftest ;;
    --compare)  compare "${2:-}" "${3:-}" "${4:-A}" "${5:-B}" ;;
    "")         echo "usage: $0 <web|linux|windows> <local-build-dir> | --compare <a> <b> | --selftest" >&2; exit 2 ;;
    *)          fetch_and_compare "$1" "${2:-}" ;;
esac
