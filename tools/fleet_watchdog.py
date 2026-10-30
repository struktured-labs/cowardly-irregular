#!/usr/bin/env python3
# fleet_watchdog.py -- detect a Claude Code session stalled on an API error and resume it.
#
# WHY THE DETECTOR KEYS ON THE *LAST* RECORD, NOT ON "AN ERROR ANYWHERE". A session that hit a
# 500 and retried has records after the error; one that is STALLED has the error as the last
# thing that ever happened. Measured 2026-10-29 on this box: 1,050 api-error records all time,
# of which only 2 are in the last 48h -- so "has an error in it" selects ~every long transcript
# and says nothing about whether anything is stuck.
#
# WHY IDLE SESSIONS ARE LOGGED BUT NEVER NUDGED. The outage this tool was built after was NOT an
# API stall. On 2026-10-13..15 the fleet took 182 rate_limit hits; three lanes then sat idle for
# TWO WEEKS at an empty prompt, each deliberately holding for a ruling (cowir-story had literally
# asked a question and chosen "stay down until told"). An auto-nudge would have poked them into
# guessing, which is the one thing a lane holding for a ruling must not do. So: API_STALL is
# mechanical and gets a keystroke; IDLE is a human's call and only gets surfaced.
#
# Exit 0 = pass ran (or every selftest arm held) * 1 = a selftest arm failed * 2 = bad invocation
import argparse, datetime, glob, json, os, re, subprocess, sys, time

ROOT_DEFAULT  = os.path.expanduser("~/.claude/projects")
FLEET_DIR     = os.path.expanduser("~/.claude/fleet")
LOG_DEFAULT   = os.path.join(FLEET_DIR, "watchdog.jsonl")
STATE_DEFAULT = os.path.join(FLEET_DIR, "watchdog_state.json")
# PREFILTER ON THE KEY, NOT ON ":true" -- the parsed value is the authority. Measured on this
# box: 1,159 records carry the key, 1,050 of them true, so the laxer prefilter costs 109 extra
# parses across 1,410 files and cannot be defeated by a space after the colon. The strict byte
# form matched real transcripts and silently missed this tool's own json.dumps fixtures.
MARK          = b'"isApiErrorMessage"'
TAIL_BYTES    = 262144
BACKOFF_BASE  = 60
BACKOFF_CAP   = 1800
MAX_ATTEMPTS  = 8

def now_ts():
    return time.time()

def iso(t):
    return datetime.datetime.fromtimestamp(t, datetime.timezone.utc).isoformat(timespec="seconds")

# ---------------------------------------------------------------- transcript reading
def last_record(path):
    """Last VALID json record in the file, or None. A truncated final line is skipped rather
    than crashing the pass -- a partially-flushed append is normal on a live transcript."""
    try:
        sz = os.path.getsize(path)
        with open(path, "rb") as fh:
            if sz > TAIL_BYTES:
                fh.seek(sz - TAIL_BYTES)
            blob = fh.read()
    except OSError:
        return None
    for line in reversed(blob.split(b"\n")):
        line = line.strip()
        if not line:
            continue
        try:
            return json.loads(line)
        except Exception:
            continue
    return None

def last_turn(path, max_bytes=16 * 1024 * 1024):
    """The last record a MODEL actually produced, scanning backward in chunks.

    AN ENTRY IS NOT A TURN, and keying on the file's mtime was this tool's worst defect:
    attachments, queue-operations, hook context and system notices all append without any
    turn occurring -- and a <task-notification> arrives with role "user", so even "last user
    record" is fooled. Measured 2026-10-29 by five lanes on their own transcripts: a shared
    "Remote Control disconnected -- OAuth token unavailable" system line appended to many
    files at one instant, and an mtime read called it activity in every one of them. The
    batch-resumed lanes had ZERO assistant records for 11d22h while their files kept growing.
    """
    try:
        sz = os.path.getsize(path)
    except OSError:
        return None
    chunk, pos, tail = 1024 * 1024, sz, b""
    while pos > 0 and (sz - pos) < max_bytes:
        step = min(chunk, pos)
        pos -= step
        try:
            with open(path, "rb") as fh:
                fh.seek(pos)
                tail = fh.read(step) + tail
        except OSError:
            return None
        lines = tail.split(b"\n")
        # the first element may be a partial line unless we are at the start of the file
        scan = lines if pos == 0 else lines[1:]
        for line in reversed(scan):
            line = line.strip()
            if not line or b'"assistant"' not in line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            if r.get("type") == "assistant":
                return r
        tail = lines[0] if pos > 0 else b""
    return None


