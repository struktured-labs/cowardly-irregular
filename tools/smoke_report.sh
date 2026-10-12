#!/usr/bin/env bash
# Print what a human needs from a render-smoke log: the verdict, and WHY.
#
# WHY THIS IS A TOOL AND NOT A GREP
# ---------------------------------
# deploy_web.sh used to end the render-smoke gate with
#
#     grep "VERDICT" tmp/deploy_smoke.log
#
# ⛔ TWO DEFECTS IN ONE LINE, both measured 2026-10-12.
#
# 1. IT EXTRACTS THE RESULT AND DISCARDS THE REASON. @cowir-overworld's bounded wipe leg emits
#    three distinct failures, and the line that tells them apart is NOT the VERDICT line:
#      [SMOKE] FAIL: wipe leg OUTRAN ITS BUDGET after 90.7s while still advancing — a slow box
#      [SMOKE] FAIL: wipe STALLED — no round advanced in 25s
#      [SMOKE] FAIL: wipe battle ended at round 15 and no game over screen came up within 15s
#    "re-run it" versus "fix the tree" is the whole point of that change, and it was in the log
#    and not in the report. That is the .654 incident from the other side: two identical
#    failures, and I had to diff against .652 and .653 to learn what "no game over" meant.
#
# 2. BARE `grep` GOES BLIND ON A LOG IT JUDGES BINARY, AND SUCCEEDS WHILE DOING IT. Measured in
#    a script (GNU grep 3.11), on a log holding one NUL byte:
#      grep "VERDICT" log             -> stdout EMPTY, exit 0, "binary file matches" on stderr
#      command grep -a "VERDICT" log  -> [SMOKE] VERDICT: PASS
#    An empty capture with exit 0 reads as "no verdict" and passes every guard that tests the
#    exit code.
#
# IS THAT LIVE OR THEORETICAL? THEORETICAL HERE, AND FIXED ANYWAY. (@cowir-battle established
# the distinction and I verified it.) The documented NUL mechanism in this repo is a FILESYSTEM
# HOLE from two processes sharing one log path, not engine output — godot sanitises NUL out of
# print(). `deploy_smoke.log` is a fixed name, but `tmp/` lives inside the per-publish pub<N>
# worktree, so two publishes never share it, and the retry at deploy_web.sh:711 runs strictly
# after attempt 1 is copied aside. No second writer, no hole. The reason to fix it is the blast
# radius: this is the line that reports whether the smoke passed.
#
# ⛔ AND THE GATE DOES NOT DEPEND ON THIS OUTPUT, which is worth stating so nobody "hardens" it
# into a decision. GameLoop.gd:747 is `get_tree().quit(1 if _smoke_failed else 0)`, so a FAIL
# verdict exits 1 and deploy_web.sh's `if ! "${SMOKE_CMD[@]}"` already blocks. This tool reports;
# it does not judge.
#
# Usage:  tools/smoke_report.sh <smoke-log>
#         tools/smoke_report.sh --selftest
# Exit:   0 reported · 2 usage / unreadable log
set -uo pipefail

# Prose in a scanned file is input. ONE shared stripper, never a private copy — see
# tools/gd_code_lines.sh for the measurements and for what it does not close.
. "$(cd "$(dirname "$0")" && pwd)/gd_code_lines.sh"

# Order-preserving: one pass, so the lines arrive as the run produced them (wipe/FAIL before the
# VERDICT) rather than in an order this script invents.
_PAT='^\[SMOKE\] (VERDICT:|FAIL:|wipe:)'

