#!/usr/bin/env python3
"""gate_line.py - derive a release tag's Gate and `gated:` lines from the fold chain's own log.

Until .800 cowir-main hand-copied Scripts / Tests / Passing / Time and the SHA out of
tmp/chainNNN.out into every tag message. cut_tag.sh checks the SHA and `failing=0`, but nothing
checked the other numbers, and a hand copy is exactly where a 3160 becomes a 3106.
This reads the log and REFUSES unless the run is a full green gate on one unmoved tree.

    python3 tools/gate_line.py tmp/chain800.out              prints the two lines
    python3 tools/gate_line.py tmp/chain800.out --fill MSG   replaces the GATE_LINE placeholder in MSG
    python3 tools/gate_line.py --selftest

Exit 0 = printed/filled · 1 = refused (reason on stderr) · 2 = bad invocation.
"""
import os
import re
import sys
import tempfile

PLACEHOLDER = "GATE_LINE"


class Refused(Exception):
    pass


def _one(pattern, text, what, flags=re.M):
    m = re.findall(pattern, text, flags)
    if not m:
        raise Refused(f"no {what} in the chain log")
    return m


def derive(text):
    tree = _one(r"^chain\d+ tree=([0-9a-f]{40})$", text, "'chainNNN tree=<sha>' header")[0]
    if not re.search(r"^GATE VERDICT EC=0$", text, re.M):
        raise Refused("the chain did not end 'GATE VERDICT EC=0' (pre-gate red, gate red, or still running)")
    pre = re.search(r"^PRE-GATE: CLEAN for ([0-9a-f]{40})", text, re.M)
    if not pre or pre.group(1) != tree:
        raise Refused("no 'PRE-GATE: CLEAN' for the chain's own tree")
    gate = _one(r"^GATE\d+ EC=(\d+) sha=([0-9a-f]{40})$", text, "'GATENNN EC= sha=' line")[-1]
    if gate[0] != "0" or gate[1] != tree:
        raise Refused(f"the gate line is EC={gate[0]} sha={gate[1][:9]}, not EC=0 on {tree[:9]}")
    if not re.search(rf"^TREE: unmoved {tree}, clean$", text, re.M):
        raise Refused("the tree moved or was dirty during the gate")
    smoke = re.search(r"^\[SMOKE\] VERDICT: PASS$", text, re.M)
    if not smoke:
        raise Refused("the render smoke did not print VERDICT: PASS")

    # The suite's Totals come AFTER the GATE line; the pre_ready sweep prints its own Passing earlier.
    tail = text[text.index(f"sha={tree}"):]
    rows = {}
    for key in ("Scripts", "Tests", "Passing", "Failing", "Risky/Pending"):
        m = re.findall(rf"^[ \t]*{re.escape(key)}[ \t]+([0-9]+)$", tail, re.M)
        if m:
            rows[key] = int(m[-1])
    t = re.findall(r"^[ \t]*Time[ \t]+([0-9.]+)s$", tail, re.M)
    for key in ("Scripts", "Tests", "Passing"):
        if key not in rows:
            raise Refused(f"the gate's Totals have no {key} row")
    if not t:
        raise Refused("the gate's Totals have no Time row")
    failing = rows.get("Failing", 0)
    if failing:
        raise Refused(f"the gate reports Failing {failing}")
    authored = int(_one(r"^authored: ([0-9]+)$", text, "'authored: N' line")[-1])
    if rows["Scripts"] != authored:
        raise Refused(f"Scripts {rows['Scripts']} != authored {authored}: a truncated run")

    guards = re.search(r"^pre_ready_guards: ([0-9]+) distinct guards", text, re.M)
    pre_head = text[: text.index(f"sha={tree}")]
    pre_pass = re.findall(r"^[ \t]*Passing[ \t]+([0-9]+)$", pre_head, re.M)
    side = re.search(r"^\[sidecars\] ([0-9]+) importable asset", text, re.M)
    if not guards or not pre_pass or not side:
        raise Refused("the pre-gate section is missing its guards, Passing or sidecars line")
    n = int(side.group(1))
    assets = "0 new assets" if n == 0 else f"{n} new asset{'s' if n != 1 else ''} all with sidecars"
    risky = rows.get("Risky/Pending", 0)

    gate_line = (
        f"Gate: Scripts {rows['Scripts']} == authored {authored} · Tests {rows['Tests']} · "
        f"Passing {rows['Passing']} · Failing 0 · Risky/Pending {risky} · {round(float(t[-1]))} s. "
        f"Pre-gate clean on this tree (render smoke VERDICT PASS, {guards.group(1)} guards / "
        f"{pre_pass[-1]} passing, {assets}). Tree unmoved."
    )
    gated = (f"gated: {tree} scripts={rows['Scripts']} tests={rows['Tests']} "
             f"passing={rows['Passing']} failing=0")
    return gate_line + "\n\n" + gated


