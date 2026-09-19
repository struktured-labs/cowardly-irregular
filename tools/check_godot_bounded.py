#!/usr/bin/env python3
"""Every godot invocation in tools/ must run under a clock. Assert it, don't assume it.

WHY THIS EXISTS
---------------
2026-09-19. @cowir-main's fold gate spun 1h57m at 100% on one non-main thread with its log
frozen, because nothing bounded the godot run. I surveyed this lane's publish path the same
night and found SEVEN godot invocations with EXACTLY ONE bounded — deploy_web.sh's xvfb smoke,
which has carried `timeout 300` since it was written. The other six were the fold gate's shape
in the release path, and the release path is worse: publish_all runs DETACHED, so a wedge
writes no publish.ec and `publish_detached.sh --status` waits on that file forever. It presents
as a release that simply never happens — no RED, no exit code, no log line.

This is the sibling of check_polling_bounded.py and it exists for the same stated reason: the
hazard was WRITTEN DOWN in publish_all.sh's own comment for an hour ("the remaining six want
the same treatment") while only one site had it. A documented hazard reads as an accepted one.

WHAT IT CHECKS
--------------
In every tools/*.sh, each godot invocation must be BOUNDED by one of:

  tools/bounded_godot.sh … -- godot …     the runner (preferred: it also owns the log and
                                          reports on the PASSING arm)
  timeout <spec> … godot …                a bare timeout, for a site with its own measured
                                          budget (deploy_web.sh's xvfb smoke, 300s)

Backslash continuations are joined first, so a runner invocation split across three lines is
one logical line and the bound is visible on it.

WHAT IT DELIBERATELY DOES NOT DO
--------------------------------
Read comments. A scan for this defect produces false positives on the file DOCUMENTING it —
this docstring contains the word godot dozens of times, and publish_all.sh's header quotes the
unbounded form it replaced. Full-line comments are stripped, and an arm asserts a defect that
appears ONLY in a comment is not reported.

ITS OWN BLIND SPOT, STATED RATHER THAN DISCOVERED LATER
-------------------------------------------------------
A candidate is `godot` followed by an option (`godot --headless`, `godot -s`), or `$GODOT`.
It does NOT see `godot` invoked with a non-option first argument, nor an invocation routed
through a variable holding the whole command. All eight sites in this tree are `godot --…`, so
the narrow form costs nothing TODAY; it is the form that would go stale silently. Arm
`blind spot: a non-option first argument is NOT seen` pins it, so the limit is a test result
rather than a thing a reader has to notice.

WHAT IT BLOCKS ON, AND WHAT IT ONLY COUNTS
------------------------------------------
I measured the false-positive set BEFORE widening, which is the half of this job that normally
gets skipped. Run over all 66 shell files in tools/ the first time, it returned 9 unbounded of
18 — and reading all nine is what produced this section:

  2  FALSE POSITIVES   run_tests.sh:348,364 — `echo "Run: godot --headless …"` is ADVICE PRINTED
                       TO A HUMAN, not an invocation. Fixed: a logical line whose first word is
                       echo/printf is not a command invocation. Two arms, both directions.
  7  REAL, OUT OF SCOPE  run_tests.sh:24 (the GUT suite, the whole fleet's), llm_prompt_preview
                       x2, and four xvfb screenshot tools. Every one is genuinely unbounded and
                       none is on the publish path. Bounding the fleet's test runner from the
                       deploy lane, at this hour, is not a repair — it is a surprise.

So the gate BLOCKS on the publish path and INVENTORIES the rest, printing the out-of-scope
count every run. The number is stated rather than hidden, which is the difference between a
scope and a blind spot: a reader learns there are seven, and that nobody has claimed them.

EXIT
----
0  every publish-path invocation is bounded    2  a defect, or a publish-path file is missing
"""
import re
import sys
from pathlib import Path

CAND = re.compile(r"(?<![\w/.\-])godot\s+-|\$\{?GODOT\b")
# A line that PRINTS the word godot is not a line that RUNS it. run_tests.sh tells a human
# "Run: godot --headless --audio-driver Dummy --import --quit" and that is not an invocation.
PRINTS = re.compile(r"^\s*(echo|printf)\b")
# The chain a publish actually executes. Named, not globbed: a glob would silently acquire the
# fleet's test runner the day someone renames it, and acquiring subjects by accident is the
# defect this lane keeps finding (harden-one-writer-miss-the-rest, widening-admission-escapes).
PUBLISH_PATH = [
    "publish_all.sh", "publish_newest.sh", "publish_detached.sh",
    "deploy_desktop.sh", "deploy_linux.sh", "deploy_windows.sh", "deploy_web.sh",
    "make_web_stage.sh", "make_web_audio.sh",
]
BOUND = re.compile(r"bounded_godot\.sh|(?<![\w/.\-])timeout\s+\S")


