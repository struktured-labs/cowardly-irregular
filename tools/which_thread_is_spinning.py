#!/usr/bin/env python3
"""Name the thread burning CPU inside a wedged process, without ptrace.

Written after the .461 gate wedged for 1h57m (cowir-main, 2026-09-19): one thread at
100%, main thread blocked, log frozen — and the mechanism was lost because a per-thread
backtrace needs privileges nobody wanted to take mid-recording. The same shape was
measured a week earlier (test/unit/helpers/gd_source.gd:91, EC=124) and lost the same way.

/proc/<pid>/task/<tid>/stat is world-readable, so WHICH thread is spinning costs nothing
and needs no privileges. That is not a backtrace, but it is the difference between
"engine-internal, unconfirmed" and "the audio server thread".

Usage:
    tools/which_thread_is_spinning.py <pid> [seconds]
    tools/which_thread_is_spinning.py --selftest

Exit: 0 printed a ranking · 1 no such process · 2 process vanished mid-sample.

--selftest exercises main_thread_verdict() against the readings measured on 2026-09-20
and touches NOTHING: no file opened, no directory walked, no /proc read, no subprocess,
no git, nothing written. It is pure table lookup over literals in this file.

PARSING NOTE — `comm` is field 2 and MAY CONTAIN SPACES AND PARENTHESES, so positional
splitting of the whole line is wrong. The only correct anchor is the LAST ')'. A shell
`read pid comm state rest` also silently shifts every later index by one, which is how
the first version of this reported stime under the label utime.
"""
import os
import sys
import time

CLK = os.sysconf("SC_CLK_TCK")


def threads(pid):
    """{tid: (comm, utime+stime in ticks)} — skips threads that exit mid-walk."""
    out = {}
    try:
        tids = os.listdir(f"/proc/{pid}/task")
    except FileNotFoundError:
        return None
    for tid in tids:
        try:
            with open(f"/proc/{pid}/task/{tid}/stat") as fh:
                line = fh.read()
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue
        # comm may contain spaces/parens: anchor on the LAST ')'
        close = line.rfind(")")
        if close < 0:
            continue
        comm = line[line.find("(") + 1:close]
        fields = line[close + 2:].split()
        # after comm: state=0 ppid=1 pgrp=2 session=3 tty=4 tpgid=5 flags=6
        #             minflt=7 cminflt=8 majflt=9 cmajflt=10 utime=11 stime=12
        try:
            ticks = int(fields[11]) + int(fields[12])
        except (IndexError, ValueError):
            continue
        state = fields[0] if fields else "?"
        # wchan names the kernel function a sleeping thread is parked in. It is what
        # separates "blocked on a lock" from "spinning in userspace", and it is
        # world-readable — cowir-sprites' column, from their independent build.
        try:
            with open(f"/proc/{pid}/task/{tid}/wchan") as fh:
                wchan = fh.read().strip() or "-"
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            wchan = "?"
        out[tid] = (comm, ticks, state, wchan)
    return out


# wchan values that mean "parked on a timer or waiting for input" -- ordinary idling.
# A healthy godot main sits here whenever it is between work.
_IDLE_WAITS = (
    "hrtimer_nanosleep", "do_nanosleep", "schedule_hrtimeout_range",
    "do_sys_poll", "poll_schedule_timeout", "ep_poll", "do_epoll_wait",
    "do_select", "pipe_read", "wait_woken",
)

# wchan prefixes that mean "waiting for another thread to release something".
_LOCK_WAITS = ("futex", "rwsem_down", "__mutex_lock", "mutex_lock",
               "wait_for_completion", "down_read", "down_write")

# wchan readings that name no wait at all: a running thread, or a kernel that
# declined to answer. Never evidence of either verdict.
_NO_ANSWER = ("", "-", "?", "0", "0x0")


def main_thread_verdict(state, wchan):
    """(verdict, why) for the main thread, from state and wchan alone.

    ⛔ "MAIN IS BLOCKED" IS TWO DIFFERENT FACTS AND THE FIRST VERSION OF THIS PRINTED
    ONE LABEL FOR BOTH. The old test was `state != "R" and wchan not in ("-", "?")`,
    which is satisfied by an idle main exactly as it is by a jammed one -- so a
    perfectly healthy process got "BLOCKED (waiting on something)".

    Measured 2026-09-20, both on healthy processes:
        suite main mid-run    state=R  wchan=0                  (cowir-sprites, pid 4030433)
        idle main             state=S  wchan=hrtimer_nanosleep  (cowir-autogrind, pid 312135)
    A healthy main is in S a large fraction of any window. `S` alone says nothing;
    WHICH wait it is parked in is the whole discriminator, and it was being discarded.
    """
    if state == "R":
        return "RUNNING", "executing -- this is the healthy signature, not a wedge"
    w = (wchan or "").strip()
    if w in _NO_ANSWER:
        return "UNKNOWN", ("state=%s but wchan reads %r -- this cannot separate idle "
                           "from blocked, and must not be reported as either" % (state, w))
    if w.startswith(_LOCK_WAITS):
        return "WAITING-ON-A-LOCK", ("parked in %s -- main wants something another thread "
                                     "holds" % w)
    if w in _IDLE_WAITS:
        return "IDLE", "sleeping in %s -- what a healthy main does between work" % w
    return "UNKNOWN", "parked in %s -- neither a known idle wait nor a known lock wait" % w