# ⛔ THE CHECK THE ARMS COULD NOT REACH. The emitter-prefix logic below used to live only inside
# selftest(), reading the REAL src/GameLoop.gd — a file with no prose-only prefix, so replacing
# `gd_code_lines` with a raw `cat` changed nothing any arm could see. MEASURED: with the stripper
# bypassed in the production path, the selftest stayed 17/17 GREEN. My planted "acceptance attack"
# called gd_code_lines ITSELF, so it certified the HELPER and said nothing about the CALLER.
# (@cowir-battle found the identical scoping defect in their own guard and that is what sent me to
# mutate mine.) Extracted so an arm can point it at a planted file and watch it fail.
_prefixes_present() {   # <file> -> prints each prefix that is NOT present in its CODE
    local src="$1" pfx code
    code="$(gd_code_lines "$src")"
    for pfx in 'VERDICT:' 'FAIL:' 'wipe:'; do
        command grep -aq "print(\"\[SMOKE\] ${pfx}" <<< "$code" || printf '%s\n' "$pfx"
    done
}

report() {
    local log="$1" out
    if [ ! -f "$log" ]; then
        echo "[smoke] BLOCKED: ${log} does not exist. A missing log is not a passing smoke." >&2
        return 2
    fi
    if [ ! -s "$log" ]; then
        echo "[smoke] BLOCKED: ${log} is empty — the smoke wrote nothing at all." >&2
        return 2
    fi
    # -a is the whole point: see the header. -E for the alternation.
    out="$(command grep -aE -- "$_PAT" "$log")"
    if [ -z "$out" ]; then
        # A silent empty is what this file exists to stop. Say which lines were looked for.
        echo "[smoke] NO VERDICT LINE in ${log} ($(wc -l < "$log") lines). The run neither passed" >&2
        echo "        nor failed in its own words — it was killed, or it crashed before printing." >&2
        return 0
    fi
    printf '%s\n' "$out"
    return 0
}

