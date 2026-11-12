#!/usr/bin/env python3
""":"
echo "$0 is a Python script: run it with python3, not bash" >&2; exit 2
":"""
"""Does this tip's GDScript LOAD? The check a .gd-editing tip gets before it is announced (cowir-main 23939, 23951).

    tools/parse_probe.py src/battle/BattleScene.gd test/unit/test_x.gd ...

On 2026-11-11 three lanes stacked on a BattleScene.gd that called a function it did not have, and a test file that
named a class with no class_name would have run nothing: each was announced "UNVERIFIED, no godot run", which is fine
for behaviour and not for "does it load". `godot --check-only --script` cannot answer either: it has no autoloads, so
it fails a HEALTHY BattleScene.gd on "Identifier not found: JobSystem". This runs tools/parse_probe.gd, which waits
for the tree to start and then load()s each file, so autoload names and class_names resolve as they do in the game.

Exit 0 = every file loaded · 1 = at least one did not (the errors are printed) · 2 = bad invocation
     3 = REFUSED: the tree is unimported (.godot has no class cache), where every class_name reads as an error
     124 = godot did not finish inside the bound.
It starts ONE short headless godot (about 6 s) on a sandboxed user:// (tmp/xdg_parse), so it is allowed outside a
box turn when no gate or publish is running; say in the channel that you ran it.

--selftest is ENGINE-FREE (no godot, no git, nothing written outside a temp dir it removes): it checks the verdict
this tool draws from a driver's output, and the unimported refusal. --selftest-live plants a script that calls a
function it does not have beside a healthy one, runs the real driver on both, and must red on exactly the planted one.
"""
USAGE = "usage: python3 tools/parse_probe.py <file.gd> [...] | --selftest | --selftest-live   (exit 0 loads, 1 does not, 3 unimported tree)"
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BOUND_S = 180
ERROR = re.compile(r"SCRIPT ERROR|Parse Error|Compile Error")
LINE = re.compile(r"^\[PARSE\] (\S+) (OK|FAILED)$")


def unimported(root):
    """Why this tree cannot be judged, or "" when it can."""
    cache = os.path.join(root, ".godot", "global_script_class_cache.cfg")
    if not os.path.isfile(cache) or os.path.getsize(cache) == 0:
        return "%s is missing or empty: import first (godot --headless --import), or every class_name reads as an error" % cache
    return ""


def verdict(output, wanted):
    """(exit code, [reasons]) from the driver's output for the files asked about."""
    seen = {}
    done = False
    for raw in output.splitlines():
        m = LINE.match(raw.strip())
        if m:
            seen[m.group(1)] = m.group(2)
        done = done or raw.strip() == "[PARSE] done"
    reasons = []
    for f in wanted:
        res = f if f.startswith("res://") else "res://" + f
        state = seen.get(res)
        if state is None:
            reasons.append("%s: the driver never reported it" % f)
        elif state != "OK":
            reasons.append("%s: did not load" % f)
    if not done:
        reasons.append("the driver did not finish")
    errors = [l for l in output.splitlines() if ERROR.search(l)]
    ## An error line with every file OK is still a red: something this run compiled is broken.
    if errors and not reasons:
        reasons.append("%d script error line(s) though every named file loaded" % len(errors))
    return (1 if reasons else 0), reasons


