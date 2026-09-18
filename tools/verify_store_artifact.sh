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
# BOTH SIDES MUST BE THIS RELEASE, checked BEFORE the fetch (2026-09-16). The store side has been
# named since the evidence-tag work; the local side was taken on faith, and "warn, then compare
# anyway" turns a wrong local build into a confident accusation against a correct store. Two
# guards, both cheap, both refusing rather than guessing:
#   version   this checkout's tag vs the version the store serves on that channel
#   staleness the newest file in the build dir vs this checkout's own commit time
# --allow-version-skew exists for a deliberate cross-release comparison and says so in the log.
#
# Usage:  tools/verify_store_artifact.sh <channel> <local-build-dir> [--allow-version-skew]
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
    # ⛔ THIS USED TO SPAWN TWO PROCESSES PER FILE — `cksum` and `awk`, inside the read loop.
    # On the selftest's 5000-file fixture that is 20,000 spawns across the two directories and
    # it cost 18.6 s, the whole of what remained after compare()'s O(n^2) content loop was
    # fixed. Batched through xargs: same manifest, same order, same field format.
    #
    # The name is taken as "everything after the second space" rather than $3, because cksum
    # prints `SUM SIZE NAME` and a NAME may contain spaces; and the directory prefix is
    # stripped by LENGTH rather than by a regex, because a path can carry regex metacharacters.
    find "$dir" -type f -print0 2>/dev/null | sort -z \
        | xargs -0 -r cksum 2>/dev/null \
        | awk -v p="$dir/" '{
              s = $1
              i = index($0, " "); rest = substr($0, i + 1)
              j = index(rest, " "); n = substr(rest, j + 1)
              if (substr(n, 1, length(p)) == p) { n = substr(n, length(p) + 1) }
              print n " " s
          }'
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
    local tmpd; tmpd="$(mktemp -d "$(_scratch_base "$(pwd -P)")/svcmp.XXXXXX")"
    printf '%s\n' "$ma" > "$tmpd/a.manifest"
    printf '%s\n' "$mb" > "$tmpd/b.manifest"
    awk 'NF{print $1}' "$tmpd/a.manifest" | sort > "$tmpd/a.names"
    awk 'NF{print $1}' "$tmpd/b.manifest" | sort > "$tmpd/b.names"
    local only_a only_b diff_files=0
    only_a="$(grep -Fxv -f "$tmpd/b.names" "$tmpd/a.names" | tr '\n' ' ')"
    only_b="$(grep -Fxv -f "$tmpd/a.names" "$tmpd/b.names" | tr '\n' ' ')"

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

    # contents, for the files present on both sides.
    #
    # ⛔ THIS USED TO SPAWN ONE awk PER FILE, each re-scanning the WHOLE other manifest — O(n^2)
    # work plus n process spawns. Measured on the selftest's 5000-file fixture: 35.88 s, which
    # is 99.7% of a 35.99 s selftest and the sole reason this tool was EXEMPTED from gate 0d
    # on cost. The fixtures themselves cost 0.24 s to build and hash; the slow thing was not
    # the thing that looked slow, and shrinking the fixture — my first idea — would have
    # hollowed the arm that catches the comm/procsub truncation for a 0.18 s saving.
    #
    # One awk pass instead: read B into a map, stream A, emit only the differing triples. The
    # loop below then runs over the differences (normally zero) rather than over every file.
    local diffs
    diffs="$(awk 'NR==FNR { if (NF) b[$1]=$2; next }
                  NF && ($1 in b) && b[$1] != $2 { print $1 " " $2 " " b[$1] }' \
             "$tmpd/b.manifest" "$tmpd/a.manifest")"
    if [ -n "$diffs" ]; then
        while read -r name sum other; do
            [ -z "$name" ] && continue
            echo "[store-verify] BLOCKED: ${name} differs — ${alabel}=${sum} ${blabel}=${other}" >&2
            diff_files=$((diff_files+1)); rc=5
        done <<< "$diffs"
    fi
    rm -rf "$tmpd"

    if [ "$rc" -eq 0 ]; then
        # The verdict names the two sides it was GIVEN. This line used to read "the store
        # serves exactly what we built" unconditionally — true for the fetch path it was
        # written for, and false the first time --compare was pointed at two local
        # directories, where it announced a store guarantee about a comparison no store took
        # part in. A hardcoded conclusion is not a verdict, it is a caption.
        echo "[store-verify] identical: ${na} file(s), every checksum matches"
        echo "[store-verify]   ${alabel} and ${blabel} agree"
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

    # NOT /tmp. On this box /tmp is TMPFS (RAM, measured 2026-09-15), so every read-back held a
    # whole build -- 209-306 MiB -- in memory while it compared, which is the free-memory signal
    # the harness reaper has killed publishes on before. An explicit TMPDIR is still honoured.
    local out; out="$(mktemp -d "$(_scratch_base "$(pwd -P)")/storeverify.XXXXXX")"
    # shellcheck disable=SC2064
    trap "rm -rf '$out'" RETURN
    echo "[store-verify] fetching ${TARGET}:${channel} (this downloads the whole build)"
    # ⛔ KEEP BUTLER'S OWN ERROR. This used to be `>/dev/null 2>&1`, so every failure read
    # exactly "butler fetch failed" and nothing else. On 2026-09-18 that cost two hours:
    # four blocked read-backs in a row, and the tool could not distinguish
    #
    #     a transient itch API timeout   -> retry in a few minutes        (what it actually was)
    #     an expired/absent credential   -> escalate, do not retry
    #     a channel that does not exist  -> a publish problem, not a read problem
    #
    # Three causes, three different responses, one message. I learned the real one by running
    # `butler fetch` by hand and reading `context deadline exceeded` off api.itch.io — which is
    # CLAUDE.md's own rule (`don't 2>/dev/null a measurement command — it deletes the warning
    # and keeps the wrong number`) broken inside the tool whose entire job is the authoritative
    # read. The classification below is a HINT, never a verdict: the raw butler text is printed
    # regardless, so an unrecognised failure is still fully visible.
    local ferr; ferr="${out}.fetch.log"
    if ! butler fetch "${TARGET}:${channel}" "$out" > "$ferr" 2>&1; then
        echo "[store-verify] BLOCKED: butler fetch failed for ${channel}. A failed read is not" >&2
        echo "               evidence the store is correct." >&2
        if [ -s "$ferr" ]; then
            echo "[store-verify] butler said:" >&2
            tail -5 "$ferr" | sed 's/^/               /' >&2
            case "$(tr -d '\n' < "$ferr")" in
                *"context deadline exceeded"*|*"timeout"*|*"no such host"*|*"connection refused"*)
                    echo "[store-verify] looks like a NETWORK/API failure — the store is probably" >&2
                    echo "               fine and the READ is what failed. Retry before acting." >&2 ;;
                *"401"*|*"403"*|*"invalid key"*|*"not authorized"*|*"login"*)
                    echo "[store-verify] looks like a CREDENTIAL failure — do not retry in a loop." >&2 ;;
                *"404"*|*"no such channel"*|*"not found"*)
                    echo "[store-verify] looks like a MISSING CHANNEL — that is a publish problem," >&2
                    echo "               not a read problem. Check what was pushed." >&2 ;;
            esac
        else
            echo "[store-verify] butler produced no output at all — that is itself the finding." >&2
        fi
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
    d="$(mktemp -d "$(_scratch_base "$(pwd -P)")/sv.XXXXXX")"
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

    # ── archiving destination, BOTH branches ────────────────────────────────────────────
    # One of these is unreachable from wherever this runs, which is why _readback_dest takes
    # `here` rather than reading pwd. A resolver that always answered would pass the first arm
    # alone; one that always refused would pass the second alone.
    local got
    got="$(_readback_dest /home/x/lane-wt/tmp/pub999 v9.9.9 2>/dev/null)"
    if [ "$got" = "/home/x/lane-wt/tmp/_archive/logs/v9.9.9" ]; then
        pass=$((pass+1)); printf '  ok    %-46s %s\n' "dest escapes the publish worktree" "$got"
    else
        fail=$((fail+1)); printf '  FAIL  %-46s got %s\n' "dest escapes the publish worktree" "$got"
    fi
    if _readback_dest /home/x/plainrepo v9.9.9 >/dev/null 2>&1; then
        fail=$((fail+1)); printf '  FAIL  %-46s accepted a non-worktree path\n' "dest refuses outside <lane>/tmp/<wt>"
    else
        pass=$((pass+1)); printf '  ok    %-46s refused\n' "dest refuses outside <lane>/tmp/<wt>"
    fi
    # the archive must be a SIBLING of the worktree, never inside it — the publish removes it
    case "$(_readback_dest /home/x/lane-wt/tmp/pub999 v9.9.9 2>/dev/null)" in
        /home/x/lane-wt/tmp/pub999/*)
            fail=$((fail+1)); printf '  FAIL  %-46s dest is INSIDE the worktree\n' "dest survives the worktree removal" ;;
        *)  pass=$((pass+1)); printf '  ok    %-46s sibling, not child\n' "dest survives the worktree removal" ;;
    esac
    # ── the verdict word must track the exit code, not be decorative ─────────────────────
    for pair in "0 identical" "5 DIFFERS FROM THE STORE" "2 could not evaluate"; do
        set -- $pair
        local code="$1"; shift; local want="$*"
        got="$(_verdict_word "$code")"
        if [ "$got" = "$want" ]; then
            pass=$((pass+1)); printf '  ok    %-46s %s\n' "verdict word for exit ${code}" "$got"
        else
            fail=$((fail+1)); printf '  FAIL  %-46s got %s want %s\n' "verdict word for exit ${code}" "$got" "$want"
        fi
    done
    if [ "$(_verdict_word 0)" = "$(_verdict_word 5)" ]; then
        fail=$((fail+1)); printf '  FAIL  %-46s identical and DIFFERS read the same\n' "verdict words discriminate"
    else
        pass=$((pass+1)); printf '  ok    %-46s differ\n' "verdict words discriminate"
    fi

    # ── evidence is named after what the STORE serves, and scratch is not tmpfs ──────────────
    _eq() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok    %-46s %s\n' "$1" "${2:-<empty>}"
            else fail=$((fail+1)); printf '  FAIL  %-46s got %s want %s\n' "$1" "${2:-<empty>}" "${3:-<empty>}"; fi; }
    # a real `butler status` table, copied from 2026-09-15
    local st='+----------+-----------+----------------------------+---------------------------+
| CHANNEL  |  UPLOAD   |           BUILD            |          VERSION          |
+----------+-----------+----------------------------+---------------------------+
| linux    | #18690458 | ✓ #1979875 (from #1973335) | v3.33.349-alpha+09334a342 |
| web      | #16306641 | ✓ #1979888 (from #1973342) | v3.33.349-alpha+09334a342 |
| windows  | #18757510 | ✓ #1979877 (from #1973339) | v3.33.349-alpha+09334a342 |'
    _eq "store version: linux row, +sha dropped"      "$(printf '%s\n' "$st" | _store_version linux)"   "v3.33.349-alpha"
    _eq "store version: windows row"                  "$(printf '%s\n' "$st" | _store_version windows)" "v3.33.349-alpha"
    _eq "store version: channel absent -> empty"      "$(printf '%s\n' "$st" | _store_version android)" ""
    local et
    et="$(_evidence_tag v3.33.349-alpha v3.33.349-alpha)"
    _eq "evidence: match -> store tag, no note"       "${et%%$'\t'*}|${et#*$'\t'}" "v3.33.349-alpha|"
    et="$(_evidence_tag v3.33.347-alpha v3.33.349-alpha)"
    _eq "evidence: mismatch -> named after the STORE" "${et%%$'\t'*}" "v3.33.349-alpha"
    case "${et#*$'\t'}" in *MISMATCH*v3.33.349-alpha*v3.33.347-alpha*) _eq "  ...and the note names both" yes yes ;;
                              *) _eq "  ...and the note names both" "${et#*$'\t'}" "MISMATCH naming both" ;; esac
    et="$(_evidence_tag 3cd794ea6 "")"
    _eq "evidence: store unknown -> checkout, flagged" "${et%%$'\t'*}" "3cd794ea6"
    case "${et#*$'\t'}" in *"store version unknown"*) _eq "  ...and says so" yes yes ;; *) _eq "  ...and says so" no yes ;; esac

    # ── BOTH SIDES: is this comparison's LOCAL side the release the store serves? ──────────
    # Every arm here exists because the previous behaviour was to warn and compare anyway,
    # which spends a whole build's bandwidth to produce "DIFFERS FROM THE STORE" about a
    # store that is correct.
    local sk
    sk="$(_skew_verdict v3.33.355-alpha v3.33.355-alpha no)"
    _eq "skew: same release -> ok, nothing to say"     "${sk%%$'\t'*}|${sk#*$'\t'}" "ok|"
    sk="$(_skew_verdict 3cd794ea6 v3.33.354-alpha no)"
    _eq "skew: checkout is not the release -> BLOCK"   "${sk%%$'\t'*}" "block"
    case "${sk#*$'\t'}" in *3cd794ea6*v3.33.354-alpha*) _eq "  ...and names both sides" yes yes ;;
                            *) _eq "  ...and names both sides" "${sk#*$'\t'}" "names both" ;; esac
    case "${sk#*$'\t'}" in *"pub<N>"*) _eq "  ...and says where the right build is" yes yes ;;
                            *) _eq "  ...and says where the right build is" no yes ;; esac
    sk="$(_skew_verdict 3cd794ea6 v3.33.354-alpha yes)"
    _eq "skew: --allow-version-skew -> ok, on purpose" "${sk%%$'\t'*}" "ok"
    case "${sk#*$'\t'}" in *DELIBERATELY*) _eq "  ...and labels it deliberate" yes yes ;;
                            *) _eq "  ...and labels it deliberate" no yes ;; esac
    # A store we could not read is NOT a mismatch. Blocking here would make an unreachable
    # butler look like a bad build, and the comparison is still worth running.
    sk="$(_skew_verdict v3.33.355-alpha "" no)"
    _eq "skew: store version unknown -> still runs"    "${sk%%$'\t'*}" "ok"

    # ── the other stale case the version check CANNOT see: right tree, old export ──────────
    local stv
    stv="$(_stale_verdict 1700000000 1600000000)"
    _eq "stale: artifact newer than HEAD -> ok"        "${stv%%$'\t'*}" "ok"
    stv="$(_stale_verdict 1600000000 1700000000)"
    _eq "stale: artifact OLDER than HEAD -> BLOCK"     "${stv%%$'\t'*}" "block"
    case "${stv#*$'\t'}" in *2020-09-13*2023-11-14*) _eq "  ...and dates both" yes yes ;;
                             *) _eq "  ...and dates both" "${stv#*$'\t'}" "both dates" ;; esac
    stv="$(_stale_verdict 1600000000 1600000000)"
    _eq "stale: same second -> ok, not a block"        "${stv%%$'\t'*}" "ok"
    stv="$(_stale_verdict "" 1700000000)"
    _eq "stale: unreadable mtime -> ok, never a claim" "${stv%%$'\t'*}" "ok"
    stv="$(_stale_verdict 1600000000 "")"
    _eq "stale: unreadable HEAD -> ok, never a claim"  "${stv%%$'\t'*}" "ok"
    # _newest_mtime against real files, both a populated and an empty directory.
    local md; md="$(mktemp -d "$HOME/.cache/vsa_mtime.XXXXXX")"
    : > "$md/old"; touch -d @1600000000 "$md/old"
    : > "$md/new"; touch -d @1700000000 "$md/new"
    _eq "newest mtime: takes the MAX, not the first"   "$(_newest_mtime "$md")" "1700000000"
    mkdir -p "$md/empty"
    _eq "newest mtime: empty dir -> empty, not 0"      "$(_newest_mtime "$md/empty")" ""
    rm -rf "$md"
    # Probe paths live in a SCOPED temp dir -- _scratch_base mkdirs what it returns, so fixed
    # absolute probes would create (and a cleanup would delete) real paths. It must contain NO
    # "/tmp/" of its own: the lane root is everything before the FIRST /tmp/ (the archive's rule),
    # so a probe nested under this worktree's tmp/ resolves to the real lane, not the probe.
    local sd sb; mkdir -p "$HOME/.cache"; sd="$(mktemp -d "$HOME/.cache/vsa_scratch.XXXXXX")"
    sb="$(TMPDIR= _scratch_base "$sd/lane-wt/tmp/pub999")"
    _eq "scratch: lane tmp, not /tmp"                  "$sb" "$sd/lane-wt/tmp/_storeverify"
    sb="$(TMPDIR= _scratch_base "$sd/plainrepo")"
    _eq "scratch: plain repo -> its own tmp/"          "$sb" "$sd/plainrepo/tmp/_storeverify"
    sb="$(TMPDIR="$sd/explicit" _scratch_base "$sd/lane-wt/tmp/pub999")"
    _eq "scratch: an explicit TMPDIR is honoured"      "$sb" "$sd/explicit"
    case "$sb" in /tmp/*) _eq "scratch: never defaults under /tmp" "$sb" "not /tmp" ;; esac
    rm -rf -- "$sd"

    echo
    echo "selftest: ${pass} passed, ${fail} failed"
    if [ "$saw0" -ne 1 ] || [ "$saw5" -ne 1 ]; then
        echo "selftest: BROKEN — outcomes seen: identical=${saw0} differs=${saw5}; both required" >&2
        return 1
    fi
    [ "$fail" -eq 0 ]
}

# ── archive the verdict ──────────────────────────────────────────────────────────────────
# ⛔ THE ONLY CHECK THAT CROSSES THE CDN LEFT NO TRACE. Measured on v3.33.318-alpha's archive:
# 18 logs, and ZERO of them mention store-verify. Every LOCAL gate is recorded -- import,
# export, boot, battle, smoke, pck size -- while the one comparison against the bytes itch
# actually serves went to a terminal and vanished. A release's evidence therefore proves the
# build was correct and says nothing about what the store holds.
#
# Same shape as two defects already fixed on this path: the detached .ec, destroyed by the
# worktree removal that follows every publish, and the boot logs, which could not name their
# own subject. In all three the most decisive artifact was the one not in the record.
#
# `here` and `tag` are PARAMETERS so both branches can be driven; one of them is unreachable
# from wherever the selftest happens to run.
# Scratch base: explicit TMPDIR if the caller set one, else the lane's own tmp/ (derived the same
# way as the archive), else ./tmp. Never a default of /tmp.
_scratch_base() {
    local here="$1" base
    if [ -n "${TMPDIR:-}" ]; then base="$TMPDIR"
    else case "$here" in
            */tmp/*) base="${here%%/tmp/*}/tmp/_storeverify" ;;
            *)       base="$here/tmp/_storeverify" ;;
         esac
    fi
    mkdir -p "$base" 2>/dev/null
    printf '%s' "$base"
}

# The version the STORE serves on a channel, from `butler status` text on stdin -> "v3.33.349-alpha"
# (the +sha build label is dropped). Empty if the channel row is absent or unparseable.
_store_version() {
    awk -F'|' -v ch="$1" '{ c=$2; gsub(/ /,"",c); if (c==ch) { v=$5; gsub(/ /,"",v); sub(/\+.*/,"",v); print v; exit } }'
}