def rec_ts(rec):
    try:
        return datetime.datetime.fromisoformat(
            rec["timestamp"].replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def assistant_text(rec):
    c = (rec.get("message") or {}).get("content") or []
    if isinstance(c, list):
        for b in c:
            if isinstance(b, dict) and b.get("type") == "text":
                return (b.get("text") or "").strip()
    return ""

def transcript_for(root, sid, cwd):
    """A sessionId is globally unique, so prefer a glob on it; fall back to the encoded cwd."""
    if sid:
        hits = glob.glob(os.path.join(root, "*", sid + ".jsonl"))
        if hits:
            return hits[0]
    if cwd:
        d = os.path.join(root, cwd.replace("/", "-"))
        js = glob.glob(os.path.join(d, "*.jsonl"))
        if js:
            return max(js, key=lambda p: os.path.getmtime(p))
    return None

# ---------------------------------------------------------------- session discovery
def ps_map():
    out = subprocess.run(["ps", "-eo", "pid=,ppid=,args="], capture_output=True, text=True).stdout
    m = {}
    for ln in out.splitlines():
        parts = ln.strip().split(None, 2)
        if len(parts) < 3:
            continue
        try:
            m[int(parts[0])] = (int(parts[1]), parts[2])
        except ValueError:
            continue
    return m

def discover_tmux():
    """[{tmux, cwd, sid, pid}] for every tmux session running a claude process."""
    r = subprocess.run(["tmux", "ls", "-F", "#{session_name}"], capture_output=True, text=True)
    if r.returncode != 0:
        return []
    pm = ps_map()
    kids = {}
    for pid, (ppid, _a) in pm.items():
        kids.setdefault(ppid, []).append(pid)
    sessions = []
    for name in r.stdout.split():
        p = subprocess.run(["tmux", "list-panes", "-t", name, "-F", "#{pane_pid}"],
                           capture_output=True, text=True)
        for ppid_s in p.stdout.split():
            try:
                pane_pid = int(ppid_s)
            except ValueError:
                continue
            stack, found = [pane_pid], None
            while stack:
                pid = stack.pop()
                args = pm.get(pid, (0, ""))[1]
                base = os.path.basename(args.split()[0]) if args.split() else ""
                if base == "claude" or args.startswith("claude ") or "/claude " in args:
                    found = (pid, args)
                    break
                stack.extend(kids.get(pid, []))
            if not found:
                continue
            pid, args = found
            mm = re.search(r"--resume\s+([0-9a-f-]{36})", args)
            try:
                cwd = os.readlink("/proc/%d/cwd" % pid)
            except OSError:
                cwd = None
            try:
                etimes = int(subprocess.run(["ps", "-o", "etimes=", "-p", str(pid)],
                                            capture_output=True, text=True).stdout.strip() or 0)
            except ValueError:
                etimes = 0
            sessions.append({"tmux": name, "cwd": cwd, "proc_age_secs": etimes,
                             "sid": mm.group(1) if mm else None, "pid": pid})
            break
    return sessions

def own_tmux_session(pm=None):
    """The tmux session this process is running inside, so the watchdog never nudges itself."""
    pm = pm or ps_map()
    pid = os.getpid()
    for _ in range(40):
        ent = pm.get(pid)
        if not ent:
            return None
        ppid, args = ent
        if args.split() and os.path.basename(args.split()[0]) == "tmux":
            m = re.search(r"-s\s+(\S+)", args)
            if m:
                return m.group(1)
        if ppid in (0, 1):
            return None
        pid = ppid
    return None

# ---------------------------------------------------------------- classification
def classify(sess, root, stall_secs, idle_hours):
    path = transcript_for(root, sess.get("sid"), sess.get("cwd"))
    out = dict(sess)
    out["transcript"] = path
    if not path or not os.path.exists(path):
        out["klass"] = "NO_TRANSCRIPT"
        return out
    out["project"] = os.path.basename(os.path.dirname(path))
    out["entry_age_secs"] = int(now_ts() - os.path.getmtime(path))
    # An api-error record IS an assistant record (model "<synthetic>"), so one scan answers
    # both questions: what the model last did, and how long ago it did it.
    rec = last_turn(path)
    if rec is None:
        # Entries exist but no model turn in reach -- the batch-resume shape. Keyed on the
        # absence of a turn rather than on a quiet file, which is the distinction that matters.
        out["klass"] = "ENTRIES_NO_TURNS" if last_record(path) else "NO_RECORD"
        out["idle_secs"] = out["entry_age_secs"]
        return out
    t = rec_ts(rec)
    age = (now_ts() - t) if t else (now_ts() - os.path.getmtime(path))
    out["idle_secs"] = int(age)
    is_err = bool(rec.get("isApiErrorMessage"))
    out["error"] = rec.get("error") if is_err else None
    out["text"] = assistant_text(rec)[:300]
    out["last_record_ts"] = rec.get("timestamp")
    # NO TURN SINCE THE PROCESS STARTED is the resume deadlock's exact signature, and it is the
    # one idle-looking state that is SAFE to nudge: a process that has never produced a turn cannot
    # be deliberately holding for a ruling -- it was never given the chance to decide. Measured
    # 2026-10-17..29: one batch resume left 13 lanes here for 12 days, because a resumed process
    # inherits the channel flag but not its intercom registration, and the SessionStart hook that
    # says to register is only read ON a turn. Nothing self-heals; a keystroke is the only break.
    pa = int(sess.get("proc_age_secs") or 0)
    if pa > 0 and age > pa and age >= stall_secs:
        out["klass"] = "NO_TURN_SINCE_START"
        out["proc_age_secs"] = pa
        return out
    if is_err:
        # A session that errored seconds ago may be retrying on its own; only a SETTLED error
        # is a stall. This is why stall_secs exists and why arm 5 pins it.
        out["klass"] = "API_STALL" if age >= stall_secs else "WORKING"
    elif age >= idle_hours * 3600:
        out["klass"] = "IDLE"
    elif age >= stall_secs:
        out["klass"] = "QUIET"
    else:
        out["klass"] = "WORKING"
    return out

# ---------------------------------------------------------------- state / backoff
def load_state(p):
    try:
        with open(p) as fh:
            return json.load(fh)
    except Exception:
        return {}

def save_state(p, st):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    tmp = p + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(st, fh, indent=1, sort_keys=True)
    os.replace(tmp, p)

def backoff_delay(attempts):
    return min(BACKOFF_BASE * (2 ** max(0, attempts - 1)), BACKOFF_CAP)

def log_event(log_path, ev):
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    with open(log_path, "a") as fh:
        fh.write(json.dumps(ev, sort_keys=True) + "\n")

# ---------------------------------------------------------------- one pass
def do_pass(args, sessions=None):
    root = args.root
    st = load_state(args.state)
    sessions = sessions if sessions is not None else discover_tmux()
    mine = args.exclude or own_tmux_session()
    rows = []
    for s in sessions:
        if mine and s.get("tmux") == mine:
            continue
        c = classify(s, root, args.stall_secs, args.idle_hours)
        key = c.get("sid") or (c.get("tmux") or "?")
        ent = st.get(key, {"attempts": 0, "last_nudge": 0.0, "last_seen_ts": None})
        action, delay = "none", None

        # RECOVERY RESET: the transcript moved on to a non-error record after our last nudge,
        # so whatever we did worked (or it recovered by itself) -- forget the attempt history.
        if c["klass"] not in ("API_STALL", "NO_TURN_SINCE_START") and ent.get("attempts"):
            ent = {"attempts": 0, "last_nudge": 0.0, "last_seen_ts": c.get("last_record_ts")}
            action = "reset"

        if c["klass"] in ("API_STALL", "NO_TURN_SINCE_START"):
            if ent["attempts"] >= args.max_attempts:
                c["klass"], action = "NEEDS_HUMAN", "none"
            else:
                delay = backoff_delay(ent["attempts"])
                waited = now_ts() - (ent.get("last_nudge") or 0)
                if ent["attempts"] == 0 or waited >= delay:
                    if args.act:
                        nudge(args, c)
                        action = "nudged"
                        ent["attempts"] += 1
                        ent["last_nudge"] = now_ts()
                    else:
                        # A --scan is READ-ONLY. Counting a would-nudge as an attempt let a
                        # diagnostic pass eat the backoff budget, so the real nudges that
                        # followed arrived already throttled -- pinned by arm18.
                        action = "would-nudge"
                else:
                    action = "backoff-wait"
        if args.act or action == "reset":
            st[key] = ent
        c["action"], c["attempt"] = action, ent["attempts"]
        c["backoff_secs"] = delay
        rows.append(c)
        if args.notify_cmd and c["klass"] in ("NEEDS_HUMAN", "IDLE", "ENTRIES_NO_TURNS") and not ent.get("notified"):
            subprocess.run(args.notify_cmd + [c["klass"], c.get("project") or "?",
                                              str(c.get("idle_secs") or 0), (c.get("text") or "")[:200]],
                           check=False)
            ent["notified"] = True
            st[key] = ent
            if args.act:
                save_state(args.state, st)
        if c["klass"] in ("API_STALL", "NEEDS_HUMAN", "IDLE", "NO_RECORD", "ENTRIES_NO_TURNS",
                          "NO_TURN_SINCE_START") or action in ("nudged", "would-nudge"):
            log_event(args.log, {"ts": iso(now_ts()), "klass": c["klass"], "tmux": c.get("tmux"),
                                 "project": c.get("project"), "sid": c.get("sid"),
                                 "error": c.get("error"), "idle_secs": c.get("idle_secs"),
                                 "action": action, "attempt": ent["attempts"],
                                 "backoff_secs": delay, "text": c.get("text", "")[:200]})
    if args.tick:
        do_tick(args, rows, st)
    if args.act:
        save_state(args.state, st)
    return rows

def do_tick(args, rows, st):
    """One lane gets its hourly prompt, subject to a budget, or nobody does.

    WHY A TICK IS NEEDED AT ALL: a lane that finishes its work and goes quiet is not woken by
    anything -- six lanes measured that on 2026-10-29, and one batch resume cost the fleet twelve
    days. WHY IT IS BUDGETED: the 182 rate_limit hits of 2026-10-13..15 came from the whole fleet
    working at once, so the danger is not the tick, it is the WORK a tick starts. Hence a cap on
    how many lanes may be active, a fleet-wide minimum gap, and an hourly ceiling -- and every
    refusal is logged with its reason, because a silent skip is indistinguishable from a tick."""
    now = now_ts()
    log = [t for t in st.get("_ticks", []) if now - t < 3600]
    st["_ticks"] = log

    def refuse(why, **kw):
        log_event(args.log, dict({"ts": iso(now), "klass": "TICK", "action": "skipped",
                                  "reason": why}, **kw))
        return None

    if args.tick_guard_cmd:
        # exit 0 means "hold off" -- box_busy.sh --publish exits 0 when a publish is IN FLIGHT
        import shlex
        cmd = (shlex.split(args.tick_guard_cmd)
               if isinstance(args.tick_guard_cmd, str) else list(args.tick_guard_cmd))
        if subprocess.run(cmd, capture_output=True).returncode == 0:
            return refuse("guard-cmd says hold")
    if len(log) >= args.tick_max_per_hour:
        return refuse("hourly ceiling", ticks_this_hour=len(log))
    if log and (now - max(log)) < args.tick_min_gap:
        return refuse("min-gap", since_last=int(now - max(log)))

    lanes = [r for r in rows if (r.get("project") or "").startswith("-home")
             and args.tick_prefix in (r.get("project") or "")]
    active = [r for r in lanes if (r.get("idle_secs") is not None
                                   and r["idle_secs"] < args.tick_active_window)]
    if len(active) >= args.tick_max_active:
        return refuse("budget: lanes already working", active=len(active))

    # oldest-silent first, and never a lane that is working or already in a nudged state
    due = [r for r in lanes
           if r.get("idle_secs") is not None
           and r["idle_secs"] >= args.tick_active_window
           and r["klass"] not in ("API_STALL", "NEEDS_HUMAN", "NO_TURN_SINCE_START")
           and (now - float(st.get(r.get("sid") or r["tmux"], {}).get("last_tick", 0)))
               >= args.tick_interval]
    if not due:
        return refuse("none due")
    pick = max(due, key=lambda r: r["idle_secs"])
    if args.act:
        nudge(args, pick, text=args.tick_text)
    ent = st.setdefault(pick.get("sid") or pick["tmux"], {"attempts": 0, "last_nudge": 0.0})
    ent["last_tick"] = now
    st["_ticks"] = log + [now]
    log_event(args.log, {"ts": iso(now), "klass": "TICK",
                         "action": "ticked" if args.act else "would-tick",
                         "project": pick.get("project"), "tmux": pick.get("tmux"),
                         "idle_secs": pick.get("idle_secs"), "active": len(active)})
    return pick


def nudge(args, c, text=None):
    """Resubmit in the stalled pane. A stalled Claude TUI needs a prompt, not a signal."""
    if args.nudge_cmd:
        subprocess.run(args.nudge_cmd + [c.get("tmux") or "", c.get("sid") or "",
                                         (text or args.nudge_text)[:40]], check=False)
        return
    t = c.get("tmux")
    if not t:
        return
    subprocess.run(["tmux", "send-keys", "-t", t, "-l", text or args.nudge_text], check=False)
    subprocess.run(["tmux", "send-keys", "-t", t, "Enter"], check=False)

# ---------------------------------------------------------------- report
def report(root, hours):
    cut = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=hours)
    rows, total, files = [], 0, 0
    for d, _s, fs in os.walk(root):
        for f in fs:
            if not f.endswith(".jsonl"):
                continue
            files += 1
            try:
                with open(os.path.join(d, f), "rb") as fh:
                    for line in fh:
                        if MARK not in line:
                            continue
                        try:
                            r = json.loads(line)
                        except Exception:
                            continue
                        if not r.get("isApiErrorMessage"):
                            continue
                        total += 1
                        try:
                            t = datetime.datetime.fromisoformat(
                                r["timestamp"].replace("Z", "+00:00"))
                        except Exception:
                            continue
                        if t >= cut:
                            rows.append((t, r.get("error", "?"), os.path.basename(d),
                                         assistant_text(r)[:90]))
            except OSError:
                continue
    rows.sort()
    import collections
    print("files scanned           %d" % files)
    print("api-error records, all  %d" % total)
    print("INCIDENTS IN LAST %-3gh  %d" % (hours, len(rows)))
    if rows:
        print("\nby class:")
        for k, v in collections.Counter(r[1] for r in rows).most_common():
            print("  %5d  %s" % (v, k))
        print("\nby lane:")
        for k, v in collections.Counter(r[2] for r in rows).most_common():
            print("  %5d  %s" % (v, k))
        print("\nincidents:")
        for t, e, p, tx in rows:
            print("  %s  %-14s %-44s %s" % (t.isoformat(timespec="seconds"), e, p, tx))
    return len(rows)