# ── self-test ────────────────────────────────────────────────────────────────
selftest() {
    local pass=0 fail=0 self dir
    self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    dir="$(mktemp -d "${TMPDIR:-/tmp}/smokereport.XXXXXX")"
    # shellcheck disable=SC2064
    trap "rm -rf '$dir'" EXIT

    chk() { # name pattern want(0 present|1 absent)
        local name="$1" pat="$2" want="$3"
        if printf '%s' "$out" | command grep -aq -- "$pat"; then
            [ "$want" -eq 0 ] && { pass=$((pass+1)); printf '  ok    %-54s\n' "$name"; return; }
        else
            [ "$want" -eq 1 ] && { pass=$((pass+1)); printf '  ok    %-54s\n' "$name"; return; }
        fi
        fail=$((fail+1)); printf '  FAIL  %-54s (/%s/ want %s)\n' "$name" "$pat" "$want"
    }

    # A PASSING log, shaped like a real one.
    {   printf '[SMOKE] cave saved err=0 size=(1280, 720) dominant=0.24 OK\n'
        printf '[SMOKE] wipe: game over after 1.3s at round 11\n'
        printf '[SMOKE] VERDICT: PASS\n'
    } > "$dir/pass.log"
    out="$("$self" "$dir/pass.log" 2>&1)"
    chk "the verdict is reported"                      'VERDICT: PASS'      0
    chk "...and the wipe timing with it"               'wipe: game over'    0
    chk "...and ordinary shot lines are NOT dumped"    'cave saved'         1

    # A FAILING log: the REASON is the thing the old line threw away.
    {   printf '[SMOKE] FAIL: wipe STALLED — no round advanced in 25s (stuck at round 8)\n'
        printf '[SMOKE] VERDICT: FAIL\n'
    } > "$dir/fail.log"
    out="$("$self" "$dir/fail.log" 2>&1)"
    chk "a FAIL reason reaches the report"             'wipe STALLED'       0
    chk "...alongside the verdict"                     'VERDICT: FAIL'      0

    # ⛔ THE NUL ARM, AND ITS CONTROL MUST WATCH THE BARE FORM FAIL. (@cowir-sfx asked for
    # exactly this: a `-a` that was never tested against a binary-judged file is a flag someone
    # added because a document said to.) The same file, two readers, opposite answers.
    {   printf '[SMOKE] wipe: game over after 1.3s at round 11\n'
        printf 'a binary\000byte from a sparse hole\n'
        printf '[SMOKE] VERDICT: PASS\n'
    } > "$dir/nul.log"
    python3 -I -c "
import sys
sys.exit(0 if b'\x00' in open('$dir/nul.log','rb').read() else 1)" \
        && { pass=$((pass+1)); printf '  ok    %-54s\n' "the NUL fixture really contains a NUL"; } \
        || { fail=$((fail+1)); printf '  FAIL  %-54s\n' "the NUL fixture contains no NUL — arms below are void"; }
    out="$("$self" "$dir/nul.log" 2>&1)"
    chk "a NUL in the log does NOT hide the verdict"   'VERDICT: PASS'      0
    chk "...nor the reason line"                       'wipe: game over'    0
    # THE CONTROL: the form this replaced, on this same file, must come back EMPTY with exit 0.
    bare="$(grep "VERDICT" "$dir/nul.log" 2>/dev/null)"; bare_ec=$?
    if [ -z "$bare" ] && [ "$bare_ec" -eq 0 ]; then
        pass=$((pass+1)); printf '  ok    %-54s\n' "the BARE form returns empty AND exit 0 here"
    else
        fail=$((fail+1)); printf '  FAIL  %-54s (got [%s] exit %s)\n' "the bare form was supposed to go blind" "$bare" "$bare_ec"
    fi
    # ...and the two forms must AGREE on a clean log, or the arm above is measuring the rewrite
    # rather than the -a.
    if [ "$(grep "VERDICT" "$dir/pass.log")" = "$(command grep -a "VERDICT" "$dir/pass.log")" ]; then
        pass=$((pass+1)); printf '  ok    %-54s\n' "on a clean log both forms agree"
    else
        fail=$((fail+1)); printf '  FAIL  %-54s\n' "the forms differ on a CLEAN log — not the NUL"
    fi

    # A log with no verdict at all must SAY SO, not print nothing.
    printf '[SMOKE] cave saved err=0\n' > "$dir/noverdict.log"
    out="$("$self" "$dir/noverdict.log" 2>&1)"
    chk "a log with no verdict says so loudly"          'NO VERDICT LINE'   0
    # And the refusals.
    out="$("$self" "$dir/absent.log" 2>&1)"; local ec1=$?
    chk "a missing log is refused, not reported empty"  'does not exist'    0
    : > "$dir/empty.log"
    out="$("$self" "$dir/empty.log" 2>&1)"; local ec2=$?
    chk "an empty log is refused"                       'is empty'          0
    if [ "$ec1" -eq 2 ] && [ "$ec2" -eq 2 ]; then
        pass=$((pass+1)); printf '  ok    %-54s\n' "both refusals exit 2"
    else
        fail=$((fail+1)); printf '  FAIL  %-54s (%s/%s)\n' "both refusals exit 2" "$ec1" "$ec2"
    fi

    # ⛔ THE ACCEPTANCE ATTACK, PLANTED RATHER THAN REASONED ABOUT. The prefix check above is an
    # ACCEPTANCE set in @cowir-story's sense — it asks "does the emitter still print this", and a
    # phantom answer of YES keeps a dead pattern looking alive. That is the direction that ships a
    # defect, and I had only measured it by hand in a shell. Four lanes planted this attack against
    # their own guards tonight (three immune via GdSource, one fooled), so mine gets the same plant.
    local adir; adir="$(mktemp -d "$PWD/tmp/smoke_cmt.XXXXXX")"
    mkdir -p "$adir/src"
    {   printf 'func _verdict():\n'
        printf '\t# the gate greps for print("[SMOKE] FAIL: <reason>") so keep that spelling\n'
        printf '\tprint("[SMOKE] VERDICT: %%s" %% v)\n'
        printf '\tprint("[SMOKE] wipe: game over after %%.1fs at round %%d" %% [t, r])\n'
    } > "$adir/src/GameLoop.gd"
    # FAIL: exists ONLY in prose here, so a comment-blind check reports it present (measured: 1)
    # while the real print count is 0.
    local prose_hits real_hits
    prose_hits="$(command grep -ac 'print("\[SMOKE\] FAIL:' "$adir/src/GameLoop.gd" || true)"
    real_hits="$(gd_code_lines "$adir/src/GameLoop.gd" | command grep -ac 'print("\[SMOKE\] FAIL:' || true)"
    if [ "${prose_hits:-0}" -ge 1 ] && [ "${real_hits:-0}" -eq 0 ]; then
        pass=$((pass+1)); printf '  ok    %-54s (prose %s, code %s)\n' "a prefix in a COMMENT does not count as present" "$prose_hits" "$real_hits"
    else
        fail=$((fail+1)); printf '  FAIL  %-54s (prose %s, code %s)\n' "the comment-blind and code-only counts agree — plant is void" "${prose_hits:-0}" "${real_hits:-0}"
    fi
    # ⛔ AND NOW DRIVEN THROUGH THE REAL CHECK, not around it. A file whose ONLY `FAIL:` mention is
    # prose must make the prefix report MISSING — which is exactly what breaks if the stripper is
    # ever dropped from that path.
    local missing_planted missing_real
    missing_planted="$(_prefixes_present "$adir/src/GameLoop.gd" | tr '\n' ' ')"
    case "$missing_planted" in
        *FAIL:*) pass=$((pass+1)); printf '  ok    %-54s\n' "the CHECK itself reports a prose-only prefix missing" ;;
        *) fail=$((fail+1)); printf '  FAIL  %-54s (missing: %s)\n' "the check did not notice a prose-only prefix" "${missing_planted:-none}" ;;
    esac
    # CONTROL: against the REAL emitter the same check must report nothing missing, or the arm
    # above passes on a check that is simply broken.
    missing_real="$(_prefixes_present src/GameLoop.gd | tr '\n' ' ')"
    if [ -z "$missing_real" ]; then
        pass=$((pass+1)); printf '  ok    %-54s\n' "...and reports NOTHING missing for the real emitter"
    else
        fail=$((fail+1)); printf '  FAIL  %-54s (missing: %s)\n' "the check reports the real emitter incomplete" "$missing_real"
    fi

    # CONTROL: uncomment it and the code-only count must find it, or the arm above passes on
    # anything that merely fails to match.
    sed -i 's|^\t# the gate greps for ||' "$adir/src/GameLoop.gd"
    real_hits="$(gd_code_lines "$adir/src/GameLoop.gd" | command grep -ac 'print("\[SMOKE\] FAIL:' || true)"
    if [ "${real_hits:-0}" -ge 1 ]; then
        pass=$((pass+1)); printf '  ok    %-54s\n' "...and UNcommented it IS counted"
    else
        fail=$((fail+1)); printf '  FAIL  %-54s (%s)\n' "the uncommented control was not counted" "${real_hits:-0}"
    fi
    rm -rf "$adir"

    # ⛔ A DEAD PATTERN IS THE FAILURE THAT LOOKS LIKE SILENCE. If `[SMOKE] FAIL:` is ever
    # renamed, _PAT matches nothing, the report goes quiet, and the symptom is a FAIL that
    # explains nothing — the .654 experience this tool exists to prevent.
    #
    # ⚠️ My first version of this arm derived the kinds by grepping the emitter FOR THE THREE
    # PREFIXES _PAT ALREADY NAMES, so it could only ever find them: a guard that confirms its own
    # input. It reported "3 kind(s) derived · ok" and could not have failed. What bites instead is
    # asking the emitter whether each prefix STILL EXISTS, and keeping a floor on how many sites
    # use them — a rename takes that count to zero.
    local src="src/GameLoop.gd"
    if [ -f "$src" ]; then
        # ⛔ STRIP ONCE INTO A VARIABLE, AND NEVER PIPE INTO `grep -q` UNDER pipefail.
        # `grep -q` exits on the FIRST match and closes the pipe; the awk producer then takes
        # SIGPIPE and exits non-zero, and `set -o pipefail` reports the pipeline as FAILED
        # BECAUSE IT MATCHED. That is how three arms came to say "the emitter no longer prints
        # [SMOKE] VERDICT:" while the same pattern matched 1/17/1 when run by hand — a verdict
        # about the EMITTER produced by my own plumbing. A herestring has no pipeline at all.
        # (It is also one awk run instead of five.)
        local sites miss=0 pfx code
        code="$(gd_code_lines "$src")"
        # (the same logic is reachable as _prefixes_present below, so an arm can drive it
        #  against a planted file instead of only against the real emitter)
        sites="$(command grep -ac 'print("\[SMOKE\] \(VERDICT:\|FAIL:\|wipe:\)' <<< "$code" || true)"
        case "$sites" in ''|*[!0-9]*) sites=0 ;; esac
        for pfx in 'VERDICT:' 'FAIL:' 'wipe:'; do
            # ⛔ THE QUIET DIRECTION, AND IT IS THE DANGEROUS ONE. This asks "does the emitter
            # still print this prefix", and a COMMENT mentioning the prefix answers YES. Measured:
            # a file whose only FAIL: mention is `# the gate greps for print("[SMOKE] FAIL: …")`
            # reported present=1 with real prints=0 — the dead-pattern guard passes while the
            # extraction matches nothing. Same class as @cowir-music's phantom, opposite
            # direction: theirs reds loudly, this one goes green and certifies a dead pattern.
            command grep -aq "print(\"\[SMOKE\] ${pfx}" <<< "$code" || {
                miss=$((miss+1))
                printf '  FAIL  %-54s\n' "the emitter no longer prints [SMOKE] ${pfx}"
            }
        done
        # A FLOOR, not a count: ten sites exist today, and a lane legitimately adding or removing
        # one must not red. Zero means the prefix moved and this tool went silent.
        # [[the-audit-instrument-gets-the-lower-standard]]
        if [ "$miss" -eq 0 ] && [ "$sites" -ge 4 ]; then
            pass=$((pass+1)); printf '  ok    %-54s (%s sites)\n' "all three prefixes still exist in the emitter" "$sites"
        else
            fail=$((fail+1)); printf '  FAIL  %-54s (%s sites, %s prefix(es) missing)\n' "the extraction pattern has gone dead" "$sites" "$miss"
        fi
        # INFORMATION, not an arm: the other [SMOKE] kinds, so a reason introduced under a NEW
        # prefix is visible here rather than invisible in a publish log. Ordinary shot lines
        # legitimately live in this set and other lanes add them freely, so it cannot be a verdict.
        local others; others="$(command grep -aoE 'print\("\[SMOKE\] [A-Za-z_]+' <<< "$code" \
            | sed -E 's/.*\[SMOKE\] //' | sort -u | command grep -avE '^(VERDICT|FAIL|wipe)$' | tr '\n' ' ')"
        printf '  info  other [SMOKE] kinds in the emitter: %s\n' "${others:-none}"
    elif git rev-parse --show-toplevel >/dev/null 2>&1; then
        # Same shape as cue_trace.sh above. Here a moved emitter WAS caught — by the
        # _prefixes_present control arm, not by this skip. Detection via a neighbour costs the
        # explanation (@cowir-overworld), so this says it directly.
        fail=$((fail+1))
        printf '  FAIL  %-54s\n' "the emitter MOVED — $src is gone from this tree"
    else
        printf '  SKIP  %-54s (not in a git tree; the chain always is)\n' "emitter prefixes still exist"
    fi

    echo
    echo "selftest: ${pass} passed, ${fail} failed"
    [ "$fail" -eq 0 ]
}

case "${1:-}" in
    --selftest) selftest ;;
    ''|-*)      echo "usage: $0 <smoke-log> | --selftest" >&2; exit 2 ;;
    *)          report "$1" ;;
esac
