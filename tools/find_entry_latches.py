#!/usr/bin/env python3
"""Find re-entrancy latches released below work that can abort.

    if _latch: return      <- entry guard: makes the strand unrecoverable by re-entry
    _latch = true
    ...work...             <- a GDScript error here aborts the enclosing function
    _latch = false         <- never runs; the latch is stranded TRUE

Found by cowir-battle on GameLoop._stop_autogrind, derived fleet-wide 2026-09-18.

⛔ PYTHON ON PURPOSE — DO NOT PORT THIS TO `grep -E`. The core test is indentation, and
`\\t` in POSIX ERE is an escaped literal 't', so `grep -cE '^\\t+return'` returns 0 on a file
with hundreds. It is not dead — it matches lines beginning with the LETTER t. In GNU ERE
`\\s`, `\\w` and `\\b` do work; `\\t` is the one that lies. Here `\\t` is a real tab.

⚠️ THIS REPORTS A SHAPE, NOT A DEFECT. Four discriminators decide whether a site matters, and
three of them cannot be derived from the source of one function:

  is a recovery ARMED in the same breath?     a watchdog/timeout at the raise  (cowir-music)
  how many CLEARS exist in src/?              0 clears = a MEMO, not a latch   (cowir-sprites)
  is everything after the flag RE-ESTABLISHED at the next entry?               (cowir-autogrind)
  is the recovery REACHABLE from the strand?  a frozen player cannot trigger
                                              the scene change that frees them (cowir-ai)

No recovery classifier is included BECAUSE MINE WAS WRONG: I keyed on `create_timer` near the
clear, and JukeboxMenu's `create_timer(0.05)` is an await for pacing. The instrument called the
one file I owned SAFE while it held the live bug. Read the site; do not let a column decide.

Usage:
    tools/find_entry_latches.py [path ...]     default: src
    tools/find_entry_latches.py --control      prove the detector can say YES before trusting a 0
"""
import os
import re
import sys

MIN_GAP = 3  # lines of work after the raise before a strand is worth looking at


def _next_code(body, j):
    for k in range(j + 1, len(body)):
        t = body[k].strip()
        if t and not t.startswith("#"):
            return t
    return ""


def scan_text(src_lines, path="<text>"):
    """Yield one row per entry-latch site."""
    funcs = []
    for i, line in enumerate(src_lines):
        m = re.match(r"^(static )?func (\w+)", line)
        if m:
            funcs.append((i, m.group(2)))
    funcs.append((len(src_lines), None))

    rows = []
    for (start, name), (end, _) in zip(funcs, funcs[1:]):
        if name is None:
            break
        body = src_lines[start:end]

        # The guard must be INSIDE this function's first lines and followed by a return.
        # Position, not count: two files can each hold exactly one `if _flag:` where one is a
        # re-entry guard and the other is an input router 300 lines away.
        guard = None
        for j, line in enumerate(body[:8]):
            m = re.search(r"if (not )?([A-Za-z_]\w*)\s*:\s*(return)?\s*$", line)
            if m and m.group(2) not in ("true", "false"):
                nxt = body[j + 1] if j + 1 < len(body) else ""
                if m.group(3) or re.match(r"^\s+return\s*$", nxt):
                    guard = m.group(2)
                    break
        if guard is None:
            continue

        # The entry latch is the assignment the function CONTINUES PAST. An assignment whose
        # next code line is `return` sits on a terminal branch and commits nothing downstream,
        # because there is no downstream (8 of 30 were this shape on first derivation).
        raise_at = None
        for j, line in enumerate(body):
            if re.search(rf"^\s*{re.escape(guard)}\s*=\s*(false|true|null)", line):
                if _next_code(body, j).startswith("return"):
                    continue
                raise_at = j
                break
        if raise_at is None:
            continue

        last = max(j for j, line in enumerate(body) if line.strip() and not line.strip().startswith("#"))
        gap = last - raise_at
        if gap < MIN_GAP:
            continue
        window = body[raise_at + 1:last + 1]
        calls = sum(1 for line in window if re.search(r"\w+\.\w+\(|^\s*await ", line))
        awaits = sum(1 for line in window if "await " in line)
        rows.append((path, name, guard, start + raise_at + 1, gap, calls, awaits))
    return rows


def scan_file(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return scan_text(fh.read().split("\n"), path)


CONTROL_POSITIVE = """extends Node

var _busy: bool = false

func work() -> void:
\tif _busy:
\t\treturn
\t_busy = true
\tawait get_tree().process_frame
\tthing.that_can_abort()
\tmore.work()
\t_busy = false
"""

CONTROL_NEGATIVE = """extends Node

var _loaded: bool = false

func load_it() -> void:
\tif _loaded:
\t\treturn
\tif not FileAccess.file_exists("x"):
\t\t_loaded = true
\t\treturn
\t_loaded = true
"""


def run_control():
    """A zero is only evidence once the instrument has been watched saying YES."""
    pos = scan_text(CONTROL_POSITIVE.split("\n"), "<control:positive>")
    neg = scan_text(CONTROL_NEGATIVE.split("\n"), "<control:negative>")
    ok_pos = len(pos) == 1 and pos[0][2] == "_busy"
    ok_neg = len(neg) == 0  # every `_loaded = true` is on a terminal branch
    print(f"  positive control (latch released below abortable work): {len(pos)} hit  "
          f"{'PASS' if ok_pos else 'FAIL'}")
    print(f"  negative control (terminal-branch assignments only):    {len(neg)} hits "
          f"{'PASS' if ok_neg else 'FAIL'}")
    if not (ok_pos and ok_neg):
        print("  ⛔ the detector is broken — a 0 from it means nothing")
        return 1
    print("  ✅ the detector can say YES and can say NO; a 0 on real code is a real 0")
    return 0


def main(argv):
    if "--control" in argv:
        return run_control()
    roots = [a for a in argv if not a.startswith("-")] or ["src"]
    files = []
    for root in roots:
        if os.path.isfile(root):
            files.append(root)
            continue
        for dirpath, _, names in os.walk(root):
            files.extend(os.path.join(dirpath, n) for n in sorted(names) if n.endswith(".gd"))
    files.sort()

    rows = []
    for path in files:
        rows.extend(scan_file(path))
    rows.sort(key=lambda r: -r[4])

    print(f"{'file':38s} {'function':30s} {'latch':26s} {'line':>6s} {'gap':>4s} {'calls':>6s} {'await':>6s}")
    print("-" * 120)
    for path, name, guard, line, gap, calls, awaits in rows:
        print(f"{path[-38:]:38s} {name[:30]:30s} {guard[:26]:26s} {line:6d} {gap:4d} {calls:6d} {awaits:6d}")
    print(f"\ncorpus: {len(files)} .gd file(s) · {len(rows)} entry-latch site(s) · min gap {MIN_GAP}")
    print("A row is a SHAPE, not a defect — see the module docstring for the four discriminators.")
    print("Run with --control before trusting a zero.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
