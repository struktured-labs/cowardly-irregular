#!/usr/bin/env bash
# Emit only the CODE lines of a GDScript file: no `#` comments, no `"""` regions.
#
# WHY THIS EXISTS, AND WHY IT IS ONE FILE
# ---------------------------------------
# A source-scanning guard makes PROSE in the scanned file load-bearing. @cowir-music measured the
# cheapest instance: they wrote `add_status("literal")` in a comment explaining that guards key on
# that shape, and a guard extracted `literal` as a real status. @cowir-battle's census: 691 guards
# read src/ as text, 454 of them RAW — a comment in the subject file is input to every one.
#
# ⛔ AND THE DIRECTION DECIDES THE COST (@cowir-story's split, which is the useful part):
#     the extracted set is what you assert ABOUT   -> a phantom REDS      -> a rephrase
#     the extracted set is ACCEPTANCE              -> a phantom SATISFIES -> a defect ships
# My smoke_report.sh prefix check is the second kind: it asks "does the emitter still print this",
# and prose answered YES while the real print count was 0 — a dead pattern reading as alive.
#
# The repo's GdSource helper already does this properly, quote- AND escape-aware, with 228
# consumers — and it is GDScript, unreachable from a shell tool. @cowir-battle enumerated NINE
# private strippers in the test tree and @cowir-ai found two more of their own, with the lesson
# that a private copy cannot inherit a fix to the shared one. So this is ONE shared helper for the
# shell tools rather than a copy inside each, and it is the bash analogue of GdSource — not a
# replacement for it, and not to be duplicated.
#
# ⚠️ WHAT IT CLOSES, MEASURED, AND WHAT IT DOES NOT:
#   closes  a `#` comment, full-line or trailing
#   closes  a multi-line `"""` region   (the shape that defeated a private split("#")[0])
#   closes  a single-line `"""..."""`  span
#   OPEN    a `#` or `"""` inside an ordinary string literal on the same line
# The open case fails toward DROPPING the line, so a real site goes missing rather than a phantom
# being admitted. For a requirement set that reds loudly; for an acceptance set it reds loudly too,
# because the prefix then reads as absent. Both directions are loud, which is the trade this form
# is chosen for.
#
# Usage:  . tools/gd_code_lines.sh  ->  gd_code_lines <file>
#         tools/gd_code_lines.sh --selftest
set -uo pipefail