# ---------------------------------------------------------------- main
def build_parser():
    ap = argparse.ArgumentParser(description="watch Claude sessions for API stalls")
    ap.add_argument("--report", nargs="?", const=48, type=float, metavar="HOURS")
    ap.add_argument("--scan", action="store_true", help="classify only, never act")
    ap.add_argument("--once", action="store_true", help="classify and act")
    ap.add_argument("--loop", nargs="?", const=300, type=float, metavar="SECS")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--root", default=ROOT_DEFAULT)
    ap.add_argument("--log", default=LOG_DEFAULT)
    ap.add_argument("--state", default=STATE_DEFAULT)
    ap.add_argument("--stall-secs", dest="stall_secs", type=float, default=120)
    ap.add_argument("--idle-hours", dest="idle_hours", type=float, default=2)
    ap.add_argument("--max-attempts", dest="max_attempts", type=int, default=MAX_ATTEMPTS)
    ap.add_argument("--nudge-text", dest="nudge_text", default="continue")
    ap.add_argument("--nudge-cmd", dest="nudge_cmd", nargs="+", default=None)
    ap.add_argument("--sessions-json", dest="sessions_json", default=None)
    ap.add_argument("--exclude", default=None)
    # IDLE is a REPORT, not a repair -- see the header. A log nobody opens is not "surfaced",
    # so an escalation hook can be attached; it fires ONCE per lane per threshold crossing.
    ap.add_argument("--notify-cmd", dest="notify_cmd", nargs="+", default=None)
    # --- the staggered hourly lane tick (struktured, 2026-10-29) ---------------------------
    ap.add_argument("--tick", action="store_true",
                    help="also give each lane its hourly tick, staggered and budgeted")
    ap.add_argument("--tick-interval", dest="tick_interval", type=float, default=3600)
    ap.add_argument("--tick-min-gap", dest="tick_min_gap", type=float, default=300,
                    help="minimum seconds between ANY two ticks fleet-wide -- this is the stagger")
    ap.add_argument("--tick-max-active", dest="tick_max_active", type=int, default=4,
                    help="skip ticking while this many lanes are already working (the budget)")
    ap.add_argument("--tick-active-window", dest="tick_active_window", type=float, default=1200)
    ap.add_argument("--tick-max-per-hour", dest="tick_max_per_hour", type=int, default=13)
    ap.add_argument("--tick-prefix", dest="tick_prefix", default="cowir-")
    # ONE STRING, shlex-split -- NOT nargs="+", which cannot accept a command whose own
    # argument starts with a dash: `--tick-guard-cmd tools/box_busy.sh --publish` made argparse
    # claim --publish as an unknown option of ours and print usage instead of running.
    # The real guard is exactly that shape, so nargs="+" was unusable for its only use case.
    ap.add_argument("--tick-guard-cmd", dest="tick_guard_cmd", default=None,
                    help="shell-quoted command whose EXIT 0 means 'hold off', "
                         "e.g. --tick-guard-cmd 'tools/box_busy.sh --publish'")
    ap.add_argument("--tick-text", dest="tick_text",
                    default="Hourly tick: pick ONE feature or fix in your lane and land it. "
                            "Check tools/box_busy.sh and the channel queue before any godot run.")
    return ap