# Which release this read-back is EVIDENCE for. The subject of a store read-back is what the store
# SERVES, so that names it -- not the checkout the tool happens to run in. Prints "<tag>\t<note>".
_evidence_tag() {
    local checkout="$1" store="$2"
    if [ -z "$store" ]; then
        printf '%s\t%s' "$checkout" "store version unknown -- labelled from the checkout (${checkout})"
    elif [ "$store" = "$checkout" ]; then
        printf '%s\t' "$store"
    else
        printf '%s\t%s' "$store" "MISMATCH: the store serves ${store} but this checkout is ${checkout}; the local build compared may not be ${store}'s"
    fi
}

# Can this read-back answer the question it was asked? The subject is "does the store serve what
# we built for THIS release", and that needs BOTH sides to be that release. The store side has
# been named since 49b6fc87; the local side was taken on faith.
#
# WHY IT IS A BLOCK AND NOT THE WARNING IT USED TO BE (cowir-deploy, 2026-09-16). I ran this
# against `cowir-deploy-wt/builds/web` while that worktree sat on an Aug-22 branch — the real
# .354 artifacts were in the publish's own `tmp/pub354`. The tool would have printed its ⚠, then
# downloaded 207 MiB, then reported exit 5 = "DIFFERS FROM THE STORE". Every word of that verdict
# accuses the store of serving the wrong bytes, and the store was correct. A skewed comparison
# does not produce a weaker answer, it produces a CONFIDENT WRONG ONE, and it charges a full
# build's bandwidth to do it.
#
# Prints "block\t<reason>" or "ok\t<note>".
_skew_verdict() {
    local checkout="$1" store="$2" allow="$3"
    if [ -z "$store" ]; then
        printf 'ok\t%s' "store version unknown — proceeding, the comparison is still the evidence"
    elif [ "$checkout" = "$store" ]; then
        printf 'ok\t'
    elif [ "$allow" = "yes" ]; then
        printf 'ok\t--allow-version-skew: comparing %s against a store serving %s DELIBERATELY' "$checkout" "$store"
    else
        printf 'block\tthis checkout is %s but the store serves %s. The local build in this tree is not %s'"'"'s, so a difference here would be reported as the STORE being wrong when the wrong build is the one that was handed in. Point this at the worktree that produced %s (the publish leaves it at <lane>/tmp/pub<N>), or pass --allow-version-skew to compare across releases on purpose.' "$checkout" "$store" "$store" "$store"
    fi
}

