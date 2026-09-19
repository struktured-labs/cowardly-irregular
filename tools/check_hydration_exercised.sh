#!/usr/bin/env bash
# Did the real-save hydration test actually RUN, or did it self-skip?
#
# WHY THIS EXISTS
# ---------------
# `test_real_saves_hydrate_smoke.gd` hydrates every save on the machine through the state layer,
# so "Continue" is not the first place an aged save meets new load code. It reads `user://saves/`,
# so with an empty sandbox it calls `pending()` and scores Risky/Pending instead of failing:
#
#     empty sandbox    Tests 2 · Passing none · Risky/Pending 2 · Asserts 0
#     seeded sandbox   Tests 2 · Passing 2    · Asserts 124
#
# ⛔ NEITHER OUTCOME IS A FAILURE, which is the whole problem. A deploy that never exercised it
# reports the same `failing=0` as one that did, and no cardinal in the evidence line can tell them
# apart. tools/seed_gate_saves.sh was written to fix that by copying his saves in.
#
# ⛔ AND THE SEEDING ALONE DOES NOT FIX IT. Measured on v3.33.371-alpha's archived logs:
#
#     [deploy] gate 1: SKIPPED — already gated by the fold: scripts=1919 … failing=0
#     [seed]   7 save(s) copied into the gate sandbox — real-save hydration will RUN.
#
# The seed ran and the suite that reads it did not. `VERDICT=SKIP` is the normal path — the fold
# gates every tag — so the coverage the seeder exists for has not happened on a normal publish.
# The seeder's own message said "will RUN" while the suite was being skipped four lines above it.
#
# So the deploy runs that ONE file against the seeded sandbox and asserts here that it was
# exercised. Pinned on VALUES from the run, never on the test's prose: a reworded pending()
# message must not turn this green.
#
# Usage:  tools/check_hydration_exercised.sh <gut-log>
#         tools/check_hydration_exercised.sh --selftest
# Exit:   0 exercised · 5 self-skipped (sandbox not seeded) · 2 cannot evaluate
set -uo pipefail

check() {
    local log="$1"
    [ -n "$log" ] || { echo "[hydra] BLOCKED: no log path given." >&2; return 2; }
    [ -f "$log" ] || { echo "[hydra] BLOCKED: ${log} does not exist — a check that cannot read its subject is not a passing one." >&2; return 2; }

    # A Totals block is the proof the run COMPLETED. Without it the numbers below are absences,
    # not zeros, and an absence must never read as "nothing pended".
    local totals; totals=$(command grep -ac '^---- Totals' "$log" || true)
    if [ "${totals:-0}" -eq 0 ]; then
        echo "[hydra] BLOCKED: ${log} has no Totals block — the run did not complete, so it says" >&2
        echo "        nothing about whether hydration was exercised." >&2
        return 2
    fi

    local asserts pending
    # ANCHOR THE END, NOT ONLY THE START. `^Asserts +[0-9]+` also matches game prose printed
    # at column 0 -- e.g. `Asserts 0 damage when the ward holds` -- and `tail -1` then PREFERS
    # the prose, because prose comes after the Totals block. Both directions were produced on
    # 2026-09-19, not reasoned:
    #     healthy run, 124 asserts + that prose line  -> extracted 0   -> EC=5, BLOCKED a publish
    #     vacuous run,   0 asserts + `Asserts 999 ...` -> extracted 999 -> EC=0, PASSED a run
    #                                                     that exercised nothing
    # The second is the one that matters: the gate exists to refuse a vacuous hydration run and
    # a sentence can talk it into passing. A Totals row is the key, whitespace, a number and
    # NOTHING ELSE, so requiring the end anchor separates them.
    #
    # LATENT, and measured rather than claimed: across 3,004 archived publish logs there are 196
    # `^Asserts N` lines and ZERO that are not pure Totals rows. No release was ever mis-gated.
    # ⚠️ Residual, stated rather than closed: a prose line that is EXACTLY `Asserts 7` still
    # matches. That is a far narrower surface than "begins with the word", and it is vocabulary
    # luck rather than structure -- the same thing this comment is fixing, one size smaller.
    asserts=$(command grep -aoE '^Asserts[[:space:]]+[0-9]+[[:space:]]*$' "$log" | command grep -aoE '[0-9]+' | tail -1)
    pending=$(command grep -aoE '^[[:space:]]*Risky/Pending[[:space:]]+[0-9]+[[:space:]]*$' "$log" | command grep -aoE '[0-9]+' | tail -1)
    asserts="${asserts:-0}"; pending="${pending:-0}"

    if [ "$pending" -gt 0 ]; then
        echo "[hydra] BLOCKED: the real-save hydration test SELF-SKIPPED (Risky/Pending ${pending})." >&2
        echo "        It reads user://saves/ and found none, so this build shipped with aged-save" >&2
        echo "        loading UNEXERCISED — and it reports failing=0 either way." >&2
        echo "        Fix: seed the gate sandbox (tools/seed_gate_saves.sh) before this runs." >&2
        return 5
    fi
    if [ "$asserts" -lt 1 ]; then
        echo "[hydra] BLOCKED: the run completed with ${asserts} asserts — nothing was exercised." >&2
        return 5
    fi
    echo "[hydra] real-save hydration EXERCISED: ${asserts} assert(s), 0 pending."
    return 0
}