def print_rows(rows):
    if not rows:
        print("no claude sessions found")
        return
    order = {"NEEDS_HUMAN": 0, "NO_TURN_SINCE_START": 1, "API_STALL": 2, "ENTRIES_NO_TURNS": 3,
             "NO_RECORD": 4, "IDLE": 5, "QUIET": 6, "NO_TRANSCRIPT": 7, "WORKING": 8}
    for c in sorted(rows, key=lambda r: (order.get(r["klass"], 9), -(r.get("idle_secs") or 0))):
        idle = c.get("idle_secs")
        idle_s = "%6.1fh" % (idle / 3600.0) if idle is not None else "      -"
        print("  %-12s %-9s %-34s %-10s %s" % (
            c["klass"], idle_s, (c.get("project") or c.get("tmux") or "?")[:34],
            c.get("action", ""), (c.get("text") or "")[:70].replace("\n", " ")))

def main(argv):
    args = build_parser().parse_args(argv)
    if args.selftest:
        return selftest()
    if args.report is not None:
        report(args.root, args.report)
        return 0
    sessions = None
    if args.sessions_json:
        with open(args.sessions_json) as fh:
            sessions = json.load(fh)
    args.act = bool(args.once or args.loop)
    if args.loop:
        while True:
            print("--- %s" % iso(now_ts()))
            print_rows(do_pass(args, sessions))
            time.sleep(args.loop)
    if args.once or args.scan:
        print_rows(do_pass(args, sessions))
        return 0
    build_parser().print_help()
    return 2