# The newest regular file in a build directory. A build cannot be OLDER than the commit it would
# be attributed to, and this is the case the version check above cannot see: the right tree, an
# artifact directory left over from an earlier export in it.
_newest_mtime() {
    find "$1" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1 | cut -d. -f1
}

# "block\t<reason>" when the artifacts cannot be this checkout's. Pure, so the selftest can
# reach it; the filesystem half is _newest_mtime.
_stale_verdict() {
    local newest="$1" head_ts="$2"
    if [ -z "$head_ts" ] || [ -z "$newest" ]; then
        printf 'ok\t'                       # unknown is not evidence either way
    elif [ "$newest" -lt "$head_ts" ]; then
        printf 'block\tnewest artifact %s predates HEAD %s' \
            "$(date -d "@$newest" -u +%Y-%m-%dT%H:%MZ)" "$(date -d "@$head_ts" -u +%Y-%m-%dT%H:%MZ)"
    else
        printf 'ok\t'
    fi
}

_readback_dest() {
    local here="$1" tag="$2"
    case "$here" in
        */tmp/*) printf '%s' "${here%%/tmp/*}/tmp/_archive/logs/${tag}" ;;
        *)       return 1 ;;
    esac
}

_verdict_word() {
    case "$1" in
        0) printf 'identical' ;;
        5) printf 'DIFFERS FROM THE STORE' ;;
        *) printf 'could not evaluate' ;;
    esac
}

# Not archiving is never a reason to skip the check: the comparison matters more than its
# record, so an unrecognised layout warns and still runs.
_run_and_archive() {
    local ch="$1" dir="${2:-}" here tag dest ec
    here="$(pwd -P)"
    # ⛔ This used to be the ONLY source of the label: the tag of whatever checkout the tool ran in.
    # Run from a publish worktree right after its publish that is right; run anywhere else it
    # files a read-back of what the store serves under a release the store may not be serving.
    local checkout store note
    checkout="$(git describe --tags --exact-match HEAD 2>/dev/null)" \
        || checkout="$(git rev-parse --short HEAD 2>/dev/null)" || checkout="untagged"
    [ -n "$checkout" ] || checkout="untagged"
    store="$(butler status "$TARGET" 2>/dev/null | _store_version "$ch")"
    IFS=$'\t' read -r tag note <<<"$(_evidence_tag "$checkout" "$store")"
    [ -n "$note" ] && echo "[store-verify] ⚠ ${note}" >&2

    # BOTH SIDES, before the fetch. Everything below this point costs 207-312 MiB.
    local verdict reason
    IFS=$'\t' read -r verdict reason <<<"$(_skew_verdict "$checkout" "$store" "$ALLOW_SKEW")"
    if [ "$verdict" = "block" ]; then
        echo "[store-verify] BLOCKED: ${reason}" >&2
        return 2
    fi
    [ -n "$reason" ] && echo "[store-verify] note: ${reason}"
    if [ -d "$dir" ]; then
        local sv sreason
        IFS=$'\t' read -r sv sreason <<<"$(_stale_verdict \
            "$(_newest_mtime "$dir")" "$(git log -1 --format=%ct HEAD 2>/dev/null)")"
        if [ "$sv" = "block" ]; then
            echo "[store-verify] BLOCKED: every file in ${dir} predates this checkout's own commit" >&2
            echo "               (${sreason})." >&2
            echo "               A build cannot be older than the commit it would be attributed to, so this" >&2
            echo "               directory is a leftover export, not this release's. Re-export, or point at" >&2
            echo "               the worktree that produced it." >&2
            return 2
        fi
    fi
    if ! dest="$(_readback_dest "$here" "$tag")"; then
        echo "[store-verify] note: NOT archiving — ${here} is not a <lane>/tmp/<worktree> path." >&2
        fetch_and_compare "$ch" "$dir"
        return $?
    fi
    mkdir -p "$dest" 2>/dev/null || {
        echo "[store-verify] note: NOT archiving — could not create ${dest}." >&2
        fetch_and_compare "$ch" "$dir"
        return $?
    }
    fetch_and_compare "$ch" "$dir" 2>&1 | tee "${dest}/readback_${ch}.log"
    ec=${PIPESTATUS[0]}
    printf '[store-verify] verdict: exit %s (%s) · %s · store serves %s · checkout %s%s\n' \
        "$ec" "$(_verdict_word "$ec")" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${store:-unknown}" "$checkout" \
        "${note:+ · $note}" | tee -a "${dest}/readback_${ch}.log"
    echo "[store-verify] archived: ${dest}/readback_${ch}.log"
    return "$ec"
}

# --allow-version-skew may appear anywhere; it is stripped before dispatch so the positional
# arguments keep their meaning.
ALLOW_SKEW=no
_args=()
for _a in "$@"; do
    case "$_a" in
        --allow-version-skew) ALLOW_SKEW=yes ;;
        *) _args+=("$_a") ;;
    esac
done
set -- "${_args[@]:-}"

case "${1:-}" in
    --selftest) selftest ;;
    --compare)  compare "${2:-}" "${3:-}" "${4:-A}" "${5:-B}" ;;
    "")         echo "usage: $0 <web|linux|windows> <local-build-dir> | --compare <a> <b> | --selftest" >&2; exit 2 ;;
    *)          _run_and_archive "$1" "${2:-}" ;;
esac
