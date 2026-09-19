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

Exit: 0 printed a ranking · 1 no such process · 2 process vanished mid-sample.

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
            out[tid] = (comm, int(fields[11]) + int(fields[12]))
        except (IndexError, ValueError):
            continue
    return out


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
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
    for tid, (comm, end) in second.items():
        if tid not in first:
            continue
        delta = end - first[tid][1]
        rows.append((delta / CLK / window * 100.0, tid, comm))
    rows.sort(reverse=True)

    print(f"pid {pid} · {len(second)} threads · {window:g}s window")
    print(f"{'%CPU':>7}  {'tid':>8}  comm")
    for pct, tid, comm in rows[:12]:
        mark = "  <-- SPINNING" if pct > 80 else ""
        print(f"{pct:7.1f}  {tid:>8}  {comm}{mark}")

    busy = [r for r in rows if r[0] > 80]
    total = sum(r[0] for r in rows)
    print(f"\ntotal across all threads: {total:.1f}%")
    if busy:
        print(f"SPINNER: tid {busy[0][1]} ({busy[0][2]}) at {busy[0][0]:.0f}%")
        main_tid = str(pid)
        if busy[0][1] != main_tid:
            print("It is NOT the main thread — so it is not GDScript; GUT runs tests on main.")
    else:
        print("No thread above 80%: not a spin. A blocked process shows ~0% everywhere,")
        print("which is a DIFFERENT failure from a wedge and wants a different look.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