gd_code_lines() {
    [ -r "${1:-}" ] || return 1
    awk '
      {
        line = $0
        n = gsub(/"""/, "&")          # count, without mutating meaning
        if (indoc) { if (n % 2 == 1) indoc = 0; next }
        if (n % 2 == 1) { indoc = 1; next }
        # ⛔ `[^"]*` CANNOT CROSS THE QUOTES INSIDE THE PROSE. My first version used it and the
        # arm red: `"""inline doc with print("[SMOKE] FAIL: z")"""` contains `"` characters, so
        # the span never matched and the line survived WITH its prose. Greedy `.*` spans it.
        # A line carrying code between two separate doc spans loses that code — rare, and it
        # fails toward dropping, which is the loud direction for both set kinds.
        gsub(/""".*"""/, "", line)    # a span that opens and closes on one line
        sub(/#.*/, "", line)
        print line
      }' "$1"
}

_selftest() {
    local pass=0 fail=0 d out
    d="$(mktemp -d "${TMPDIR:-${PWD}/tmp}/gdcode.XXXXXX")"
    trap "rm -rf '$d'" EXIT
    {   printf 'func _verdict():\n'
        printf '\t# the gate greps for print("[SMOKE] FAIL: x") so keep it\n'
        printf '\t"""\n'
        printf '\tand the docstring also says print("[SMOKE] FAIL: y")\n'
        printf '\t"""\n'
        printf '\t"""inline doc with print("[SMOKE] FAIL: z")"""\n'
        printf '\tprint("[SMOKE] VERDICT: %%s" %% v)   # a trailing comment\n'
        printf '\tprint("[SMOKE] wipe: game over after %%.1fs" %% t)\n'
    } > "$d/f.gd"
    out="$(gd_code_lines "$d/f.gd")"

    chk() { local name="$1" pat="$2" want="$3"
        if printf '%s' "$out" | command grep -aq -- "$pat"; then
            [ "$want" -eq 0 ] && { pass=$((pass+1)); printf '  ok    %-52s\n' "$name"; return; }
        else
            [ "$want" -eq 1 ] && { pass=$((pass+1)); printf '  ok    %-52s\n' "$name"; return; }
        fi
        fail=$((fail+1)); printf '  FAIL  %-52s (/%s/ want %s)\n' "$name" "$pat" "$want"; }

    chk "a # comment is dropped"                     'FAIL: x'              1
    chk "a multi-line \"\"\" region is dropped"      'FAIL: y'              1
    chk "a single-line \"\"\"...\"\"\" span is dropped" 'FAIL: z'           1
    # ⛔ THE MUST-SURVIVE CONTROL, which GdSource's own header demands: over-stripping and a
    # correct strip are the SAME GREEN on the three arms above. Without this, returning nothing
    # at all would pass them.
    chk "a real code site SURVIVES"                  'VERDICT'              0
    chk "...and its trailing comment is gone"        'a trailing comment'   1
    # ⛔ A FLOOR THAT NAMES ONE LINE IS GAMED BY A MUTANT THAT READ IT. @cowir-overworld measured
    # this on their own file and I then measured it here: a stripper emitting ONLY the line the
    # must-survive arm names passed five of six arms, and the one that caught it was
    # "its trailing comment is gone" — true, and pointing at comment handling rather than at a
    # stripper returning one line of eight. Detection by a sibling arm costs you the EXPLANATION
    # even when it costs no coverage.
    #
    # So the floor is PROPORTIONAL, over MULTIPLE sites: every code `print(` in the input must
    # survive, counted. A mutant must then preserve essentially all code to pass — which is the
    # correct behaviour. [[a-factorial-with-a-missing-cell]]
    local want_prints got_prints
    want_prints=2   # the two real code prints in the fixture above; the other three are prose
    got_prints="$(printf '%s' "$out" | command grep -ac 'print(')"
    if [ "${got_prints:-0}" -eq "$want_prints" ]; then
        pass=$((pass+1)); printf '  ok    %-52s (%s/%s)\n' "EVERY code print survives, counted" "$got_prints" "$want_prints"
    else
        fail=$((fail+1)); printf '  FAIL  %-52s (%s, want %s — the strip ate or kept too much)\n' "code prints surviving" "${got_prints:-0}" "$want_prints"
    fi

    echo; echo "selftest: ${pass} passed, ${fail} failed"
    [ "$fail" -eq 0 ]
}

# ⛔ A SOURCEABLE FILE MUST NOT ACT ON THE CALLER'S ARGUMENTS. This was
#     case "${1:-}" in --selftest) _selftest ;; esac
# and when smoke_report.sh sourced it while ITS OWN $1 was --selftest, the positional parameters
# were the caller's — so this file ran its own selftest inside the caller, installed an EXIT trap
# over the caller's cleanup, and three of the caller's arms failed with a verdict about the
# EMITTER ("the emitter no longer prints [SMOKE] VERDICT:") that had nothing to do with the
# emitter. Measured: the same patterns matched 1/17/1 when run by hand, which is what said the
# fault was in the plumbing and not in the derivation.
#
# The guard below dispatches only when this file IS the program. Sourcing it now defines the
# function and does nothing else, whatever the caller's arguments are.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    case "${1:-}" in
        --selftest) _selftest ;;
        *) echo "usage: . $0  ->  gd_code_lines <file>   |   $0 --selftest" >&2; exit 2 ;;
    esac
fi
