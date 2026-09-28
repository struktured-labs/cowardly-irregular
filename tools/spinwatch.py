#!/usr/bin/env python3
"""Run a command unchanged; if a godot it launches spins its AUDIO MIX thread, write a stack.

Usage:
    tools/spinwatch.sh [--window S] [--gdb-budget S] -- <cmd> [args...]
    tools/spinwatch.py --selftest

WHY THIS EXISTS
---------------
2026-09-28. The headless Dummy mix thread went to 100% CPU with ZERO wakes mid-suite and never
returned (cowir-ai run 1: 172 samples, one wake, from log line ~52481 to the SIGKILL at shutdown).
It hit about 3 of 7 of cowir-main's fold gates that day and 1 of 7 of cowir-ai's own runs, and
never in 15 fresh processes of the files where it starts. So the gates are the best sample, and
the mechanism is still unknown: which_thread_is_spinning.py names the THREAD without ptrace; only
a backtrace names the LOOP.

WHY A WRAPPER, AND WHY THIS SHAPE
---------------------------------
This box runs yama ptrace_scope=1: only an ANCESTOR of godot may attach (or root). So the gdb has
to BE a process that launched the run, not something started beside it. The tree is

    W  (this process: what your caller waits on, and what it gets the exit status from)
    └─ S  (a fork that sits idle; on a hit it replaces itself with gdb, keeping the ancestor PID)
       └─ M  (runs your command and sends its exit status up a pipe to W)
          └─ your command ... godot

S becoming gdb costs nothing, because the exit status travels M -> W and never through S.

CONTRACT (cowir-main, 2026-09-28)
---------------------------------
1. INERT unless the fingerprint matches: no output of its own, same stdin/stdout/stderr, same
   exit status (a signal death is re-raised as the same signal). The fingerprint is ONE thread:
   a non-main godot thread that was seen asleep on a timer at the mix cadence (8-14 wakes/s;
   4096 frames at 44.1k = 10.7/s, at 48k = 11.7/s), then runs at >= 90% CPU with <= 1 wake for
   --window seconds (default 10). Main's state is recorded but NOT required: in run 1 main was
   never in futex_do_wait (0 of 172 samples after onset; it kept running tests), so requiring it
   would have missed the only spin anyone has sampled.
2. The command's exit status passes through untouched, so run_tests.sh's 124 stays 124.
3. On a hit: the /proc history and three gdb rounds go to tmp/spinwatch_<time>_pid<P>_tid<T>.txt,
   one line names that file on stderr, and gdb is bounded by --gdb-budget (default 120s). Past
   the budget gdb is killed and the process gets SIGCONT so a ptrace-stop cannot outlive it. Your
   own wedge handling then proceeds. At most one capture per run.
SPINWATCH_OFF=1 execs the command directly: no fork, nothing watched.
--probe-after S is a WIRING CHECK: after S seconds it captures the mix-cadence thread even though
nothing spins, proving attach, symbols and the hand-off on this box. Never put it under a gate.

Symbols: gdb reads /usr/lib/debug plus <repo>/tmp/godot-dbgsym/usr/lib/debug if present. Ubuntu's
debuginfod has none for godot 4.4.1+ds-1; without root:
    apt download godot-dbgsym && dpkg-deb -x godot-dbgsym_*.ddeb tmp/godot-dbgsym

--selftest runs the classifier over literal histories, then runs THIS FILE as a subprocess
around python3/sh children and one synthetic spinner, with a fake "gdb" (python3) that writes a
marker. It reads /proc only for its own descendants and writes only under
<repo>/tmp/spinwatch_selftest_<pid>/, which it removes. No git, no network, no real gdb.
"""
import os
import select
import signal
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from which_thread_is_spinning import CLK, threads  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TIMER_WAITS = ("hrtimer_nanosleep", "do_nanosleep")
MIX_RATE_LO, MIX_RATE_HI = 8.0, 14.0
SPIN_CPU = 0.90
SPIN_MAX_WAKES = 1

GDB_SCRIPT = r'''
import gdb, os, time
pid = int(os.environ["SPINWATCH_PID"]); tid = int(os.environ["SPINWATCH_TID"])
for r in range(3):
    try:
        if r:
            gdb.execute("attach %d" % pid)
        print("=== ROUND %d  %s" % (r, time.strftime("%H:%M:%S")))
        gdb.execute("info threads")
        for t in gdb.selected_inferior().threads():
            if t.ptid[1] == tid:
                t.switch()
                print("--- WATCHED THREAD %d (the mix-cadence thread)" % tid)
                gdb.execute("bt full 12")
        gdb.execute("thread apply all bt 30")
    except gdb.error as e:
        print("gdb error in round %d: %s" % (r, e))
    finally:
        try:
            gdb.execute("detach")
        except gdb.error:
            pass
    time.sleep(0.7)
'''


