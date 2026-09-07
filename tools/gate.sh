#!/usr/bin/env bash
# Gate the suite so the VERDICT is consumed, not just displayed.
# Piping the runner (sed/grep/head) discards its exit code — the shaping
# command's status wins. Capture first, shape second, decide on the capture.
set -uo pipefail
LOG="${1:-tmp/gate.log}"
# Suite selector, so the DEPLOY path can gate the isolated suite through this script instead of
# re-rolling a weaker check (cowir-deploy msg-3720: deploy_web.sh had three [Failed]-count gates,
# none consulting an exit code, guarding a public butler push).
MODE="${2:-}"
case "$MODE" in
	"")          SUITE_DIR="test/unit" ;;
	--isolated)  SUITE_DIR="test/isolated" ;;
	*) echo "usage: tools/gate.sh [log-path] [--isolated]" >&2; exit 2 ;;
esac
mkdir -p "$(dirname "$LOG")"

# PLAYER-DATA NET now lives in tools/run_tests.sh, which is CLAUDE.md's canonical command
# and the thing this script wraps. It was here first, which meant it only protected runs
# that typed `gate.sh` — cowir-sfx measured three of their own full-suite runs with no net
# because they followed the docs. Protecting the wrapper protected the path fewest runs take.

tools/run_tests.sh $MODE > "$LOG" 2>&1
EC=$?
sed -i 's/\x1b\[[0-9;]*m//g' "$LOG"
grep -A7 "^---- Totals" "$LOG" | grep -E "Scripts|Tests|Passing|Failing|Risky"
# A [Failed] line count is a VALID BOOLEAN AND NEVER A COUNT. It equals 2x
# failing ASSERTS (@cowir-controller msg-3446, correcting their own 2x-tests
# claim) — and GUT never prints a failing-assert total, so the ratio to
# Failing N is unbounded: 2:1 with one assert per test, 6:1 with three.
# Report Failing N, the only exact cardinal GUT emits.
FAILLINES=$(grep -c '\[Failed\]' "$LOG")
FAILED=$(grep -A9 "^---- Totals" "$LOG" | grep -oE "^ +Failing +[0-9]+" | grep -oE "[0-9]+" | tail -1)
FAILED=${FAILED:-0}
# Vacuity floor (@cowir-sfx entry 6, STALE READ): a file-based gate counts
# [Failed] from whatever the log holds. A crashed or empty run yields 0 and
# reads exactly like a clean one. Require proof THIS run produced a real suite.
TOTALS=$(grep -c "^---- Totals" "$LOG")
RAN=$(grep -oE "^Tests +[0-9]+" "$LOG" | grep -oE "[0-9]+" | tail -1)
RAN=${RAN:-0}
# SCOPE (@cowir-controller msg-3522): "a gate that reports a different corpus size is not
# reporting on your tree." They caught a conflicted-tree run by seeing 7272 where 7278 belonged.
# $? is silent about scope — it answers "did what ran pass", never "did the right thing run".
#
# Derived from the tree rather than remembered, so it cannot go stale and needs no state file:
# GUT's Scripts count must equal the test files on disk. A script that fails to PARSE is simply
# omitted — GUT warns and carries on — so a broken file, a conflict marker, or a missing
# class_name silently shrinks the corpus while every surviving test passes. That is precisely
# the run that exits 0 and means nothing.
SCRIPTS=$(grep -oE "^Scripts +[0-9]+" "$LOG" | grep -oE "[0-9]+" | tail -1)
SCRIPTS=${SCRIPTS:-0}
ONDISK=$(ls "$SUITE_DIR"/test_*.gd 2>/dev/null | wc -l)
LOADFAIL=$(grep -c 'does not extend GutTest\|Failed to load script' "$LOG")
# RISKY IS A THIRD OUTCOME AND THIS GATE READ TWO (@cowir-cutscenes msg-3685).
# A test that dies in setup asserts NOTHING and GUT scores it [Risky], not
# [Failed] — exit 0, failing 0, and five tests dead on main. The count was
# already in the Totals block above and was read past six times, so print the
# NAMES: a number skims, a list of test names does not. Never a hard fail —
# legitimate Risky exists (forward-compat probes that self-skip) — and
# deliberately no allowlist, because a check you can silence green is not a
# check. You can only explain it, and the explanation is the fix.
# GUT's "Risky/Pending" is ONE COMBINED counter and only half of it is actionable:
# measured 21 = 8 risky + 13 deliberate pending() skips. Labelling all 21
# "asserted nothing" would be false about 13 legitimate skips and would train
# people to ignore the line — the exact habit this exists to break. So print
# GUT's own cardinal AND the risky subset derived from unique test NAMES.
# Not from line counts: each test emits the inline and summary form, so
# [Risky]-lines is 2x and is a boolean, the same trap as [Failed].
RISKYPEND=$(grep -oE "^ +Risky/Pending +[0-9]+" "$LOG" | grep -oE "[0-9]+" | tail -1)
RISKYPEND=${RISKYPEND:-0}
NOASSERT=$(grep -oE '\[Risky\]: +[a-z_0-9]+ did not assert' "$LOG" | sort -u | wc -l)
echo "exit=$EC  failing=$FAILED (authoritative)  risky/pending=$RISKYPEND (GUT total)  asserted-nothing=$NOASSERT (named below)  [Failed]-lines=$FAILLINES (boolean only, NOT a count)  totals-blocks=$TOTALS  tests-run=$RAN"
echo "scope: scripts-run=$SCRIPTS  test-files-on-disk=$ONDISK  load-failures=$LOADFAIL"
if [ "$NOASSERT" -ne 0 ]; then
	echo "--- $NOASSERT test(s) ran and asserted NOTHING (scored Risky, never [Failed]) ---"
	grep -oE '\[Risky\]: +[a-z_0-9]+ did not assert' "$LOG" | sort -u | sed 's/^/  /'
	SETUP_ERRS=$(grep -c 'SCRIPT ERROR' "$LOG")
	[ "$SETUP_ERRS" -ne 0 ] && echo "  ^ $SETUP_ERRS SCRIPT ERROR(s) this run — a test dying in setup lands here, not in failing=$FAILED"