def run(files, root=ROOT):
    why = unimported(root)
    if why:
        print("[parse_probe] REFUSED (unimported tree): " + why, file=sys.stderr)
        return 3
    missing = [f for f in files if not os.path.isfile(os.path.join(root, f.replace("res://", "")))]
    if missing:
        print("[parse_probe] no such file: " + " ".join(missing), file=sys.stderr)
        return 2
    xdg = os.path.join(root, "tmp", "xdg_parse")
    os.makedirs(xdg, exist_ok=True)
    env = dict(os.environ, XDG_DATA_HOME=xdg)
    cmd = ["timeout", str(BOUND_S), "godot", "--headless", "--audio-driver", "Dummy", "-s", "res://tools/parse_probe.gd", "--"] + list(files)
    try:
        p = subprocess.run(cmd, cwd=root, env=env, capture_output=True, text=True, timeout=BOUND_S + 20, stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        print("[parse_probe] godot did not finish in %d s" % BOUND_S, file=sys.stderr)
        return 124
    out = p.stdout + p.stderr
    code, reasons = verdict(out, files)
    for l in out.splitlines():
        if LINE.match(l.strip()) or ERROR.search(l) or l.strip().startswith("at: "):
            print(l.rstrip())
    for r in reasons:
        print("[parse_probe] FAIL " + r)
    print("[parse_probe] %s: %d file(s)" % ("LOADS" if code == 0 else "DOES NOT LOAD", len(files)))
    return code


def selftest():
    fails = []

    def check(name, got, want):
        if got != want:
            fails.append("%s: got %r, want %r" % (name, got, want))

    ok = "[PARSE] res://a.gd OK\n[PARSE] res://b.gd OK\n[PARSE] done\n"
    check("two healthy files", verdict(ok, ["a.gd", "res://b.gd"])[0], 0)
    bad = 'SCRIPT ERROR: Parse Error: Function "_reduce_flashes()" not found in base self.\n          at: GDScript::reload (res://a.gd:5)\n[PARSE] res://a.gd FAILED\n[PARSE] res://b.gd OK\n[PARSE] done\n'
    code, reasons = verdict(bad, ["a.gd", "b.gd"])
    check("a missing function reds", code, 1)
    check("and names only the broken file", reasons, ["a.gd: did not load"])
    check("a file the driver never reported reds", verdict(ok, ["a.gd", "c.gd"])[0], 1)
    check("a driver that died before the end reds", verdict("[PARSE] res://a.gd OK\n", ["a.gd"])[0], 1)
    check("an error line with every file OK still reds", verdict("SCRIPT ERROR: Compile Error: x\n" + ok, ["a.gd", "b.gd"])[0], 1)
    check("prose that mentions OK is not a result", verdict("[PARSE] res://a.gd OK really\n[PARSE] done\n", ["a.gd"])[0], 1)
    t = tempfile.mkdtemp(prefix="parse_probe_selftest.")
    try:
        check("an unimported tree is refused", bool(unimported(t)), True)
        os.makedirs(os.path.join(t, ".godot"))
        open(os.path.join(t, ".godot", "global_script_class_cache.cfg"), "w").write("")
        check("an EMPTY class cache is refused too", bool(unimported(t)), True)
        open(os.path.join(t, ".godot", "global_script_class_cache.cfg"), "w").write("list=[]\n")
        check("CONTROL: an imported tree is not refused", unimported(t), "")
    finally:
        shutil.rmtree(t, ignore_errors=True)
    for f in fails:
        print("[parse_probe] SELFTEST FAIL " + f)
    print("[parse_probe] selftest: %d arm(s) failed" % len(fails))
    return 1 if fails else 0


def selftest_live():
    """One real godot run: a planted missing-function call must red, the healthy file beside it must not."""
    d = os.path.join(ROOT, "tmp", "parse_probe_live")
    os.makedirs(d, exist_ok=True)
    good, bad = "tmp/parse_probe_live/good.gd", "tmp/parse_probe_live/bad.gd"
    open(os.path.join(ROOT, good), "w").write("extends Node\n\n\nfunc size_of() -> int:\n\treturn JobSystem.get_ability(\"fire\").size()\n")
    open(os.path.join(ROOT, bad), "w").write("extends Node\n\n\nfunc broken() -> bool:\n\treturn _a_function_this_script_does_not_have()\n")
    try:
        both = run([good, bad])
        alone = run([good])
    finally:
        shutil.rmtree(d, ignore_errors=True)
    ok = both == 1 and alone == 0
    print("[parse_probe] selftest-live: planted+healthy exit %d (want 1) · healthy alone exit %d (want 0, and it names an autoload) -> %s" % (both, alone, "PASS" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    args = sys.argv[1:]
    if args == ["--selftest"]:
        sys.exit(selftest())
    if args == ["--selftest-live"]:
        sys.exit(selftest_live())
    if not args or any(a.startswith("--") for a in args):
        print(USAGE, file=sys.stderr)
        sys.exit(2)
    sys.exit(run(args))