def mixer_like(history, cadence_window=5.0):
    """True once a thread has slept on a timer at the mix cadence. history: [(t, ticks, vcs, state, wchan)]."""
    if not any(h[4] in TIMER_WAITS for h in history):
        return False
    for i in range(len(history)):
        for j in range(i + 1, len(history)):
            dt = history[j][0] - history[i][0]
            if dt >= cadence_window:
                rate = (history[j][2] - history[i][2]) / dt
                return MIX_RATE_LO <= rate <= MIX_RATE_HI
    return False


def spinning(history, window):
    """True if the trailing `window` seconds are >= 90% CPU with <= 1 wake, ending in state R."""
    if len(history) < 2 or history[-1][3] != "R":
        return False
    end = history[-1]
    start = None
    for h in reversed(history[:-1]):
        if end[0] - h[0] >= window:
            start = h
            break
    if start is None:
        return False
    dt = end[0] - start[0]
    return (end[1] - start[1]) >= SPIN_CPU * dt * CLK and (end[2] - start[2]) <= SPIN_MAX_WAKES


def classify(histories, main_tid, window, cadence_window=5.0):
    """The tid of the first mixer-like non-main thread that is spinning, else None."""
    for tid, hist in histories.items():
        if tid == main_tid:
            continue
        healthy = [h for h in hist if h[3] != "R" or h[4] in TIMER_WAITS]
        if mixer_like(healthy, cadence_window) and spinning(hist, window):
            return tid
    return None


def _children(pid):
    out = []
    try:
        for tid in os.listdir(f"/proc/{pid}/task"):
            with open(f"/proc/{pid}/task/{tid}/children") as fh:
                out.extend(int(x) for x in fh.read().split())
    except (FileNotFoundError, ProcessLookupError, PermissionError, ValueError):
        pass
    return out


def descendants(pid):
    seen, frontier = [], [pid]
    while frontier:
        nxt = []
        for p in frontier:
            for c in _children(p):
                if c not in seen:
                    seen.append(c)
                    nxt.append(c)
        frontier = nxt
    return seen


def _exe(pid):
    try:
        return os.readlink(f"/proc/{pid}/exe")
    except OSError:
        return ""


def _quiet_handler(signum, frame):
    pass


def _reporter(cmd, report_w):
    """M: run the command with the dispositions it would have had, send its status to W."""
    child = os.fork()
    if child == 0:
        # Python ignores these two at startup; exec resets handlers and keeps inherited ignores.
        for s in (signal.SIGPIPE, signal.SIGXFSZ):
            signal.signal(s, signal.SIG_DFL)
        try:
            os.execvp(cmd[0], cmd)
        except OSError as e:
            os.write(2, f"spinwatch: cannot run {cmd[0]}: {e.strerror}\n".encode())
            os._exit(127)
    os.write(report_w, f"pid {child}\n".encode())
    while True:
        try:
            _, status = os.waitpid(child, 0)
            break
        except ChildProcessError:
            status = 127 << 8
            break
    if os.WIFSIGNALED(status):
        os.write(report_w, f"signal {os.WTERMSIG(status)}\n".encode())
    else:
        os.write(report_w, f"exit {os.WEXITSTATUS(status)}\n".encode())
    os._exit(0)


def _idle_ancestor(cmd, report_w, ctl_r, gdb_bin):
    """S: fork M, then wait. SIGUSR1 turns this process into gdb (it stays godot's ancestor)."""
    m = os.fork()
    if m == 0:
        os.close(ctl_r)
        _reporter(cmd, report_w)
    os.close(report_w)

    def become_gdb(signum, frame):
        req = os.read(ctl_r, 4096).decode().split("\n", 1)[0].split("\t")
        pid, tid, out, script, exe, debug = req
        env = dict(os.environ, SPINWATCH_PID=pid, SPINWATCH_TID=tid)
        fd = os.open(out, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o644)
        os.dup2(fd, 1)
        os.dup2(fd, 2)
        nul = os.open(os.devnull, os.O_RDONLY)
        os.dup2(nul, 0)
        signal.signal(signal.SIGTERM, signal.SIG_DFL)
        os.execvpe(gdb_bin, [gdb_bin, exe, "-p", pid, "-batch", "-iex", "set sysroot /",
                             "-iex", "set debuginfod enabled off",
                             "-iex", f"set debug-file-directory {debug}", "-x", script], env)

    signal.signal(signal.SIGUSR1, become_gdb)
    while True:
        try:
            os.waitpid(m, 0)
            break
        except ChildProcessError:
            break
    os._exit(0)