fi
# The PENDING half was a bare number for as long as the risky half has been named,
# and that asymmetry cost a day: 4 lanes read "risky/pending=14" past ~25 gate runs
# without once learning that 12 of them are LLM-absence tests skipping because
# Ollama happens to be running on this box. A deliberate skip is legitimate; a skip
# whose CONDITION is ambient machine state is a coverage hole wearing a green tick.
# Print the reasons, deduped, for the same reason the risky half is printed: a number
# gets skimmed and a sentence does not. Never a hard fail — pending() is a real tool.
PENDNAMES=$(grep -aoE '\[Pending\]: *.*' "$LOG" | sed 's/\[Pending\]: *//' | sort -u)
PENDCOUNT=$(printf '%s\n' "$PENDNAMES" | grep -c . || true)
if [ "${PENDCOUNT:-0}" -ne 0 ]; then
	echo "--- $PENDCOUNT distinct pending() skip reason(s) — deliberate, but check the CONDITION ---"
	printf '%s\n' "$PENDNAMES" | sed 's/^/  /'
fi
# The floor USED to be `RAN -lt 1000`, sized for the 7000-test unit suite. That is an absolute
# magnitude where a relationship was meant — CLAUDE.md's coincidental-value trap, in this gate.
# It passes a 1001-test broken tree and REFUSES a correct small suite: pointing gate.sh at
# test/isolated (1 file, 5 tests) reported RED on a green run. Found only by extending the gate to
# a second suite, which is the mutation an author never runs on their own default path.
# What actually proves a real suite ran is mode-independent: a Totals block exists, something ran,
# and scripts-run matches the files on disk (checked below).
if [ "$TOTALS" -eq 0 ] || [ "$RAN" -lt 1 ]; then
	echo "GATE: RED — log has no Totals block or ran $RAN tests; the run did not complete, so [Failed]=$FAILED means nothing"; exit 1
fi
if [ "$SCRIPTS" -ne "$ONDISK" ] || [ "$LOADFAIL" -ne 0 ]; then
	echo "GATE: RED — SCOPE. GUT ran $SCRIPTS script(s) against $ONDISK on disk ($LOADFAIL load failure(s))."
	echo "A file that does not parse is skipped, not failed, so failing=$FAILED is silent about it:"
	grep -E 'does not extend GutTest|Failed to load script|Parse Error' "$LOG" | head -5
	exit 1
fi
# Two independent signals must agree; disagreement is itself a failure.
if [ "$EC" -ne 0 ] || [ "$FAILED" -ne 0 ]; then
	echo "GATE: RED — do not push"; exit 1
fi
echo "GATE: GREEN"
