#!/usr/bin/env bash
# What cues did this publish's render smoke actually fire?
#
# WHY THIS REPORTS A SET AND NOT A COMPLEMENT
# -------------------------------------------
# The obvious tool here lists "authored but never observed". @cowir-music measured why that is the
# wrong product: of 23 authored `status_*` cues, 14 are reachable by some live path and 9 are not —
# and the render smoke drives ONE battle, ONE duel and NO group action, so a "not observed" list
# would name far more than 9, with the excess being smoke coverage rather than defects. Their
# sentence is the design constraint: "a reader who sees a 19-line list will not keep your caveat in
# mind by line 12."
#
# So this prints the OBSERVED SET, which is a fact about a run, and nothing about absence. The
# finding is the INTERSECTION with a static reachability audit (authored ∧ not observed ∧ no static
# path reaches it) — @cowir-music owns that third term for the `status_` family, because
# `test_sfx_reverse_orphan_audit` declares itself blind there: by its own note it credits every
# `status_*` key as reachable on the strength of the literal `"status_" +` construction in
# SoundManager. An over-admitting list reads as thoroughness. [[a-false-admission-is-silent]]
#
# ⚠️ REQUIRES COWIR_SFX_LOG_CUES=1, which deploy_web.sh sets on SMOKE_CMD from v3.33.661-alpha. A
# log from before that has three [SFX] startup lines and no per-cue lines, and reporting an almost
# empty set from it would be the false-clean this file exists to avoid — so an untraced log is
# named as such and NOT reported as a set.
#
# Usage:  tools/cue_trace.sh <smoke-log> [more-logs...]
#         tools/cue_trace.sh --selftest
# Exit:   0 reported · 2 usage / unreadable · 3 no log carried cue tracing
set -uo pipefail

# The two traced forms, from SoundManager (`if log_cues:` at :995 and :1018, procedural at :1784):
#   [SFX] <requested> -> <resolved> pitch=<f> (<player>)
#   [SFX] procedural <type> freq=<f> dur=<d> (<player>)
# The startup lines ("Loaded sfx manifest", "Derived N ability cues") match neither, which is what
# makes "was tracing on?" an exact question rather than a threshold on line count.
_TRACED='^\[SFX\] [^ ]+ -> [^ ]+ pitch='
_PROC='^\[SFX\] procedural '