def _read_lines(fd, buf):
    try:
        chunk = os.read(fd, 4096)
    except BlockingIOError:
        return buf, False
    if not chunk:
        return buf, True
    return buf + chunk.decode(), False


def run(cmd, window, gdb_budget, gdb_bin, exe_prefix, out_dir, interval=1.0, cadence_window=5.0, probe_after=0.0):
    if os.environ.get("SPINWATCH_OFF") == "1":
        os.execvp(cmd[0], cmd)
    report_r, report_w = os.pipe()
    ctl_r, ctl_w = os.pipe()
    for s in (signal.SIGINT, signal.SIGQUIT):
        if signal.getsignal(s) is not signal.SIG_IGN:
            signal.signal(s, _quiet_handler)
    s_pid = os.fork()
    if s_pid == 0:
        os.close(report_r)
        os.close(ctl_w)
        _idle_ancestor(cmd, report_w, ctl_r, gdb_bin)
    os.close(report_w)
    os.close(ctl_r)
    os.set_blocking(report_r, False)

    child = {"pid": None}

    def forward(signum, frame):
        if child["pid"]:
            try:
                os.kill(child["pid"], signum)
            except ProcessLookupError:
                pass

    for s in (signal.SIGTERM, signal.SIGHUP):
        if signal.getsignal(s) is not signal.SIG_IGN:
            signal.signal(s, forward)

    buf, eof, result = "", False, None
    histories, captured = {}, False
    started = time.monotonic()
    while result is None and not eof:
        ready, _, _ = select.select([report_r], [], [], interval)
        if ready:
            buf, eof = _read_lines(report_r, buf)
            for line in buf.splitlines():
                kind, _, val = line.partition(" ")
                if kind == "pid":
                    child["pid"] = int(val)
                elif kind in ("exit", "signal"):
                    result = (kind, int(val))
            continue
        if captured:
            continue
        now = time.monotonic()
        for p in descendants(s_pid):
            if not os.path.basename(_exe(p)).startswith(exe_prefix):
                continue
            snap = threads(p)
            if not snap:
                continue
            for tid, (_comm, ticks, state, wchan, vcs) in snap.items():
                hist = histories.setdefault((p, tid), [])
                hist.append((now, ticks, vcs, state, wchan))
                if len(hist) > 600:
                    del hist[:300]
            per_pid = {tid: histories[(p, tid)] for tid in snap}
            hit = classify(per_pid, str(p), window, cadence_window)
            reason = "spin"
            if not hit and probe_after and now - started >= probe_after:
                hit = next((t for t, h in per_pid.items() if t != str(p) and mixer_like(h, cadence_window)), None)
                reason = "probe"
            if hit:
                captured = True
                _capture(s_pid, ctl_w, p, hit, histories, cmd, window, gdb_budget, out_dir, reason)
                break
    try:
        os.waitpid(s_pid, 0)
    except ChildProcessError:
        pass
    if result is None:
        os._exit(127)
    kind, val = result
    if kind == "signal":
        signal.signal(val, signal.SIG_DFL)
        os.kill(os.getpid(), val)
        os._exit(128 + val)
    os._exit(val)


