#!/usr/bin/env bash
# Gate the suite so the VERDICT is consumed, not just displayed.
# Piping the runner (sed/grep/head) discards its exit code — the shaping
# command's status wins. Capture first, shape second, decide on the capture.
set -uo pipefail
LOG="${1:-tmp/gate.log}"
mkdir -p "$(dirname "$LOG")"
tools/run_tests.sh > "$LOG" 2>&1
EC=$?
sed -i 's/\x1b\[[0-9;]*m//g' "$LOG"
grep -A7 "^---- Totals" "$LOG" | grep -E "Scripts|Tests|Passing|Failing|Risky"
# GUT prints each failure TWICE (inline at the test, then again in the
# end-of-run failing-tests block), so a [Failed] line count is exactly 2x the
# true number (@cowir-controller msg-3435). Valid as a boolean, a lie as a
# cardinal. Report the authoritative Failing N from Totals; keep the line
# count only as a corroborating non-zero signal, labelled as lines.
FAILLINES=$(grep -c '\[Failed\]' "$LOG")
FAILED=$(grep -A9 "^---- Totals" "$LOG" | grep -oE "^ +Failing +[0-9]+" | grep -oE "[0-9]+" | tail -1)
FAILED=${FAILED:-0}
# Vacuity floor (@cowir-sfx entry 6, STALE READ): a file-based gate counts
# [Failed] from whatever the log holds. A crashed or empty run yields 0 and
# reads exactly like a clean one. Require proof THIS run produced a real suite.
TOTALS=$(grep -c "^---- Totals" "$LOG")
RAN=$(grep -oE "^Tests +[0-9]+" "$LOG" | grep -oE "[0-9]+" | tail -1)
RAN=${RAN:-0}
echo "exit=$EC  failing=$FAILED (authoritative)  [Failed]-lines=$FAILLINES (2x by design)  totals-blocks=$TOTALS  tests-run=$RAN"
if [ "$TOTALS" -eq 0 ] || [ "$RAN" -lt 1000 ]; then
	echo "GATE: RED — log has no Totals block or ran only $RAN tests; the run did not complete, so [Failed]=$FAILED means nothing"; exit 1
fi
# Two independent signals must agree; disagreement is itself a failure.
if [ "$EC" -ne 0 ] || [ "$FAILED" -ne 0 ]; then
	echo "GATE: RED — do not push"; exit 1
fi
echo "GATE: GREEN"
