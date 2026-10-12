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

# Order-preserving: one pass, so the lines arrive as the run produced them (wipe/FAIL before the
# VERDICT) rather than in an order this script invents.
_PAT='^\[SMOKE\] (VERDICT:|FAIL:|wipe:)'

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
        local sites miss=0 pfx
        sites="$(command grep -ac '^[^#]*print("\[SMOKE\] \(VERDICT:\|FAIL:\|wipe:\)' "$src" || true)"
        case "$sites" in ''|*[!0-9]*) sites=0 ;; esac
        for pfx in 'VERDICT:' 'FAIL:' 'wipe:'; do
            # ⛔ THE QUIET DIRECTION, AND IT IS THE DANGEROUS ONE. This asks "does the emitter
            # still print this prefix", and a COMMENT mentioning the prefix answers YES. Measured:
            # a file whose only FAIL: mention is `# the gate greps for print("[SMOKE] FAIL: …")`
            # reported present=1 with real prints=0 — the dead-pattern guard passes while the
            # extraction matches nothing. Same class as @cowir-music's phantom, opposite
            # direction: theirs reds loudly, this one goes green and certifies a dead pattern.
            command grep -aq "^[^#]*print(\"\[SMOKE\] ${pfx}" "$src" || {
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
        local others; others="$(command grep -aoE 'print\("\[SMOKE\] [A-Za-z_]+' "$src" \
            | sed -E 's/.*\[SMOKE\] //' | sort -u | command grep -avE '^(VERDICT|FAIL|wipe)$' | tr '\n' ' ')"
        printf '  info  other [SMOKE] kinds in the emitter: %s\n' "${others:-none}"
    else
        printf '  SKIP  %-54s (no %s from this cwd)\n' "emitter prefixes still exist" "$src"
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