def _capture(s_pid, ctl_w, pid, tid, histories, cmd, window, gdb_budget, out_dir, reason="spin"):
    os.makedirs(out_dir, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    out = os.path.join(out_dir, f"spinwatch_{stamp}_pid{pid}_tid{tid}.txt")
    script = out[:-4] + ".gdb.py"
    with open(script, "w") as fh:
        fh.write(GDB_SCRIPT)
    debug = "/usr/lib/debug:" + os.path.join(REPO, "tmp", "godot-dbgsym", "usr", "lib", "debug")
    with open(out, "w") as fh:
        fh.write(f"spinwatch {reason} {time.strftime('%Y-%m-%d %H:%M:%S')}\ncmd: {' '.join(cmd)}\n")
        if reason == "probe":
            fh.write(f"godot pid {pid}, mix-cadence tid {tid}: --probe-after wiring check, NOT a spin\n")
        else:
            fh.write(f"godot pid {pid}, spinning tid {tid}: >= {SPIN_CPU:.0%} CPU, <= {SPIN_MAX_WAKES} wake over {window:g}s\n")
        fh.write("history of that thread (monotonic s, cpu ticks, voluntary switches, state, wchan):\n")
        for h in histories[(pid, tid)][-30:]:
            fh.write("  %.1f %d %d %s %s\n" % h)
        main = histories.get((pid, str(pid)))
        if main:
            fh.write("main thread now: state %s wchan %s\n\n" % (main[-1][3], main[-1][4]))
    os.write(ctl_w, f"{pid}\t{tid}\t{out}\t{script}\t{_exe(pid)}\t{debug}\n".encode())
    os.kill(s_pid, signal.SIGUSR1)
    deadline = time.monotonic() + gdb_budget
    while time.monotonic() < deadline:
        done, _ = os.waitpid(s_pid, os.WNOHANG)
        if done:
            break
        time.sleep(0.2)
    else:
        try:
            os.kill(s_pid, signal.SIGKILL)
            os.waitpid(s_pid, 0)
        except (ProcessLookupError, ChildProcessError):
            pass
        with open(out, "a") as fh:
            fh.write(f"\nspinwatch: gdb exceeded {gdb_budget:g}s and was killed\n")
    try:
        os.kill(pid, signal.SIGCONT)
    except ProcessLookupError:
        pass
    what = "wiring probe of" if reason == "probe" else f"spun {window:g}s at >= 90% CPU with no wakes:"
    os.write(2, f"[spinwatch] godot {pid}: {what} audio-mix-cadence thread {tid}; stack -> {out}\n".encode())


def _selftest():
    import shutil
    import subprocess
    failures = []

    def check(name, ok, detail=""):
        print(("ok   " if ok else "FAIL ") + name + ("" if ok else f"  ({detail})"))
        if not ok:
            failures.append(name)

    def hist(rows):
        return [(float(t), int(c), int(v), s, w) for t, c, v, s, w in rows]

    mixer_sleep = [(t, t // 10, 11 * t, "S", "hrtimer_nanosleep") for t in range(0, 12)]
    mixer_spin = mixer_sleep + [(t, 11 + (t - 11) * CLK, 121, "R", "0") for t in range(12, 25)]
    check("a healthy mix thread is not a hit",
          classify({"9": hist(mixer_sleep), "1": hist(mixer_sleep)}, "1", 10) is None)
    check("the mix thread at 100% with no wakes for the window is a hit",
          classify({"9": hist(mixer_spin)}, "1", 10) == "9")
    check("a spin shorter than the window is not a hit",
          classify({"9": hist(mixer_spin[:18])}, "1", 10) is None)
    check("the same spin on MAIN is not a hit (main is busy running tests)",
          classify({"1": hist(mixer_spin)}, "1", 10) is None)
    fast = [(t, t // 10, 100 * t, "S", "hrtimer_nanosleep") for t in range(0, 12)]
    fast += [(t, 11 + (t - 11) * CLK, 1100, "R", "0") for t in range(12, 25)]
    check("a 99.7/s timer thread spinning is not the mixer", classify({"9": hist(fast)}, "1", 10) is None)
    worker = [(t, t * CLK, 0, "R", "0") for t in range(0, 25)]
    check("a futex worker at 100% that never slept on a timer is not a hit",
          classify({"9": hist(worker)}, "1", 10) is None)
    woke = [(t, c, v + (3 if t >= 20 else 0), s, w) for t, c, v, s, w in mixer_spin]
    check("three wakes inside the window is not a spin", classify({"9": hist(woke)}, "1", 10) is None)

    work = os.path.join(REPO, "tmp", f"spinwatch_selftest_{os.getpid()}")
    os.makedirs(work, exist_ok=True)
    me = [sys.executable, os.path.abspath(__file__)]
    try:
        for code in (0, 1, 124):
            r = subprocess.run(me + ["--", sys.executable, "-c", f"import sys; sys.exit({code})"],
                               capture_output=True, timeout=30)
            check(f"exit {code} passes through untouched", r.returncode == code and r.stdout == b"" and r.stderr == b"",
                  f"rc={r.returncode} out={r.stdout!r} err={r.stderr!r}")
        payload = b"in\x00put\xff\n"
        r = subprocess.run(me + ["--", "sh", "-c", "cat; printf E >&2"], input=payload, capture_output=True, timeout=30)
        check("stdin, stdout and stderr pass through byte for byte",
              r.returncode == 0 and r.stdout == payload and r.stderr == b"E", f"{r.returncode} {r.stdout!r} {r.stderr!r}")
        r = subprocess.run(me + ["--", "sh", "-c", "kill -TERM $$"], capture_output=True, timeout=30)
        check("a signal death is re-raised as the same signal", r.returncode == -signal.SIGTERM, f"rc={r.returncode}")

        spinner = os.path.join(work, "spinner.py")
        with open(spinner, "w") as fh:
            fh.write("import threading, time, sys\n"
                     "def mixer():\n"
                     "    end = time.monotonic() + 1.8\n"
                     "    while time.monotonic() < end:\n"
                     "        time.sleep(4096 / 44100)\n"
                     "    end = time.monotonic() + 2.2\n"
                     "    while time.monotonic() < end:\n"
                     "        pass\n"
                     "t = threading.Thread(target=mixer); t.start(); t.join(); sys.exit(7)\n")
        fake_gdb = os.path.join(work, "fakegdb.py")
        with open(fake_gdb, "w") as fh:
            fh.write("#!/usr/bin/env python3\nimport os, sys\n"
                     "print('FAKE STACK pid %s tid %s' % (os.environ['SPINWATCH_PID'], os.environ['SPINWATCH_TID']))\n")
        os.chmod(fake_gdb, 0o755)
        exe_prefix = os.path.basename(os.path.realpath(sys.executable))
        hang_gdb = os.path.join(work, "hanggdb.py")
        with open(hang_gdb, "w") as fh:
            fh.write("#!/usr/bin/env python3\nimport time\ntime.sleep(3600)\n")
        os.chmod(hang_gdb, 0o755)
        fast = ["--interval", "0.2", "--cadence-window", "1", "--window", "1", "--exe-prefix", exe_prefix]
        hit_dir, hang_dir = os.path.join(work, "hit"), os.path.join(work, "hang")
        t0 = time.monotonic()
        hit = subprocess.Popen(me + fast + ["--gdb", fake_gdb, "--out-dir", hit_dir, "--", sys.executable, spinner],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        hang = subprocess.Popen(me + fast + ["--gdb", hang_gdb, "--gdb-budget", "1", "--out-dir", hang_dir,
                                             "--", sys.executable, spinner], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        _, hit_err = hit.communicate(timeout=60)
        _, _ = hang.communicate(timeout=60)

        def body(d):
            names = sorted(os.listdir(d)) if os.path.isdir(d) else []
            return [n for n in names if n.endswith(".txt")], "".join(
                open(os.path.join(d, n)).read() for n in names if n.endswith(".txt"))
        outs, text = body(hit_dir)
        check("a mixer-cadence thread that spins is captured, and its exit status still passes through",
              hit.returncode == 7 and len(outs) == 1 and "FAKE STACK" in text and b"[spinwatch]" in hit_err,
              f"rc={hit.returncode} files={outs} err={hit_err[-200:]!r}")
        _, text = body(hang_dir)
        check("a gdb that never returns is killed at its budget and the run still exits with its own status",
              hang.returncode == 7 and "exceeded 1s" in text, f"rc={hang.returncode} tail={text[-120:]!r}")
        check("both capture arms finished well inside a gate's patience", time.monotonic() - t0 < 20,
              f"{time.monotonic() - t0:.1f}s")
    finally:
        shutil.rmtree(work, ignore_errors=True)
    print("SELFTEST " + ("PASSED" if not failures else f"FAILED: {', '.join(failures)}"))
    return 0 if not failures else 1


def main(argv):
    if argv[1:2] == ["--selftest"]:
        return _selftest()
    if "--" not in argv:
        sys.stderr.write(__doc__.split("\n\n")[1] + "\n")
        return 2
    split = argv.index("--")
    opts, cmd = argv[1:split], argv[split + 1:]
    if not cmd:
        sys.stderr.write("spinwatch: nothing to run after --\n")
        return 2
    cfg = {"--window": "10", "--gdb-budget": "120", "--gdb": "gdb", "--exe-prefix": "godot",
           "--out-dir": os.path.join(REPO, "tmp"), "--interval": "1", "--cadence-window": "5", "--probe-after": "0"}
    i = 0
    while i < len(opts):
        if opts[i] not in cfg or i + 1 >= len(opts):
            sys.stderr.write(f"spinwatch: unknown or incomplete option {opts[i]}\n")
            return 2
        cfg[opts[i]] = opts[i + 1]
        i += 2
    run(cmd, float(cfg["--window"]), float(cfg["--gdb-budget"]), cfg["--gdb"], cfg["--exe-prefix"], cfg["--out-dir"],
        float(cfg["--interval"]), float(cfg["--cadence-window"]), float(cfg["--probe-after"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