selftest() {
    local pass=0 fail=0 d; d="$(mktemp -d "${TMPDIR:-/tmp}/hydra.XXXXXX")"
    _eq() {
        if [ "$2" = "$3" ]; then printf '  ok    %-54s %s\n' "$1" "$2"; pass=$((pass+1))
        else printf '  FAIL  %-54s got %s want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
    }
    # The two real shapes, transcribed from seed_gate_saves.sh's measured header and from a real
    # archived gate log's Totals block -- not invented.
    printf '%s\n' '---- Totals ----' 'Scripts           1' 'Tests             2' '  Passing         2' 'Asserts           124' 'Time              9.1s' > "$d/seeded.log"
    printf '%s\n' '[Pending]:  no local saves on this machine' '---- Totals ----' 'Scripts           1' 'Tests             2' '  Passing         0' '  Risky/Pending   2' 'Asserts           0' > "$d/empty.log"
    printf '%s\n' 'Godot Engine v4.4.1' 'SCRIPT ERROR: something died' > "$d/killed.log"

    check "$d/seeded.log" >/dev/null 2>&1; _eq "a seeded run is EXERCISED"              "$?" "0"
    check "$d/empty.log"  >/dev/null 2>&1; _eq "a self-skipped run BLOCKS"              "$?" "5"
    check "$d/killed.log" >/dev/null 2>&1; _eq "no Totals block CANNOT EVALUATE"        "$?" "2"
    check "$d/nope.log"   >/dev/null 2>&1; _eq "an absent log CANNOT EVALUATE"          "$?" "2"
    check ""              >/dev/null 2>&1; _eq "no argument CANNOT EVALUATE"            "$?" "2"

    local out
    out="$(check "$d/empty.log" 2>&1)"
    case "$out" in *"SELF-SKIPPED"*) _eq "  ...and says it self-skipped" yes yes ;;
                   *) _eq "  ...and says it self-skipped" no yes ;; esac
    case "$out" in *"failing=0 either way"*) _eq "  ...and names why failing=0 hid it" yes yes ;;
                   *) _eq "  ...and names why failing=0 hid it" no yes ;; esac

    # ⛔ A COMPLETED RUN WITH ZERO ASSERTS IS NOT A PASS. Pending is one way to exercise nothing;
    # it is not the only one, and gating solely on Risky/Pending would green a vacuous run.
    printf '%s\n' '---- Totals ----' 'Scripts           1' 'Tests             2' '  Passing         2' 'Asserts           0' > "$d/vacuous.log"
    check "$d/vacuous.log" >/dev/null 2>&1; _eq "a completed run with 0 asserts BLOCKS" "$?" "5"

    # ⛔ GAME PROSE AT COLUMN 0 MUST NOT BE READ AS A TOTALS ROW. `^Asserts +[0-9]+` matches
    # `Asserts 0 damage when the ward holds`, and `tail -1` prefers it because prose comes
    # AFTER the block. Both arms are required and they fail in opposite directions:
    #   the first  -- a healthy run would BLOCK a publish on a sentence  (false RED)
    #   the second -- a VACUOUS run would PASS because a sentence claimed a number (false GREEN)
    # The second is the one the gate exists to prevent, so an arm that only covered the first
    # would pin the cheaper half. Latent when written: 0 such lines in 3,004 archived logs.
    printf '%s\n' '---- Totals ----' 'Scripts           1' 'Tests             2' '  Passing         2' 'Asserts           124' 'Time              9.1s' 'Asserts 0 damage when the ward holds' > "$d/prose_after.log"
    check "$d/prose_after.log" >/dev/null 2>&1; _eq "prose after Totals does NOT mask a real count" "$?" "0"

    printf '%s\n' '---- Totals ----' 'Scripts           1' 'Tests             2' '  Passing         2' 'Asserts           0' 'Asserts 999 hitpoints were restored' > "$d/prose_vacuous.log"
    check "$d/prose_vacuous.log" >/dev/null 2>&1; _eq "prose cannot talk a VACUOUS run into passing" "$?" "5"

    # ⚠️ The same anchor flaw lives on the pending extraction, so it gets its own arm rather
    # than riding on the asserts one -- two extractions, two ways to be wrong.
    # ⛔ THE ASSERT COUNT HERE IS 124 ON PURPOSE. The first version of this arm used 0, so the
    # gate returned 5 from the ASSERTS path whatever the pending extraction did -- it passed
    # against a reverted pending fix and pinned nothing. Mutating the pending pattern alone
    # red nothing, which is how it was caught. A healthy count is what forces the verdict to
    # come from the pending path and nowhere else.
    printf '%s\n' '---- Totals ----' 'Scripts           1' 'Tests             2' '  Passing         0' '  Risky/Pending   2' 'Asserts           124' 'Risky/Pending 0 reason the ward held' > "$d/prose_pending.log"
    check "$d/prose_pending.log" >/dev/null 2>&1; _eq "prose cannot mask a self-SKIP"               "$?" "5"

    # ⚠️ PINNED ON VALUES, NOT PROSE. The test's pending() wording is not load-bearing here --
    # reword it and this must still block, or the guard tracks a string instead of an outcome.
    printf '%s\n' '[Pending]:  ZZ totally different wording ZZ' '---- Totals ----' 'Scripts           1' 'Tests             2' '  Risky/Pending   2' 'Asserts           0' > "$d/reworded.log"
    check "$d/reworded.log" >/dev/null 2>&1; _eq "a REWORDED pending still BLOCKS"      "$?" "5"

    # and the floor: the seeded shape must not block for some unrelated reason
    out="$(check "$d/seeded.log" 2>&1)"
    case "$out" in *"124 assert"*) _eq "  FLOOR: the pass names the assert count" yes yes ;;
                   *) _eq "  FLOOR: the pass names the assert count" no yes ;; esac

    rm -rf "$d"
    printf '\nselftest: %s passed, %s failed\n' "$pass" "$fail"
    [ "$fail" -eq 0 ]
}

case "${1:-}" in
    --selftest) selftest; exit $? ;;
    *) check "${1:-}"; exit $? ;;
esac