report() {
    local traced=0 logs=0 f
    local tmp; tmp="$(mktemp -d "$PWD/tmp/cuetrace.XXXXXX" 2>/dev/null || mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN
    : > "$tmp/pairs"
    for f in "$@"; do
        [ -f "$f" ] || { echo "[cue] BLOCKED: ${f} does not exist" >&2; return 2; }
        logs=$((logs+1))
        local n
        n="$(command grep -acE -- "$_TRACED" "$f" || true)"
        case "$n" in ''|*[!0-9]*) n=0 ;; esac
        if [ "$n" -eq 0 ]; then
            echo "[cue] ${f##*/}: no per-cue lines — this log was produced WITHOUT COWIR_SFX_LOG_CUES=1"
            echo "[cue]   (deploy_web.sh sets it on SMOKE_CMD from v3.33.661-alpha). Not reporting a set"
            echo "[cue]   from it: an almost-empty set would read as 'these cues never fired'."
            continue
        fi
        traced=$((traced+1))
        # requested<TAB>resolved
        command grep -aoE -- "$_TRACED[^ ]*" "$f" \
            | sed -E 's/^\[SFX\] ([^ ]+) -> ([^ ]+) pitch=.*/\1\t\2/' >> "$tmp/pairs"
        command grep -aoE -- "$_PROC[^ ]+" "$f" \
            | sed -E 's/^\[SFX\] procedural ([^ ]+).*/procedural:\1\tprocedural:\1/' >> "$tmp/pairs" || true
    done
    [ "$traced" -gt 0 ] || { echo "[cue] no log carried cue tracing — nothing to report" >&2; return 3; }

    echo "[cue] OBSERVED in ${traced} of ${logs} log(s). This is what ran, not what exists."
    local total uniq
    total="$(wc -l < "$tmp/pairs")"
    cut -f1 "$tmp/pairs" | sort -u > "$tmp/keys"
    uniq="$(wc -l < "$tmp/keys")"
    echo "[cue]   ${total} cue play(s), ${uniq} distinct key(s)"
    sort "$tmp/pairs" | uniq -c | sort -rn | head -40 | sed 's/^/        /'

    # A cue that RESOLVED to a different key splits into two populations, and conflating them is
    # how this tool nearly handed @cowir-music fourteen false positives on its first real run.
    #
    # ⛔ MEASURED on 259 archived publishes: every single resolution difference was a VARIANT —
    # footstep_grass -> footstep_grass_v2, ability_heal -> ability_heal_v3, buff -> buff_v2. That
    # is the manifest's round-robin variation working, not a cue going missing. My fixture used
    # status_exposed -> debuff_generic, a genuine substitution, so the variant case never appeared
    # in a test and the warning header said "authored cue, something else played" over fourteen
    # rows of correct behaviour. A reader would have read them as defects — the same
    # over-admission I wrote this file to avoid, arriving from the other direction.
    # [[a-false-admission-is-silent]]
    #
    # SUBSTITUTION is the finding: the resolved key is not the requested one and not a _vN sibling
    # of it, so a DIFFERENT sound played. @cowir-music's Memory-Leak-reaching-the-generic-blip is
    # this shape, and it is audible.
    local subs vars
    vars="$(awk -F'\t' '$1 != $2 && $2 ~ "^"$1"_v[0-9]+$"' "$tmp/pairs" | sort -u | wc -l)"
    subs="$(awk -F'\t' '$1 != $2 && $2 !~ "^"$1"_v[0-9]+$"' "$tmp/pairs" | sort -u)"
    if [ -n "$subs" ]; then
        echo "[cue]   ⚠️ SUBSTITUTED — a DIFFERENT cue played than the one asked for:"
        printf '%s\n' "$subs" | sed 's/^/        /'
    else
        echo "[cue]   no substitutions: every cue resolved to itself or to a _vN variant of itself"
    fi
    [ "${vars:-0}" -gt 0 ] && echo "[cue]   (${vars} variant rotation(s) like key -> key_v2, which is the manifest working)"

    # The coverage bound, DERIVED from the log rather than asserted, so the artifact carries it.
    local f1="$1" shots battles group
    shots="$(command grep -ac 'saved err=0' "$f1" || true)"
    battles="$(command grep -ac 'Battle commenced\|=== DEFEAT ===\|duel' "$f1" || true)"
    group="$(command grep -aci 'group' "$f1" || true)"
    echo "[cue]   COVERAGE of ${f1##*/}: ${shots} shot(s), ${battles} battle marker(s), ${group} 'group' mention(s)."
    echo "[cue]   A key absent from the set above may simply be on a path the smoke never walks."
    return 0
}

