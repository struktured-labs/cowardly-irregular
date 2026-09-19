#!/usr/bin/env bash
# bounded_godot.sh — run ONE godot invocation under a clock, and say so in BOTH directions.
#
# WHY THIS EXISTS AS A FILE RATHER THAN AS `timeout` AT SEVEN CALL SITES.
# 2026-09-19 I surveyed the publish path and found seven godot invocations, exactly one bounded
# (deploy_web.sh's xvfb smoke, `timeout 300`). I bounded a second one inline — publish_all's
# import — and the inline repair immediately showed why it is the wrong shape:
#
#   1. THE VERDICT LANDED IN THE LOG. Every site writes `godot … > tmp/x.log 2>&1`, so an inline
#      wrapper's own message is captured by the caller's redirection and nobody reads it. The
#      bound has to own the redirection to be able to speak outside it. Hence --log.
#   2. THE PASSING ARM SAID NOTHING. The inline block named elapsed and budget when it blocked
#      and printed nothing when it passed, so "bounded and finished in 38s" and "not bounded at
#      all" are the same output. A bound you cannot see is indistinguishable from its absence.
#   3. THE REASONING IS 12 LINES OF MEASURED COMMENT PER SITE. Six copies is six chances to
#      copy the version that predates the next measurement.
#
# ⛔ THE PLAIN `timeout` IS DELIBERATE — DO NOT "HARDEN" IT. Measured on this box, four lanes
# agreeing: uutils timeout 0.2.2 CANNOT DELIVER SIGKILL. `--signal=KILL` runs the command to
# completion and still reports 124, i.e. it is a SILENT NO-OP as a bound. TERM delivers, and
# godot honours TERM (SigIgn=0, bit 0x4000 clear, read off this lane's own `--headless --import`
# run, identified by `readlink /proc/<pid>/exe` rather than by pgrep pattern — `timeout`'s own
# command line contains its child's entire argv, so `pgrep -f godot` matches the WRAPPER).
# `--kill-after` only changes 124 into 125 and makes a normally-exiting TERM-ignoring child
# report 137.
#
# ⚠️ AND THE VERDICT IS ELAPSED, NEVER THE EXIT CODE. The same measurements showed `timeout`
# reporting 124 for a command that ran 6x its budget untouched, and 137 — "killed by SIGKILL" —
# for a process that exited normally. The code names events that did not happen; the clock does
# not. So the wedge test here is `elapsed >= budget`, and the code is only reported.
#
# USAGE
#   tools/bounded_godot.sh --label <name> --budget <seconds> --log <file> -- <command…>
# EXIT
#   124  WEDGE — ran to the budget. This is NO VERDICT, not a failure: the run never finished,
#        so whatever it was judging is unjudged.
#   2    the bound itself is unusable (missing/!numeric/<=0 budget, no command, unwritable log).
#        Fails CLOSED: an unbounded run is the thing this file exists to prevent.
#   *    the command's own exit code, unmodified.
set -uo pipefail
SELF="${BASH_SOURCE[0]}"

