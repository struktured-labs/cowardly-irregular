#!/usr/bin/env python3
"""Arms for derive_selftest_corpus.py.

Run: python3 tools/derive_selftest_corpus_selftest.py   (no flag; sibling convention)

WHY THIS FILE EXISTS. The derivation decides which guards get their arms run before a publish.
Every way it can be wrong is SILENT: a member lost runs fewer arms and still prints success, and
a member gained runs arms that pass anyway, so an inflated corpus reads as thoroughness. Two
defects in one day, neither found by a test -- a scope widened in one of two places (caught by
the membership floor) and a Python docstring read as code (caught only by chasing a member I had
not predicted). Both are arms below.

Each arm pins the expected REASON, not merely pass/fail: a guard whose verdict is broader than
its code passes for the wrong cause. Fixtures are built on disk and the REAL script is executed
against them -- never a copy of its logic, which would drift from the thing that ships.

NOTE ON RECURSION, stated because the obvious home for a selftest is often the thing it tests:
this file WRITES a fixture named tools/publish_all.sh but never EXECUTES one, and never invokes
the publish path. The subject is derive_selftest_corpus.py, run as a subprocess against a
throwaway git repo. Bounded by construction, not by luck.
"""
import os, shutil, subprocess, sys, tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(REPO, "tools", "derive_selftest_corpus.py")

ARMS_SH = 'case "$1" in\n    --selftest) echo ok ;;\nesac\n'   # dispatches -> has arms
ARMS_PY = 'import sys\nif "--selftest" in sys.argv:\n    print("ok")\n'
BARE_SH = 'echo no arms here\n'

# publish_all.sh must reach BOTH channel scripts or the structural floor fires by design.
BASE = {
    "publish_all.sh": 'deploy_desktop.sh\ndeploy_web.sh\ngate_one.sh\ngate_two.py\nquiet.sh\nproser.py\n',
    "deploy_desktop.sh": BARE_SH,
    "deploy_web.sh": BARE_SH,
    "gate_one.sh": ARMS_SH,
    "gate_two.py": ARMS_PY,
    "quiet.sh": BARE_SH,            # reached, no arms -> reached != corpus
    "proser.py": "x = 1\n",         # the file each arm mutates
    "secret_tool.sh": ARMS_SH,      # tracked + armed: admitted IFF genuinely referenced
}
BASE_CORPUS = "gate_one.sh gate_two.py"


def build(files):
    d = tempfile.mkdtemp(prefix="dsc_", dir=os.path.join(REPO, "tmp"))
    os.mkdir(os.path.join(d, "tools"))
    for name, body in files.items():
        with open(os.path.join(d, "tools", name), "w") as f:
            f.write(body)
    for cmd in (["git", "init", "-q"], ["git", "add", "-A"]):
        subprocess.run(cmd, cwd=d, capture_output=True)
    return d


def run(files):
    d = build(files)
    try:
        p = subprocess.run([sys.executable, SCRIPT], cwd=d, capture_output=True, text=True)
        return p.returncode, p.stdout.strip(), p.stderr.strip()
    finally:
        shutil.rmtree(d, ignore_errors=True)


def variant(**over):
    f = dict(BASE)
    f.update(over)
    return f


fails = []


def arm(label, files, corpus=None, ec=0, reason=None):
    got_ec, out, err = run(files)
    why = []
    if got_ec != ec:
        why.append("EC %d != %d" % (got_ec, ec))
    if corpus is not None and out != corpus:
        why.append("corpus %r != %r" % (out, corpus))
    if reason is not None and reason not in err:
        why.append("reason %r not in %r" % (reason, err))
    print("  %-4s %s" % ("FAIL" if why else "ok", label))
    if why:
        for w in why:
            print("         " + w)
        fails.append(label)


print("[dsc-selftest] derive_selftest_corpus.py")

arm("baseline: armed tools admitted, unarmed reached-but-excluded",
    BASE, corpus=BASE_CORPUS)