def selftest():
    """The verdict table, against real readings. Pure; opens nothing.

    The third row is the regression: before 2026-09-20 an IDLE main was labelled
    "BLOCKED (waiting on something)", identically to a lock-waiting one. Both of the
    first three rows came off healthy processes, so the old label fired on health.
    """
    cases = [
        # (state, wchan,               expected verdict,     what produced this reading)
        ("R", "0",                     "RUNNING",
         "healthy .471 suite main mid-run, t=71s, pid 4030433"),
        ("S", "hrtimer_nanosleep",     "IDLE",
         "healthy idle main, pid 312135 -- MISLABELLED 'BLOCKED' before this fix"),
        ("S", "do_sys_poll",           "IDLE",
         "a main parked waiting for input is idle, not blocked"),
        ("S", "futex_do_wait",         "WAITING-ON-A-LOCK",
         "the reading that would make a spinner main's blocker"),
        ("S", "rwsem_down_read_slowpath", "WAITING-ON-A-LOCK",
         "a lock wait that is not a futex must not fall through to UNKNOWN"),
        ("S", "0",                     "UNKNOWN",
         "state S with no wait channel decides nothing -- must not read as blocked"),
        ("S", "?",                     "UNKNOWN", "unreadable wchan"),
        ("S", "",                      "UNKNOWN", "empty wchan"),
        ("S", "some_future_kernel_fn", "UNKNOWN",
         "an unrecognised wait is UNDECIDED, never quietly filed as idle"),
        ("D", "io_schedule",           "UNKNOWN",
         "uninterruptible sleep is neither of the two branches"),
    ]
    bad = 0
    for state, wchan, want, note in cases:
        got, why = main_thread_verdict(state, wchan)
        ok = got == want
        bad += not ok
        print(f"{'ok  ' if ok else 'FAIL'} state={state} wchan={wchan!r:28} "
              f"-> {got:18} (want {want})   {note}")
    # ANTI-VACUITY FLOOR: an empty or truncated case list would make this pass while
    # asserting nothing, which is the failure mode this tool exists to warn about.
    if len(cases) < 10:
        print(f"FAIL the case table is {len(cases)} rows; it must cover both branches "
              f"and every no-answer form")
        bad += 1
    # CONTROL: prove the two verdicts are actually distinguishable by this function.
    # If it ever returned one constant, every row above could still be made to pass by
    # editing expectations -- this cannot.
    if main_thread_verdict("S", "futex_do_wait")[0] == main_thread_verdict("S", "hrtimer_nanosleep")[0]:
        print("FAIL a lock wait and a timed sleep must not share a verdict -- "
              "that collapse IS the bug this replaced")
        bad += 1
    print(f"\n{len(cases)} cases, {bad} failed")
    return 1 if bad else 0


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    if sys.argv[1] == "--selftest":
        return selftest()
    pid = sys.argv[1]
    window = float(sys.argv[2]) if len(sys.argv) > 2 else 5.0

    first = threads(pid)
    if first is None:
        print(f"no such process: {pid}")
        return 1
    time.sleep(window)
    second = threads(pid)
    if second is None:
        print(f"process {pid} vanished during the sample")
        return 2

    rows = []
    for tid, (comm, end, state, wchan) in second.items():
        if tid not in first:
            continue
        delta = end - first[tid][1]
        rows.append((delta / CLK / window * 100.0, tid, comm, state, wchan))
    rows.sort(reverse=True)

    print(f"pid {pid} · {len(second)} threads · {window:g}s window")
    print(f"{'%CPU':>7}  {'tid':>8}  {'S':1}  {'comm':22}  wchan")
    for pct, tid, comm, state, wchan in rows[:12]:
        mark = "  <-- SPINNING" if pct > 80 else ""
        print(f"{pct:7.1f}  {tid:>8}  {state:1}  {comm:22}  {wchan}{mark}")

    main_row = next((r for r in rows if r[1] == str(pid)), None)
    verdict = None
    if main_row is None:
        # An absent main row is a fact, not a blank. Say so rather than print nothing:
        # a missing line reads as "main is fine" to everyone who does not know the format.
        print(f"\nmain thread {pid}: NOT SAMPLED -- it exited or appeared mid-window.")
    else:
        verdict, why = main_thread_verdict(main_row[3], main_row[4])
        print(f"\nmain thread {main_row[1]}: {main_row[0]:.1f}% "
              f"state={main_row[3]} wchan={main_row[4]}")
        print(f"  -> {verdict}: {why}")

    busy = [r for r in rows if r[0] > 80]
    total = sum(r[0] for r in rows)
    print(f"\ntotal across all threads: {total:.1f}%")
    if busy:
        print(f"SPINNER: tid {busy[0][1]} ({busy[0][2]}) at {busy[0][0]:.0f}%")
        main_tid = str(pid)
        if busy[0][1] != main_tid:
            print("It is NOT the main thread — so it is not GDScript; GUT runs tests on main.")
            # The pairing, not either half: a spinner beside an IDLE main is a spinner
            # nobody is waiting for; beside a LOCK-WAITING main it is the thing main is
            # stuck behind. Reporting only the spinner cannot tell these apart.
            if verdict == "WAITING-ON-A-LOCK":
                print("...and main is waiting on a lock: main is blocked BEHIND this "
                      "spinner. Whatever main asked for is the trigger.")
            elif verdict == "IDLE":
                print("...and main is merely idle: the spinner is INDEPENDENT of main, "
                      "which is a different failure from a wedge.")
            elif verdict == "UNKNOWN":
                print("...and main's wait is unreadable, so whether main is blocked "
                      "behind it is UNDECIDED. Do not report this as a wedge.")
    else:
        print("No thread above 80%: not a spin. A blocked process shows ~0% everywhere,")
        print("which is a DIFFERENT failure from a wedge and wants a different look.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