def logical_lines(text):
    """Join backslash continuations, dropping full-line comments FIRST.

    Order matters: a commented-out continuation would otherwise swallow the next real line.
    """
    out, buf, start = [], "", 0
    for n, raw in enumerate(text.splitlines(), 1):
        if not buf and raw.lstrip().startswith("#"):
            continue
        if not buf:
            start = n
        if raw.endswith("\\"):
            buf += raw[:-1] + " "
            continue
        out.append((start, buf + raw))
        buf = ""
    if buf:
        out.append((start, buf))
    return out


def findings(text):
    return [(n, line.strip()) for n, line in logical_lines(text)
            if CAND.search(line) and not PRINTS.match(line) and not BOUND.search(line)]


def _selftest():
    cases = [
        ("bare invocation is a defect",
         'godot --headless --import --quit > log 2>&1', 1),
        ("the runner bounds it",
         './tools/bounded_godot.sh --label x --budget 5 --log l -- godot --headless --import', 0),
        ("a bare timeout bounds it",
         'xvfb-run -a timeout 300 godot --rendering-driver opengl3', 0),
        ("an env prefix does not hide it",
         'XDG_DATA_HOME="$PWD/tmp/x" godot --headless --import --quit', 1),
        ("backgrounded is still a defect",
         'XDG_DATA_HOME=x godot --headless --import &', 1),
        ("a continuation is joined, bound VISIBLE",
         './tools/bounded_godot.sh --label x --budget 5 --log l -- \\\n    godot --headless --import', 0),
        ("a continuation is joined, defect STILL SEEN",
         'XDG_DATA_HOME=x \\\n    godot --headless --import', 1),
        ("a comment-only defect is NOT reported",
         '#  XDG_DATA_HOME=x godot --headless --import --quit', 0),
        ("a commented continuation does not swallow the next line",
         '# trailing backslash in a comment \\\nXDG_DATA_HOME=x godot --headless --import', 1),
        ("a template PATH containing godot is not an invocation",
         'ln -s "$HOME/.local/share/godot/export_templates" "$sandbox/godot"', 0),
        ("an exe readlink mentioning godot is not an invocation",
         'case "$(readlink /proc/$p/exe)" in *godot*) ;; esac', 0),
        ("$GODOT is a candidate too",
         '"$GODOT" --headless --import', 1),
        ("  ...and $GODOT bounded is clean",
         './tools/bounded_godot.sh --budget 5 -- "$GODOT" --headless --import', 0),
        # STATED LIMIT, not a discovered one.
        ("an ECHOED command is advice, not an invocation",
         'echo "  Run: godot --headless --audio-driver Dummy --import --quit" >&2', 0),
        ("  ...and the CONTROL: the same text as a real command IS a defect",
         'XDG_DATA_HOME=x godot --headless --audio-driver Dummy --import --quit >&2', 1),
        ("blind spot: a non-option first argument is NOT seen",
         'godot res://main.tscn', 0),
    ]
    p = f = 0
    for name, src, want in cases:
        got = len(findings(src))
        if got == want:
            p += 1
            print(f"  ok    {name}")
        else:
            f += 1
            print(f"  FAIL  {name}: {got} findings, wanted {want}")
    print(f"[godot-bound] selftest: {p} passed, {f} failed")
    return 0 if f == 0 else 1


def main(argv):
    if "--selftest" in argv:
        return _selftest()
    root = Path(argv[1]) if len(argv) > 1 else Path("tools")

    def count(fp):
        text = fp.read_text(errors="replace")
        n = sum(1 for _, line in logical_lines(text)
                if CAND.search(line) and not PRINTS.match(line))
        return n, findings(text)

    # VACUITY CONTROL, and a stronger one than a file count: every named publish-path file must
    # be present. A renamed deploy script would otherwise shrink the corpus to a clean green.
    missing = [n for n in PUBLISH_PATH if not (root / n).exists()]
    if missing:
        print(f"[godot-bound] BLOCKED: publish-path files absent from {root}: "
              f"{', '.join(missing)} — a clean result over the rest would mean nothing.",
              file=sys.stderr)
        return 2

    total = bad = 0
    for name in PUBLISH_PATH:
        n_here, hits = count(root / name)
        total += n_here
        for ln, line in hits:
            bad += 1
            print(f"[godot-bound] UNBOUNDED  {root/name}:{ln}  {line[:110]}", file=sys.stderr)

    others = sorted(p for p in root.glob("*.sh") if p.name not in PUBLISH_PATH)
    o_total = o_bad = 0
    o_names = []
    for fp in others:
        n_here, hits = count(fp)
        o_total += n_here
        for ln, _ in hits:
            o_bad += 1
            o_names.append(f"{fp.name}:{ln}")

    if bad:
        print(f"[godot-bound] BLOCKED: {bad} of {total} godot invocations on the publish path "
              f"({len(PUBLISH_PATH)} files) run with no clock on them.", file=sys.stderr)
        return 2
    print(f"[godot-bound] publish path: {total} godot invocations across {len(PUBLISH_PATH)} "
          f"files, {total} bounded, 0 unbounded.")
    print(f"[godot-bound] outside the publish path: {o_bad} of {o_total} unbounded across "
          f"{len(others)} files — NOT blocked here, and NOT claimed by anyone: "
          f"{', '.join(o_names) if o_names else 'none'}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