def fill(msgfile, block):
    with open(msgfile, encoding="utf-8") as f:
        body = f.read()
    if body.count(PLACEHOLDER) != 1:
        raise Refused(f"{msgfile} must hold exactly one {PLACEHOLDER} placeholder, it holds {body.count(PLACEHOLDER)}")
    with open(msgfile, "w", encoding="utf-8") as f:
        f.write(body.replace(PLACEHOLDER, block))


GREEN = """chain799 tree=1c58df47e66bc2fd43254a4ec90c5e5ba79c68f4
import EC=0
[SMOKE] VERDICT: PASS
[sidecars] 4 importable asset(s) added v3.33.798-alpha -> HEAD: every one has a committed .import
pre_ready EC=0
pre_ready_guards: 1165 distinct guards for: assets data src test
  Passing         7092
authored: 3160
GATE799 EC=0 sha=1c58df47e66bc2fd43254a4ec90c5e5ba79c68f4
TREE: unmoved 1c58df47e66bc2fd43254a4ec90c5e5ba79c68f4, clean
Scripts           3160
Tests             18037
  Passing         18035
  Risky/Pending   2
Time              1833.716s
PRE-GATE: CLEAN for 1c58df47e66bc2fd43254a4ec90c5e5ba79c68f4 (selftests EC=0)
GATE VERDICT EC=0
"""
WANT = ("Gate: Scripts 3160 == authored 3160 · Tests 18037 · Passing 18035 · Failing 0 · "
        "Risky/Pending 2 · 1834 s. Pre-gate clean on this tree (render smoke VERDICT PASS, 1165 guards / "
        "7092 passing, 4 new assets all with sidecars). Tree unmoved.\n\n"
        "gated: 1c58df47e66bc2fd43254a4ec90c5e5ba79c68f4 scripts=3160 tests=18037 passing=18035 failing=0")


def selftest():
    fails = []

    def expect_refused(name, text, why):
        try:
            derive(text)
            fails.append(f"{name}: accepted, should refuse ({why})")
        except Refused as e:
            if why not in str(e):
                fails.append(f"{name}: refused for the wrong reason: {e}")

    try:
        got = derive(GREEN)
        if got != WANT:
            fails.append(f"CONTROL green log: derived\n{got}\nwant\n{WANT}")
    except Refused as e:
        fails.append(f"CONTROL green log refused: {e}")
    expect_refused("pre-gate red", GREEN.replace("GATE VERDICT EC=0", "PRE-GATE RED (sweep) — gate NOT started"),
                   "GATE VERDICT EC=0")
    expect_refused("truncated", GREEN.replace("Scripts           3160", "Scripts           3008"), "truncated")
    expect_refused("failing", GREEN.replace("  Risky/Pending   2", "  Failing         1\n  Risky/Pending   2"),
                   "Failing 1")
    expect_refused("tree moved", GREEN.replace("TREE: unmoved", "TREE: MOVED"), "moved")
    expect_refused("other sha", GREEN.replace("GATE799 EC=0 sha=1c58df47e", "GATE799 EC=0 sha=2c58df47e"),
                   "gate line")
    # The pre_ready Passing must not stand in for the suite's when the suite printed none.
    expect_refused("no suite Passing", GREEN.replace("  Passing         18035\n", ""), "no Passing row")

    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "msg.txt")
        with open(p, "w", encoding="utf-8") as f:
            f.write("v3.33.799-alpha\n\n- a line\n\nGATE_LINE\n")
        fill(p, WANT)
        with open(p, encoding="utf-8") as f:
            if f.read() != "v3.33.799-alpha\n\n- a line\n\n" + WANT + "\n":
                fails.append("fill: placeholder not replaced exactly once")
        try:
            fill(p, WANT)
            fails.append("fill: a file with no placeholder was accepted")
        except Refused:
            pass

    for f in fails:
        print("FAIL", f)
    print(f"gate_line selftest: {9 - len(fails)}/9 arms as expected")
    return 1 if fails else 0


def main(argv):
    if argv == ["--selftest"]:
        return selftest()
    if not argv or len(argv) not in (1, 3) or (len(argv) == 3 and argv[1] != "--fill"):
        print(__doc__, file=sys.stderr)
        return 2
    try:
        with open(argv[0], encoding="utf-8", errors="replace") as f:
            block = derive(f.read())
        if len(argv) == 3:
            fill(argv[2], block)
            print(f"gate_line: filled {argv[2]}")
        else:
            print(block)
        return 0
    except (Refused, OSError) as e:
        print(f"gate_line: REFUSED: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
