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
     4 = REFUSED: the box is not yours (tools/box_busy.sh says a gate, a publish or ANOTHER lane's held slot is up,
         or could not answer). No godot is started. The holder is named.
     124 = godot did not finish inside the bound.
It starts ONE short headless godot (about 6 s) on a sandboxed user:// (tmp/xdg_parse). That is still an engine on a
shared box: on 2026-11-11/12 five "4-second" probes landed inside other lanes' claimed slots, announced each time, and
the holder cannot tell a probe from its own measurement (cowir-main 24116: a claimed box means NO godot from anyone
else, a parse_probe included). So this asks tools/box_busy.sh FIRST and refuses unless the box is free or the hold is
your own: run it as a step of your slot, under `tools/box_hold.sh <lane> -- ...`, where box_busy reads free by ancestry.
`--box` asks only that question (exit 0 = you may probe now, 4 = refused, with the reason) and starts nothing.

--selftest is ENGINE-FREE (no godot, no git, nothing written outside a temp dir it removes): it checks the verdict
this tool draws from a driver's output, the unimported refusal, and the box refusal: against stub box_busy answers
with a stand-in `godot` on PATH that records being started, and against the REAL box_busy + box_hold on scratch
markers (a real hold by another lane refuses; the same question from inside that hold does not). --selftest-live plants a script that calls a
function it does not have beside a healthy one, runs the real driver on both, and must red on exactly the planted one.
"""
USAGE = "usage: python3 tools/parse_probe.py <file.gd> [...] | --box | --selftest | --selftest-live   (exit 0 loads, 1 does not, 3 unimported tree, 4 the box is not yours)"
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BOUND_S = 180
BOX_BOUND_S = 120
ERROR = re.compile(r"SCRIPT ERROR|Parse Error|Compile Error")
LINE = re.compile(r"^\[PARSE\] (\S+) (OK|FAILED)$")


def unimported(root):
    """Why this tree cannot be judged, or "" when it can."""
    cache = os.path.join(root, ".godot", "global_script_class_cache.cfg")
    if not os.path.isfile(cache) or os.path.getsize(cache) == 0:
        return "%s is missing or empty: import first (godot --headless --import), or every class_name reads as an error" % cache
    return ""


def box_refusal(root):
    """Why this probe may not start an engine now, or "" when it may. Fails CLOSED: no answer is a refusal."""
    bb = os.path.join(root, "tools", "box_busy.sh")
    if not os.path.isfile(bb):
        return "tools/box_busy.sh is missing from this tree, so nothing can say whose the box is"
    try:
        p = subprocess.run(["bash", bb], cwd=root, capture_output=True, text=True, timeout=BOX_BOUND_S, stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return "tools/box_busy.sh did not answer in %d s" % BOX_BOUND_S
    if p.returncode == 0:
        return ""
    said = [l for l in p.stdout.splitlines() if l.strip()]
    if p.returncode == 1 and said:
        return said[-1].strip()
    return "tools/box_busy.sh exited %d without a reason this tool can read (0 = free, 1 = busy + why)" % p.returncode


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
    held = box_refusal(root)
    if held:
        print("[parse_probe] REFUSED (the box is not yours, no godot started): " + held, file=sys.stderr)
        print("[parse_probe] run it as a step of your own slot: tools/box_hold.sh <lane> -- python3 tools/parse_probe.py ...", file=sys.stderr)
        return 4
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
        ## ---- the box refusal, on a stand-in tree: stub box_busy answers, and a `godot` on PATH that records a start ----
        mark = os.path.join(t, "godot.started")
        os.makedirs(os.path.join(t, "tools"))
        os.makedirs(os.path.join(t, "bin"))
        open(os.path.join(t, "a.gd"), "w").write("extends Node\n")
        open(os.path.join(t, "bin", "godot"), "w").write("#!/bin/sh\n: > '%s'\necho '[PARSE] res://a.gd OK'\necho '[PARSE] done'\n" % mark)
        os.chmod(os.path.join(t, "bin", "godot"), 0o755)
        bb = os.path.join(t, "tools", "box_busy.sh")
        old_path = os.environ["PATH"]
        os.environ["PATH"] = os.path.join(t, "bin") + os.pathsep + old_path

        def probe(stub):
            """(exit code, was the engine started) for one stub box_busy; None = no box_busy at all."""
            if os.path.exists(mark):
                os.remove(mark)
            if os.path.exists(bb):
                os.remove(bb)
            if stub is not None:
                open(bb, "w").write(stub)
            return run(["a.gd"], root=t), os.path.exists(mark)

        try:
            check("CONTROL: a free box runs the probe, and the engine starts", probe("echo 'FREE (other lanes godot up: 0)'; exit 0\n"), (0, True))
            check("another lane's held slot is refused, and NO engine starts", probe("echo 'BUSY: slot cowir-zz running: pid=1 lane=cowir-zz'; exit 1\n"), (4, False))
            check("the refusal names the holder", "cowir-zz" in box_refusal(t), True)
            check("a tree with no box_busy is refused, and no engine starts", probe(None), (4, False))
            check("a box_busy that cannot answer (exit 2) is refused, not read as free", probe("echo usage >&2; exit 2\n"), (4, False))
            check("a busy answer with no reason is refused too", probe("exit 1\n"), (4, False))
        finally:
            os.environ["PATH"] = old_path
        ## ---- the REAL box_busy + box_hold, scratch markers only (box_hold's own selftest isolates the same way) ----
        hold = os.path.join(ROOT, "tools", "box_hold.sh")
        if os.path.isfile(hold):
            e = dict(os.environ, BOX_SLOT_MARKER=os.path.join(t, "slot"), BOX_MARKER=os.path.join(t, "none.m"), DEPLOY_DIR=os.path.join(t, "d"),
                     DEPLOY_GLOB=os.path.join(t, "none"), FOLD_TREE=os.path.join(t, "none"), BOX_BUSY_ENGINE=os.path.join(t, "no-engine"))
            me = os.path.abspath(__file__)
            inner = 'python3 "%s" --box > "%s/in.out" 2>&1; echo $? > "%s/in.ec"; n=0; while [ ! -e "%s/go" ] && [ $n -lt 600 ]; do sleep 0.2; n=$((n+1)); done' % (me, t, t, t)
            check("CONTROL: with no hold anywhere, the real box_busy lets a probe through", subprocess.run([sys.executable, me, "--box"], env=e, capture_output=True, text=True).returncode, 0)
            h = subprocess.Popen(["bash", hold, "cowir-zz", "--", "sh", "-c", inner], env=e, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)
            try:
                import time
                n = 0
                while not os.path.exists(os.path.join(t, "in.ec")) and n < 600:
                    time.sleep(0.2)
                    n += 1
                out = subprocess.run([sys.executable, me, "--box"], env=e, capture_output=True, text=True)
                check("a REAL hold by another lane refuses a probe from outside it", out.returncode, 4)
                check("and that refusal names the lane holding", "cowir-zz" in (out.stdout + out.stderr), True)
                got = open(os.path.join(t, "in.ec")).read().strip() if os.path.exists(os.path.join(t, "in.ec")) else "never ran"
                check("the SAME question from inside that hold is allowed (your own slot)", got, "0")
            finally:
                open(os.path.join(t, "go"), "w").write("")
                h.wait(timeout=180)
            check("the hold's marker is gone afterwards", os.path.exists(os.path.join(t, "slot")), False)
        else:
            fails.append("tools/box_hold.sh is missing: the real-hold arms did not run")
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
    if args == ["--box"]:
        why = box_refusal(ROOT)
        print("[parse_probe] " + ("REFUSED (the box is not yours): " + why if why else "the box is free or the hold is yours: a probe may run"))
        sys.exit(4 if why else 0)
    if not args or any(a.startswith("--") for a in args):
        print(USAGE, file=sys.stderr)
        sys.exit(2)
    sys.exit(run(args))