# ── selftest ────────────────────────────────────────────────────────────────
# Every arm runs THIS FILE as a subprocess with the godot command SUBSTITUTED, so no real import
# is interrupted and no import cache is put at risk. Testing a re-implementation of the clock
# would not execute a line of what ships (cowir-battle, 2026-09-09).
_selftest() {
    local dir ec out pass=0 fail=0
    mkdir -p "${TMPDIR:-tmp}"
    dir="$(mktemp -d "${TMPDIR:-tmp}/bounded_selftest.XXXXXX")" || { echo "selftest: no tmp dir" >&2; return 2; }
    trap 'rm -rf "$dir"' RETURN

    # run <name> <expected-ec> <expect-stderr-regex> <reject-stderr-regex|-> -- args…
    run() {
        local name="$1" want_ec="$2" want_re="$3" deny_re="$4"; shift 4; [ "${1-}" = "--" ] && shift
        local err="$dir/err.$$.$RANDOM"
        ec=0
        bash "$SELF" "$@" 2> "$err" || ec=$?
        local why=""
        [ "$ec" = "$want_ec" ] || why="exit ${ec}, wanted ${want_ec}"
        if [ -z "$why" ] && [ "$want_re" != "-" ]; then
            command grep -aqE -e "$want_re" "$err" || why="stderr lacks /${want_re}/"
        fi
        if [ -z "$why" ] && [ "$deny_re" != "-" ]; then
            command grep -aqE -e "$deny_re" "$err" && why="stderr wrongly contains /${deny_re}/"
        fi
        if [ -n "$why" ]; then
            fail=$(( fail + 1 )); echo "  FAIL  ${name}: ${why}"; sed -n '1,6p' "$err" | sed 's/^/        | /'
        else
            pass=$(( pass + 1 )); echo "  ok    ${name}"
        fi
    }

    echo "[bound] selftest — the clock, both directions"
    run "wedge is called a wedge"        124 "sleeper WEDGED — ran [0-9]+s against a 1s budget" "-" \
        -- --label sleeper --budget 1 --log "$dir/a.log" -- sleep 3
    run "  ...and names NO VERDICT"      124 "NO VERDICT: the run never finished" "-" \
        -- --label sleeper --budget 1 --log "$dir/b.log" -- sleep 3
    run "  ...and reports survivors"     124 "survivors in .*: 0 — the bound reaped" "-" \
        -- --label sleeper --budget 1 --log "$dir/c.log" -- sleep 3
    # THE BOUNDARY IS DELIBERATELY INCLUSIVE, AND IT IS A KNOWN FALSE POSITIVE. `timeout` fires AT
    # the budget, so a run that reaches it is indistinguishable from one that was killed there —
    # measured 6x on `sleep 2` under `--budget 2`: the CODE came back 124 four times and 0 twice,
    # for the same command. The clock said 2 every time. So the code cannot arbitrate the boundary
    # and a command that genuinely finished on the last second is called a wedge. That costs a
    # re-run; the other choice costs a release that never happens.
    run "elapsed == budget IS a wedge"   124 "WEDGED — ran [0-9]+s against a 1s budget" "-" \
        -- --label edge --budget 1 --log "$dir/d.log" -- sleep 1
    # THE PASSING ARM SPEAKS. This is the defect the inline version shipped with: it named
    # elapsed and budget when it blocked and printed nothing when it passed.
    run "a pass names its subject"         0 "^\[bound\] quickie: finished in [0-9]+s of a 20s budget" "-" \
        -- --label quickie --budget 20 --log "$dir/e.log" -- sleep 1
    run "a pass is not called a wedge"     0 "bounded, not wedged" "WEDGED" \
        -- --label quickie --budget 20 --log "$dir/f.log" -- sleep 1
    # A FAST FAILURE IS NOT A WEDGE — the distinction the exit code alone cannot make.
    run "fail-fast keeps its own code"     1 "falsey: finished in [0-9]+s of a 20s budget .code 1." "WEDGED" \
        -- --label falsey --budget 20 --log "$dir/g.log" -- false
    run "an exotic code passes through"   42 "code 42" "WEDGED" \
        -- --label exotic --budget 20 --log "$dir/h.log" -- bash -c 'exit 42'

    echo "[bound] selftest — the bound fails CLOSED when it is unusable"
    run "no --budget"                      2 "no --budget for 'nb'" "-"  -- --label nb --log "$dir/i.log" -- true
    run "non-numeric --budget"             2 "--budget 'soon' .* is not a whole number" "-" -- --label nn --budget soon --log "$dir/j.log" -- true
    run "--budget 0 is NOT a bound"        2 "GNU timeout reads 0 as NO BOUND" "-" -- --label z --budget 0 --log "$dir/k.log" -- true
    run "no --label"                       2 "cannot name its subject" "-" -- --budget 5 --log "$dir/l.log" -- true
    run "no --log"                         2 "the verdict lands in the caller's redirection" "-" -- --label nl --budget 5 -- true
    run "no command after --"              2 "no command after -- for 'nc'" "-" -- --label nc --budget 5 --log "$dir/m.log" --
    run "unknown option"                   2 "unknown option: --zzz" "-" -- --label uo --budget 5 --zzz --log "$dir/n.log" -- true

    echo "[bound] selftest — the verdict must escape the caller's log"
    ec=0; bash "$SELF" --label speaker --budget 20 --log "$dir/o.log" -- \
        bash -c 'echo COMMAND_STDOUT_LANDED_HERE; echo COMMAND_STDERR_TOO >&2' 2> "$dir/o.err" || ec=$?
    if [ "$ec" = 0 ] \
       && command grep -aq COMMAND_STDOUT_LANDED_HERE "$dir/o.log" \
       && command grep -aq COMMAND_STDERR_TOO "$dir/o.log" \
       && ! command grep -aq '\[bound\]' "$dir/o.log" \
       && command grep -aq '\[bound\] speaker:' "$dir/o.err"; then
        pass=$(( pass + 1 )); echo "  ok    command output in the log, verdict OUTSIDE it"
    else
        fail=$(( fail + 1 )); echo "  FAIL  command output in the log, verdict OUTSIDE it (ec=${ec})"
    fi
    # CONTROL for the arm above: if the verdict did land in the log the arm must go red, so
    # prove the log is a file this test can actually see a '[bound]' string in.
    echo '[bound] planted' >> "$dir/o.log"
    if command grep -aq '\[bound\]' "$dir/o.log"; then
        pass=$(( pass + 1 )); echo "  ok    CONTROL: a planted '[bound]' IS visible in that same log"
    else
        fail=$(( fail + 1 )); echo "  FAIL  CONTROL: a planted '[bound]' is invisible — the arm above was vacuous"
    fi

    echo "[bound] selftest: ${pass} passed, ${fail} failed"
    [ "$fail" -eq 0 ]
}

