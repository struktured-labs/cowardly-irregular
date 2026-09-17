#!/usr/bin/env bash
# Read a gate log and decide. Four cardinals, because each is blind to what the others see.
#
#   EC                a run that aborted before its first assert still EXITS ZERO (cowir-music,
#                     2026-09-16) — GUT scores Risky as not-failing, so EC alone passes a guard
#                     that has stopped guarding.
#   Scripts           == authored, or the run measured a subset and said nothing.
#   Failing           the only exact cardinal GUT prints for real failures.
#   Risky/Pending     arms that asserted NOTHING. An abort before the first assert lands here and
#                     nowhere else. Compared against a baseline rather than required to be 0,
#                     because some tests pend deliberately and say why in their skip text.
#   Asserts           printed for the record: a corpus going inert collapses this by 20-40% while
#                     every other cardinal holds still. Small deltas are noise (±2 measured on an
#                     unchanged 29-file radius), so this is reported, never gated.
set -uo pipefail
LOG="${1:?usage: gate_verdict.sh <gate.log> <ec> [risky-baseline]}"
EC="${2:?usage: gate_verdict.sh <gate.log> <ec> [risky-baseline]}"
RISKY_MAX="${3:-0}"
[ -r "$LOG" ] || { echo "gate_verdict: cannot read $LOG" >&2; exit 2; }

_num() { command grep -aE "$1" "$LOG" | tail -1 | command grep -aoE '[0-9]+' | tail -1; }
SCRIPTS=$(_num '^Scripts'); TESTS=$(_num '^Tests'); PASSING=$(_num '^  Passing')
FAILING=$(_num '^  Failing'); RISKY=$(_num '^  Risky'); ASSERTS=$(_num '^Asserts')
AUTHORED=$(ls test/unit/test_*.gd | wc -l)
: "${FAILING:=0}" "${RISKY:=0}"

# A Totals block that never printed is the vacuity case the wrapper exits 3 for; if the numbers
# are absent here, nothing below can be evaluated and a missing value must not read as a zero.
[ -n "${SCRIPTS:-}" ] && [ -n "${TESTS:-}" ] || {
    echo "GATE: NO TOTALS — the run printed no Scripts/Tests. Discard it; EC was $EC." >&2; exit 3; }

VACUITY=$(command grep -ac 'NOT ALL TEST FILES RAN\|NOT ALL REQUESTED FILES RAN\|DISCARD THIS RUN' "$LOG" || true)
echo "EC=$EC  Scripts $SCRIPTS/$AUTHORED  Tests $TESTS  Passing $PASSING  Failing $FAILING  Risky $RISKY  Asserts ${ASSERTS:-?}"
FAIL=0
[ "$EC" = "0" ]                || { echo "  STOP: exit code $EC" >&2; FAIL=1; }
[ "$SCRIPTS" = "$AUTHORED" ]   || { echo "  STOP: $SCRIPTS scripts ran, $AUTHORED authored — a subset" >&2; FAIL=1; }
[ "$FAILING" = "0" ]           || { echo "  STOP: $FAILING failing" >&2; FAIL=1; }
[ "$VACUITY" = "0" ]           || { echo "  STOP: the wrapper printed a discard notice" >&2; FAIL=1; }
[ "$RISKY" -le "$RISKY_MAX" ]  || { echo "  STOP: Risky $RISKY > baseline $RISKY_MAX — arms that asserted NOTHING. An abort before the first assert lands here and still exits 0; read them before raising the baseline." >&2; FAIL=1; }
test "$FAIL" = "0" || exit 1
echo "GATE: GREEN"