# ---------------------------------------------------------------- selftest (hermetic)
def selftest():
    import tempfile, shutil
    fails = []
    def ck(name, cond, detail=""):
        if not cond:
            fails.append("%s: %s" % (name, detail))
    T = tempfile.mkdtemp(prefix="fleetwd_")
    try:
        root = os.path.join(T, "projects")
        proj = os.path.join(root, "-home-x-lane")
        os.makedirs(proj)
        nudges = os.path.join(T, "nudges.txt")
        stub = os.path.join(T, "stub.sh")
        with open(stub, "w") as fh:
            fh.write("#!/usr/bin/env bash\necho \"$@\" >> %s\n" % nudges)
        os.chmod(stub, 0o755)

        def write_tx(sid, recs, age_secs, extra=None):
            p = os.path.join(proj, sid + ".jsonl")
            with open(p, "w") as fh:
                for r in recs:
                    # stamp the RECORD to the intended age: the tool reads the turn's own
                    # timestamp now, so a fixture that backdates only the mtime tests nothing
                    r = dict(r, timestamp=iso(now_ts() - age_secs))
                    fh.write(json.dumps(r, separators=(",", ":")) + "\n")
                for r in (extra or []):      # appended AFTER the turn, as a real tail does
                    fh.write(json.dumps(r, separators=(",", ":")) + "\n")
            t = time.time() - age_secs
            os.utime(p, (t, t))
            return p

        def err_rec(msg="API Error: Overloaded"):
            # a real api-error record IS type=assistant with model "<synthetic>"
            return {"timestamp": iso(now_ts()), "type": "assistant", "isApiErrorMessage": True,
                    "error": "server_error",
                    "message": {"content": [{"type": "text", "text": msg}]}}

        def ok_rec(msg="done"):
            return {"timestamp": iso(now_ts()), "type": "assistant",
                    "message": {"content": [{"type": "text", "text": msg}]}}

        def mkargs(**kw):
            a = build_parser().parse_args([])
            a.root, a.log, a.state = root, os.path.join(T, "log.jsonl"), os.path.join(T, "st.json")
            a.nudge_cmd = [stub]
            a.act = True
            a.exclude = "__none__"
            for k, v in kw.items():
                setattr(a, k, v)
            return a

        def nudge_count():
            try:
                return sum(1 for _ in open(nudges))
            except OSError:
                return 0

        S = lambda sid: [{"tmux": "t-" + sid, "cwd": "/home/x/lane", "sid": sid, "pid": 0}]

        # 1 settled api error -> API_STALL and a nudge
        write_tx("s1", [ok_rec(), err_rec()], 600)
        a = mkargs()
        r = do_pass(a, S("s1"))[0]
        ck("arm1", r["klass"] == "API_STALL" and r["action"] == "nudged" and nudge_count() == 1,
           "klass=%s action=%s nudges=%d" % (r["klass"], r["action"], nudge_count()))

        # 2 POSITIVE CONTROL for the stub itself -- arm 1's count must have come from the real path
        ck("arm2-control", nudge_count() == 1, "stub recorded %d" % nudge_count())

        # 3 immediately again -> inside backoff, no second nudge
        r = do_pass(a, S("s1"))[0]
        ck("arm3", r["action"] == "backoff-wait" and nudge_count() == 1,
           "action=%s nudges=%d" % (r["action"], nudge_count()))

        # 4 backoff elapsed -> nudge again, attempt 2
        st = load_state(a.state); st["s1"]["last_nudge"] = now_ts() - 10_000; save_state(a.state, st)
        r = do_pass(a, S("s1"))[0]
        ck("arm4", r["action"] == "nudged" and r["attempt"] == 2 and nudge_count() == 2,
           "action=%s attempt=%s nudges=%d" % (r["action"], r["attempt"], nudge_count()))

        # 5 delay grows with attempts
        ck("arm5", backoff_delay(1) == 60 and backoff_delay(2) == 120 and backoff_delay(99) == BACKOFF_CAP,
           "%s %s %s" % (backoff_delay(1), backoff_delay(2), backoff_delay(99)))

        # 6 at the cap -> NEEDS_HUMAN, stop poking
        st = load_state(a.state); st["s1"] = {"attempts": 8, "last_nudge": 0.0}; save_state(a.state, st)
        before = nudge_count()
        r = do_pass(a, S("s1"))[0]
        ck("arm6", r["klass"] == "NEEDS_HUMAN" and nudge_count() == before,
           "klass=%s nudges %d->%d" % (r["klass"], before, nudge_count()))

        # 7 a FRESH error is a session still retrying -> WORKING, not a stall
        write_tx("s2", [err_rec()], 5)
        before = nudge_count()
        r = do_pass(mkargs(), S("s2"))[0]
        ck("arm7", r["klass"] == "WORKING" and nudge_count() == before,
           "klass=%s nudges %d->%d" % (r["klass"], before, nudge_count()))

        # 8 idle for 10h, last record NOT an error -> IDLE and NEVER nudged
        write_tx("s3", [ok_rec("Holding. clean, nothing posted.")], 36_000)
        before = nudge_count()
        r = do_pass(mkargs(), S("s3"))[0]
        ck("arm8", r["klass"] == "IDLE" and r["action"] == "none" and nudge_count() == before,
           "klass=%s action=%s nudges %d->%d" % (r["klass"], r["action"], before, nudge_count()))

        # 9 the IDLE text is carried into the row, so a human can see WHAT it is holding for
        ck("arm9", "Holding" in (r.get("text") or ""), "text=%r" % r.get("text"))

        # 10 recovery after a nudge resets the attempt counter
        write_tx("s4", [err_rec()], 600)
        a4 = mkargs()
        do_pass(a4, S("s4"))
        ck("arm10a", load_state(a4.state)["s4"]["attempts"] == 1, "no attempt recorded")
        write_tx("s4", [err_rec(), ok_rec("recovered")], 600)
        r = do_pass(a4, S("s4"))[0]
        ck("arm10b", r["action"] == "reset" and load_state(a4.state)["s4"]["attempts"] == 0,
           "action=%s attempts=%s" % (r["action"], load_state(a4.state)["s4"]["attempts"]))

        # 11 a truncated final line does not crash; the last VALID record decides
        p = write_tx("s5", [err_rec()], 600)
        with open(p, "a") as fh:
            fh.write('{"timestamp":"2026-10-2')
        t = time.time() - 600          # the append reset mtime; a stall is judged on mtime
        os.utime(p, (t, t))
        r = do_pass(mkargs(), S("s5"))[0]
        ck("arm11", r["klass"] == "API_STALL", "klass=%s" % r["klass"])

        # 12 a missing transcript is reported, not fatal
        r = do_pass(mkargs(), [{"tmux": "t-x", "cwd": "/nope", "sid": "deadbeef", "pid": 0}])[0]
        ck("arm12", r["klass"] == "NO_TRANSCRIPT", "klass=%s" % r["klass"])

        # 13 every event that mattered reached the log
        lines = [json.loads(l) for l in open(os.path.join(T, "log.jsonl"))]
        ck("arm13", any(l["klass"] == "API_STALL" for l in lines)
                    and any(l["klass"] == "IDLE" for l in lines)
                    and any(l["action"] == "nudged" for l in lines),
           "log classes=%s" % sorted({l["klass"] for l in lines}))

        # 14 --report counts by RECORD timestamp, not by file mtime
        old = {"timestamp": "2026-01-01T00:00:00.000Z", "isApiErrorMessage": True,
               "error": "rate_limit", "message": {"content": [{"type": "text", "text": "old"}]}}
        # `old` goes in the un-stamped tail: write_tx re-dates the records it stamps, which
        # would make the deliberately-ancient one recent and leave the window untestable.
        write_tx("s6", [err_rec(), err_rec()], 10, extra=[old])
        n = report(root, 48)
        ck("arm14", n >= 2, "report returned %s" % n)

        # 15 the window really excludes the old one: a 1h window must not count it
        n1 = report(root, 1)
        ck("arm15", n1 >= 2, "1h window returned %s" % n1)
        n_wide = report(root, 24 * 3650)
        ck("arm16", n_wide > n1, "wide=%s narrow=%s -- window has no effect" % (n_wide, n1))

        # 19 the escalation hook fires ONCE per lane, not once per pass
        notif = os.path.join(T, "notif.txt")
        hook = os.path.join(T, "hook.sh")
        with open(hook, "w") as fh:
            fh.write("#!/usr/bin/env bash\necho \"$@\" >> %s\n" % notif)
        os.chmod(hook, 0o755)
        write_tx("s8", [ok_rec("Holding for a ruling.")], 36_000)
        a8 = mkargs(notify_cmd=[hook])
        do_pass(a8, S("s8")); do_pass(a8, S("s8")); do_pass(a8, S("s8"))
        lines = open(notif).read().splitlines() if os.path.exists(notif) else []
        ck("arm19a", len(lines) == 1, "hook fired %d times across 3 passes: %s" % (len(lines), lines))
        ck("arm19b", lines and lines[0].startswith("IDLE") and "Holding for a ruling" in lines[0],
           "hook payload=%r" % (lines[0] if lines else None))

        # 24 THE RESUME DEADLOCK: a process younger than its last turn has never produced one,
        #    so it is holding nothing and IS safe to nudge -- unlike IDLE.
        write_tx("s13", [ok_rec("pre-resume work")], 36_000)
        S13 = [{"tmux": "t-s13", "cwd": "/home/x/lane", "sid": "s13", "pid": 0,
                "proc_age_secs": 600}]          # process 10 min old, last turn 10 HOURS old
        before = nudge_count()
        r = do_pass(mkargs(), S13)[0]
        ck("arm24a", r["klass"] == "NO_TURN_SINCE_START", "klass=%s" % r["klass"])
        ck("arm24b", r["action"] == "nudged" and nudge_count() == before + 1,
           "the deadlock must be nudged: action=%s nudges %d->%d" % (r["action"], before, nudge_count()))

        # 25 CONTROL: a turn TAKEN since the process started is not the deadlock
        write_tx("s14", [ok_rec("post-resume work")], 300)
        S14 = [{"tmux": "t-s14", "cwd": "/home/x/lane", "sid": "s14", "pid": 0,
                "proc_age_secs": 36_000}]       # process 10h old, turn 5 min old
        before = nudge_count()
        r = do_pass(mkargs(), S14)[0]
        ck("arm25", r["klass"] != "NO_TURN_SINCE_START" and nudge_count() == before,
           "a worked-since-start session was called a deadlock: klass=%s" % r["klass"])

        # 26 CONTROL: unknown process age must NOT trigger it -- never nudge on missing data
        write_tx("s15", [ok_rec("old")], 36_000)
        S15 = [{"tmux": "t-s15", "cwd": "/home/x/lane", "sid": "s15", "pid": 0, "proc_age_secs": 0}]
        before = nudge_count()
        r = do_pass(mkargs(), S15)[0]
        ck("arm26", r["klass"] == "IDLE" and nudge_count() == before,
           "missing proc age triggered a nudge: klass=%s nudges %d->%d" % (r["klass"], before, nudge_count()))

        # 20 THE DEFECT: entries appended after the last turn must NOT read as activity.
        #    A shared "Remote Control disconnected" system line appended to many transcripts
        #    at one instant, and an mtime read called every one of them alive.
        sysline = {"timestamp": iso(now_ts()), "type": "system", "subtype": "informational",
                   "content": "Remote Control disconnected - OAuth token unavailable"}
        attach = {"timestamp": iso(now_ts()), "type": "attachment"}
        tasknote = {"timestamp": iso(now_ts()), "type": "user",
                    "message": {"role": "user", "content": "<task-notification>done</task-notification>"}}
        write_tx("s9", [ok_rec("real work")], 36_000, extra=[attach, sysline])
        os.utime(os.path.join(proj, "s9.jsonl"), None)       # mtime = NOW, as an append gives
        r = do_pass(mkargs(), S("s9"))[0]
        ck("arm20a", r["klass"] == "IDLE",
           "entries after the turn read as activity: klass=%s" % r["klass"])
        ck("arm20b", r["idle_secs"] > 30_000,
           "idle came from mtime, not the turn: idle_secs=%s" % r.get("idle_secs"))
        ck("arm20c", r.get("entry_age_secs", 9999) < 120,
           "entry_age must still be reported, and be fresh: %s" % r.get("entry_age_secs"))

        # 21 a <task-notification> arrives with role "user" -- the check that fools a
        #    "last user record" heuristic specifically
        write_tx("s10", [ok_rec("real work")], 36_000, extra=[tasknote])
        os.utime(os.path.join(proj, "s10.jsonl"), None)
        r = do_pass(mkargs(), S("s10"))[0]
        ck("arm21", r["klass"] == "IDLE" and r["idle_secs"] > 30_000,
           "a machine user-record read as a turn: klass=%s idle=%s" % (r["klass"], r.get("idle_secs")))

        # 22 entries but ZERO model turns -- the batch-resume shape, its own class
        write_tx("s11", [], 10, extra=[attach, attach, sysline])
        r = do_pass(mkargs(), S("s11"))[0]
        ck("arm22", r["klass"] == "ENTRIES_NO_TURNS", "klass=%s" % r["klass"])

        # 23 POSITIVE CONTROL: a genuinely fresh turn is still WORKING, so arm20 is not
        #    passing because everything now reads IDLE
        write_tx("s12", [ok_rec("just now")], 5)
        r = do_pass(mkargs(), S("s12"))[0]
        ck("arm23", r["klass"] == "WORKING", "a fresh turn must read WORKING: %s" % r["klass"])

        # 18 a --scan is read-only: it names the stall but spends no backoff budget
        write_tx("s7", [err_rec()], 600)
        a7 = mkargs(act=False)
        before_n = nudge_count()
        r = do_pass(a7, S("s7"))[0]
        ck("arm18a", r["klass"] == "API_STALL" and r["action"] == "would-nudge",
           "klass=%s action=%s" % (r["klass"], r["action"]))
        ck("arm18b", "s7" not in load_state(a7.state) and nudge_count() == before_n,
           "scan mutated state=%s nudges %d->%d" % (load_state(a7.state).get("s7"), before_n, nudge_count()))
        # and the very next ACTING pass still gets attempt 1, undiminished
        r = do_pass(mkargs(), S("s7"))[0]
        ck("arm18c", r["action"] == "nudged" and r["attempt"] == 1,
           "action=%s attempt=%s" % (r["action"], r["attempt"]))

        # ── the hourly tick: every refusal reason gets an arm, because a budget nobody has
        #    watched refuse is worth nothing, and a silent skip looks exactly like a tick ──
        def ticks_of(logp):
            try:
                return [json.loads(l) for l in open(logp) if '"TICK"' in l]
            except OSError:
                return []

        def tickargs(name="shared", **kw):
            a = mkargs(tick=True, tick_prefix="x-lane", tick_active_window=1200,
                       tick_interval=3600, tick_min_gap=300, tick_max_active=4,
                       tick_max_per_hour=13, tick_guard_cmd=None)
            a.log = os.path.join(T, "ticklog_%s.jsonl" % name)
            a.state = os.path.join(T, "tickstate_%s.json" % name)
            for k, v in kw.items():
                setattr(a, k, v)
            return a

        write_tx("t1", [ok_rec("quiet lane")], 7200)      # silent 2h -> due
        T1 = [{"tmux": "t-t1", "cwd": "/home/x/lane", "sid": "t1", "pid": 0, "proc_age_secs": 99999}]

        # 27 a due, silent lane is ticked, with the TICK text and not the nudge text
        a = tickargs()
        before = nudge_count()
        do_pass(a, T1)
        ck("arm27a", nudge_count() == before + 1, "no tick fired: %d->%d" % (before, nudge_count()))
        ck("arm27b", any(t["action"] == "ticked" for t in ticks_of(a.log)),
           "tick not logged: %s" % ticks_of(a.log))
        ck("arm27c", "Hourly tick" in open(nudges).read(),
           "the tick sent the wrong text")

        # 28 immediately again -> refused by the fleet-wide MIN GAP, with that reason logged
        before = nudge_count()
        do_pass(a, T1)
        ck("arm28", nudge_count() == before
                    and any(t.get("reason") == "min-gap" for t in ticks_of(a.log)),
           "min-gap not enforced/logged: nudges %d->%d reasons=%s"
           % (before, nudge_count(), [t.get("reason") for t in ticks_of(a.log)]))

        # 29 THE BUDGET: too many lanes already working -> refuse, reason logged
        write_tx("t2", [ok_rec("busy lane")], 10)        # active
        T2 = T1 + [{"tmux": "t-t2", "cwd": "/home/x/lane", "sid": "t2", "pid": 0,
                    "proc_age_secs": 99999}]
        a2 = tickargs("budget", tick_max_active=1)
        before = nudge_count()
        do_pass(a2, T2)
        ck("arm29", nudge_count() == before
                    and any(t.get("reason", "").startswith("budget") for t in ticks_of(a2.log)),
           "budget did not refuse: nudges %d->%d" % (before, nudge_count()))

        # 30 the hourly CEILING refuses even with nothing else in the way
        a3 = tickargs("ceiling", tick_max_per_hour=2)
        st3 = {"_ticks": [now_ts() - 10, now_ts() - 20]}
        save_state(a3.state, st3)
        before = nudge_count()
        do_pass(a3, T1)
        ck("arm30", nudge_count() == before
                    and any(t.get("reason") == "hourly ceiling" for t in ticks_of(a3.log)),
           "ceiling did not refuse: nudges %d->%d" % (before, nudge_count()))

        # 31 the GUARD (exit 0 = hold, matching box_busy.sh --publish) refuses; exit 1 proceeds
        hold = os.path.join(T, "hold.sh"); go = os.path.join(T, "go.sh")
        open(hold, "w").write("#!/usr/bin/env bash\nexit 0\n")
        open(go, "w").write("#!/usr/bin/env bash\nexit 1\n")
        os.chmod(hold, 0o755); os.chmod(go, 0o755)
        a4 = tickargs("hold", tick_guard_cmd=[hold]); before = nudge_count()
        do_pass(a4, T1)
        ck("arm31a", nudge_count() == before
                     and any(t.get("reason") == "guard-cmd says hold" for t in ticks_of(a4.log)),
           "guard did not hold")
        # 34 the guard accepts a DASH-CARRYING argument as one shlex string -- the real shape
        flagged = os.path.join(T, "flagged.sh")
        open(flagged, "w").write('#!/usr/bin/env bash\n[ "$1" = "--publish" ] && exit 0\nexit 1\n')
        os.chmod(flagged, 0o755)
        a4b = tickargs("flag", tick_guard_cmd="%s --publish" % flagged); before = nudge_count()
        do_pass(a4b, T1)
        ck("arm34a", nudge_count() == before
                     and any(t.get("reason") == "guard-cmd says hold" for t in ticks_of(a4b.log)),
           "a dash-carrying guard arg did not reach the command")
        a4c = tickargs("noflag", tick_guard_cmd=flagged); before = nudge_count()
        do_pass(a4c, T1)
        ck("arm34b", nudge_count() == before + 1,
           "without --publish the same guard must exit 1 and let the tick through")

        a5 = tickargs("go", tick_guard_cmd=[go]); before = nudge_count()
        do_pass(a5, T1)
        ck("arm31b", nudge_count() == before + 1, "guard exit 1 should have let the tick through")

        # 32 a lane in the DEADLOCK class is not ALSO ticked -- it is already being nudged
        write_tx("t3", [ok_rec("pre-resume")], 7200)
        T3 = [{"tmux": "t-t3", "cwd": "/home/x/lane", "sid": "t3", "pid": 0, "proc_age_secs": 600}]
        a6 = tickargs("deadlock"); before = nudge_count()
        r = do_pass(a6, T3)[0]
        ck("arm32", r["klass"] == "NO_TURN_SINCE_START" and nudge_count() == before + 1,
           "expected exactly ONE poke (the deadlock nudge), got klass=%s nudges %d->%d"
           % (r["klass"], before, nudge_count()))

        # 33 a WORKING lane is never ticked, and the reason is "none due" not a budget refusal
        write_tx("t4", [ok_rec("busy")], 30)
        T4 = [{"tmux": "t-t4", "cwd": "/home/x/lane", "sid": "t4", "pid": 0, "proc_age_secs": 99999}]
        a7 = tickargs("nonedue"); before = nudge_count()
        do_pass(a7, T4)
        ck("arm33", nudge_count() == before
                    and any(t.get("reason") == "none due" for t in ticks_of(a7.log)),
           "a working lane was ticked or refused for the wrong reason")

        # 17 the watchdog excludes its own tmux session
        a = mkargs(exclude="t-s1")
        rows = do_pass(a, S("s1"))
        ck("arm17", rows == [], "did not exclude itself: %s" % rows)
    finally:
        shutil.rmtree(T, ignore_errors=True)
    if fails:
        print("SELFTEST FAILED (%d):" % len(fails))
        for f in fails:
            print("  " + f)
        return 1
    print("fleet_watchdog selftest: 46 arms ran, every assertion held")
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