selftest() {
    local pass=0 fail=0 self dir out
    self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
    mkdir -p tmp
    # Inside the repo on purpose: a fixture under ${TMPDIR:-/tmp} is how reap_probe.sh came to pass
    # 17/17 by hand and fail 3 arms in the chain — my own TMPDIR had supplied a precondition.
    # [[the-harness-supplies-what-the-file-lacks]]
    dir="$(mktemp -d "$PWD/tmp/cuetrace_test.XXXXXX")"
    # shellcheck disable=SC2064
    trap "rm -rf '$dir'" EXIT

    chk() { local name="$1" pat="$2" want="$3"
        if printf '%s' "$out" | command grep -aq -- "$pat"; then
            [ "$want" -eq 0 ] && { pass=$((pass+1)); printf '  ok    %-56s\n' "$name"; return; }
        else
            [ "$want" -eq 1 ] && { pass=$((pass+1)); printf '  ok    %-56s\n' "$name"; return; }
        fi
        fail=$((fail+1)); printf '  FAIL  %-56s (/%s/ want %s)\n' "$name" "$pat" "$want"; }

    # An UNTRACED log: three startup lines, no per-cue lines. Must be NAMED, not reported.
    {   printf '[SFX] Loaded sfx manifest: 951 sounds\n'
        printf '[SFX] Derived 101 ability cues from abilities.json (hand map: 25)\n'
        printf '[SMOKE] cave saved err=0\n'
    } > "$dir/untraced.log"
    out="$("$self" "$dir/untraced.log" 2>&1)"; local ec=$?
    chk "an untraced log is NAMED as untraced"            'WITHOUT COWIR_SFX_LOG_CUES' 0
    chk "...and no set is printed from it"                 'OBSERVED in'                1
    [ "$ec" -eq 3 ] && { pass=$((pass+1)); printf '  ok    %-56s\n' "...and it exits 3, not 0"; } \
        || { fail=$((fail+1)); printf '  FAIL  %-56s (exit %s)\n' "an untraced log exits 3" "$ec"; }

    # A TRACED log. One cue resolves to itself, one falls back, one is procedural.
    {   printf '[SFX] Loaded sfx manifest: 951 sounds\n'
        printf '[SFX] menu_select -> menu_select pitch=1.00 (SFXPlayer1)\n'
        printf '[SFX] menu_select -> menu_select pitch=1.00 (SFXPlayer2)\n'
        printf '[SFX] status_exposed -> debuff_generic pitch=0.95 (SFXPlayer3)\n'
        printf '[SFX] procedural blip freq=440 dur=0.1 (SFXPlayer4)\n'
        printf '[SMOKE] cave saved err=0\n'
        printf 'Battle commenced\n'
    } > "$dir/traced.log"
    out="$("$self" "$dir/traced.log" 2>&1)"
    chk "a traced log reports the observed set"            'OBSERVED in 1 of 1'         0
    chk "...with the distinct key count"                   '3 distinct key(s)'          0
    chk "...naming a key that fired"                       'menu_select'                0
    chk "...and the procedural form too"                   'procedural:blip'            0
    chk "a SUBSTITUTION is flagged"                        'SUBSTITUTED'                0
    chk "...naming both sides of it"                       'status_exposed.*debuff_generic' 0
    chk "the coverage bound is printed"                    'COVERAGE of traced.log'     0
    chk "...and it does NOT print an absence list"         'never observed'             1

    # ⛔ THE ARM THIS TOOL WAS MISSING, AND REAL DATA SUPPLIED IT: a _vN variant is the manifest
    # rotating, not a cue going missing. 259 archived publishes contained ONLY variants, so the
    # first real run would have printed fourteen rows of correct behaviour under a warning.
    {   printf '[SFX] footstep_grass -> footstep_grass_v2 pitch=1.00 (SFXPlayer1)\n'
        printf '[SFX] ability_heal -> ability_heal_v3 pitch=1.00 (SFXPlayer2)\n'
    } > "$dir/variants.log"
    out="$("$self" "$dir/variants.log" 2>&1)"
    chk "a _vN variant is NOT called a substitution"       'SUBSTITUTED'                1
    chk "...it is counted as rotation"                     'variant rotation'           0
    chk "...and the positive line says so"                 'resolved to itself or to a _vN' 0
    # ...and a variant must not MASK a real substitution in the same log.
    {   cat "$dir/variants.log"
        printf '[SFX] status_exposed -> debuff_generic pitch=1.00 (SFXPlayer3)\n'
    } > "$dir/mixed.log"
    out="$("$self" "$dir/mixed.log" 2>&1)"
    chk "a variant does not hide a substitution beside it" 'status_exposed.*debuff_generic' 0
    chk "...and the rotation count still prints"           'variant rotation'           0

    # CONTROL: with neither, the substitution section must NOT appear — otherwise the arm above
    # passes on any input and says nothing about the detector.
    {   printf '[SFX] menu_select -> menu_select pitch=1.00 (SFXPlayer1)\n'; } > "$dir/clean.log"
    out="$("$self" "$dir/clean.log" 2>&1)"
    chk "no substitution -> the warning is absent"         'SUBSTITUTED'                1
    chk "...and it says so positively"                     'no substitutions'           0

    # Several logs: the union, with the untraced one counted but not reported.
    out="$("$self" "$dir/traced.log" "$dir/untraced.log" "$dir/clean.log" 2>&1)"
    chk "a mixed set says how many logs carried tracing"  'OBSERVED in 2 of 3'         0

    out="$("$self" "$dir/nope.log" 2>&1)"; local ec2=$?
    [ "$ec2" -eq 2 ] && { pass=$((pass+1)); printf '  ok    %-56s\n' "a missing log exits 2"; } \
        || { fail=$((fail+1)); printf '  FAIL  %-56s (exit %s)\n' "a missing log exits 2" "$ec2"; }

    echo; echo "selftest: ${pass} passed, ${fail} failed"
    [ "$fail" -eq 0 ]
}

case "${1:-}" in
    --selftest) selftest ;;
    ''|-*)      echo "usage: $0 <smoke-log> [more-logs...] | --selftest" >&2; exit 2 ;;
    *)          report "$@" ;;
esac