_die() { echo "[bound] BLOCKED: $*" >&2; exit 2; }

LABEL=""; BUDGET=""; LOG=""
while [ $# -gt 0 ]; do
    case "$1" in
        --label)  LABEL="${2-}"; shift 2 || _die "--label needs a value" ;;
        --budget) BUDGET="${2-}"; shift 2 || _die "--budget needs a value" ;;
        --log)    LOG="${2-}"; shift 2 || _die "--log needs a value" ;;
        --selftest) shift; _selftest "$@"; exit $? ;;
        --) shift; break ;;
        *) _die "unknown option: $1" ;;
    esac
done

[ -n "$LABEL" ]  || _die "no --label. A bound that cannot name its subject cannot report one."
[ -n "$LOG" ]    || _die "no --log for '$LABEL'. Without it the verdict lands in the caller's redirection."
[ -n "$BUDGET" ] || _die "no --budget for '$LABEL'."
case "$BUDGET" in ''|*[!0-9]*) _die "--budget '$BUDGET' for '$LABEL' is not a whole number of seconds." ;; esac
[ "$BUDGET" -gt 0 ] || _die "--budget 0 for '$LABEL' — GNU timeout reads 0 as NO BOUND, which is the defect."
[ $# -gt 0 ]     || _die "no command after -- for '$LABEL'."

mkdir -p "$(dirname "$LOG")" || _die "could not create the log directory for '$LOG'."
: > "$LOG" || _die "could not write the log '$LOG' for '$LABEL'."

_t0=$(date +%s)
timeout "$BUDGET" "$@" > "$LOG" 2>&1
EC=$?
_elapsed=$(( $(date +%s) - _t0 ))

if [ "$_elapsed" -ge "$BUDGET" ]; then
    echo "[bound] BLOCKED: ${LABEL} WEDGED — ran ${_elapsed}s against a ${BUDGET}s budget (code ${EC})." >&2
    echo "[bound]   This is not a failure, it is NO VERDICT: the run never finished, so whatever" >&2
    echo "[bound]   it was judging is unjudged. Re-run before concluding anything about the tree." >&2
    echo "[bound]   Log: ${LOG}" >&2
    # A wedge that ALSO leaves a live godot is a different problem from a wedge that was reaped,
    # and the exit code cannot tell them apart (see the 124/137 note above). So look at /proc.
    # By exe, not by pattern: `timeout`'s argv contains godot's argv, and so does this script's.
    _surv=0
    for _p in /proc/[0-9]*; do
        _exe="$(readlink "${_p}/exe" || true)"
        case "$_exe" in *godot*) ;; *) continue ;; esac
        [ "$(readlink "${_p}/cwd" || true)" = "$PWD" ] || continue
        _surv=$(( _surv + 1 ))
        echo "[bound]   SURVIVOR: pid ${_p##*/} still running ${_exe} in ${PWD}" >&2
    done
    [ "$_surv" -eq 0 ] && echo "[bound]   survivors in ${PWD}: 0 — the bound reaped what it started." >&2
    exit 124
fi

echo "[bound] ${LABEL}: finished in ${_elapsed}s of a ${BUDGET}s budget (code ${EC}) — bounded, not wedged." >&2
exit "$EC"