# --- the defect that shipped: Python prose read as code -------------------------------------
arm("a tool named in a \"\"\" docstring is NOT admitted",
    variant(**{"proser.py": '"""cites secret_tool.sh as a place, not a call."""\nx = 1\n'}),
    corpus=BASE_CORPUS)

arm("a tool named in a ''' docstring is NOT admitted",
    variant(**{"proser.py": "'''cites secret_tool.sh as a place, not a call.'''\nx = 1\n"}),
    corpus=BASE_CORPUS)

arm("a tool named in a MULTI-LINE docstring is NOT admitted",
    variant(**{"proser.py": '"""opens here\nsecret_tool.sh sits inside\n"""\nx = 1\n'}),
    corpus=BASE_CORPUS)

# --- the control that fires the OTHER way: stripping must not blind the scan to .py code -----
arm("the SAME name in real code IS admitted",
    variant(**{"proser.py": 'X = "secret_tool.sh"\n'}),
    corpus="gate_one.sh gate_two.py secret_tool.sh")

arm("code AFTER a one-line docstring is not swallowed",
    variant(**{"proser.py": '"""a one-liner naming nothing"""\nX = "secret_tool.sh"\n'}),
    corpus="gate_one.sh gate_two.py secret_tool.sh")

arm("code AFTER a closed multi-line docstring is not swallowed",
    variant(**{"proser.py": '"""opens\ncloses\n"""\nX = "secret_tool.sh"\n'}),
    corpus="gate_one.sh gate_two.py secret_tool.sh")

arm("a '#' comment is still stripped (old behaviour survives)",
    variant(**{"proser.py": "# secret_tool.sh in a hash comment\nx = 1\n"}),
    corpus=BASE_CORPUS)

arm("docstring stripping does NOT apply to .sh (where \"\"\" is not a comment)",
    variant(**{"quiet.sh": '""" secret_tool.sh\n'}),
    corpus="gate_one.sh gate_two.py secret_tool.sh")

# --- conventions ------------------------------------------------------------------------------
arm("sibling <base>_selftest.py counts as arms; the sibling itself is excluded",
    variant(**{"publish_all.sh": BASE["publish_all.sh"] + "sib.py\n",
               "sib.py": "x = 1\n", "sib_selftest.py": "x = 1\n"}),
    corpus="gate_one.sh gate_two.py sib.py")

arm("an UNTRACKED tool is not admitted even when referenced and armed",
    variant(**{"publish_all.sh": BASE["publish_all.sh"] + "ghost.sh\n"}),
    corpus=BASE_CORPUS)

# --- floors: each must fire, and name its own cause -------------------------------------------
arm("structural floor fires when the closure misses deploy_web.sh",
    variant(**{"publish_all.sh": 'deploy_desktop.sh\ngate_one.sh\ngate_two.py\n'}),
    ec=1, reason="closure never reached deploy_web.sh")

arm("membership floor fires when NO .py has arms (a whole language lost)",
    variant(**{"gate_two.py": "x = 1\n"}),
    ec=1, reason="contains no .py tool")

arm("membership floor fires when NO .sh has arms",
    variant(**{"gate_one.sh": BARE_SH, "secret_tool.sh": BARE_SH}),
    ec=1, reason="contains no .sh tool")

# --- vacuity: the arms above must be capable of failing ----------------------------------------
_ec, _out, _err = run(variant(**{"proser.py": 'X = "secret_tool.sh"\n'}))
if _out == BASE_CORPUS:
    print("  FAIL vacuity: the admit-control produced the baseline corpus, so no arm above discriminates")
    fails.append("vacuity")
else:
    print("  ok   vacuity: the admit-control moves the corpus, so the docstring arms mean something")

print("[dsc-selftest] %d arm(s) FAILED" % len(fails) if fails else "[dsc-selftest] all arms passed")
sys.exit(1 if fails else 0)
