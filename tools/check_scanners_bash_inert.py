#!/usr/bin/env python3
""":"
echo "$0 is a Python script: run it with python3, not bash" >&2; exit 2
":"""
# check_scanners_bash_inert.py — `bash tools/check_X.py` must do NOTHING but refuse (cowir-main 23550).
# Bash reads a Python file line by line and keeps going after errors, so any docstring line that looks like a command
# RUNS: check_raw_assets_shipped_selftest.py's docstring had a line starting "tools/deploy_web.sh gate 3c ...". Every
# tracked tools/check_*.py (and this file) carries the three-line guard above: Python reads one string, bash runs `:`
# and then `exit 2` before anything else.
#   python3 tools/check_scanners_bash_inert.py              judge every tracked scanner: the guard is present (static) AND
#                                                           `bash <file>` exits 2 saying so (dynamic)
#   python3 tools/check_scanners_bash_inert.py --selftest   both directions on fixtures, then the real scanners
# The DYNAMIC run is safe even on an unguarded file: an EMPTY environment (PATH=/nonexistent), an EMPTY scratch cwd and
# stdin closed, so a relative `tools/...` or any external command resolves to nothing; only bash builtins can run.
# Exit 0 all inert · 1 any scanner not inert · 2 usage.
import os, shutil, subprocess, sys, tempfile

GUARD = '""":"\necho "$0 is a Python script: run it with python3, not bash" >&2; exit 2\n":"""\n'
BASH = shutil.which('bash') or '/bin/bash'   # resolved HERE: the run itself gets PATH=/nonexistent
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def scanners():
    out = subprocess.check_output(['git', '-C', REPO, 'ls-files', 'tools/check_*.py']).decode().split()
    return [os.path.join(REPO, p) for p in sorted(out)]


def judge(path):
    """-> '' when inert, else the reason."""
    s = open(path, encoding='utf-8').read()
    first, _, rest = s.partition('\n')
    if not first.startswith('#!') or not rest.startswith(GUARD):
        return 'no bash guard right after the shebang'
    with tempfile.TemporaryDirectory(prefix='bash_inert.') as cwd:
        r = subprocess.run([BASH, path], cwd=cwd, env={'PATH': '/nonexistent'}, stdin=subprocess.DEVNULL,
                           capture_output=True, text=True, timeout=10)
    if r.returncode != 2 or 'run it with python3' not in r.stderr:
        return 'bash exit %d, stderr %r' % (r.returncode, r.stderr.strip()[:120])
    return ''


def main(paths):
    bad = [(p, judge(p)) for p in paths]
    bad = [(p, w) for p, w in bad if w]
    for p, w in bad:
        print('[bash-inert] NOT INERT %s: %s' % (os.path.relpath(p, REPO), w))
    print('[bash-inert] %d scanner(s) · %d not inert' % (len(paths), len(bad)))
    return 1 if bad else 0


def selftest():
    fails = []
    with tempfile.TemporaryDirectory(prefix='bash_inert_st.') as d:
        good = os.path.join(d, 'good.py'); open(good, 'w').write('#!/usr/bin/env python3\n' + GUARD + 'print(1)\n')
        bare = os.path.join(d, 'bare.py'); open(bare, 'w').write('#!/usr/bin/env python3\n"""doc\necho LEAKED\n"""\n')
        # a guard text that is present but BROKEN for bash (exit removed) must red dynamically, not pass on the static half
        broke = os.path.join(d, 'broke.py'); open(broke, 'w').write('#!/usr/bin/env python3\n' + GUARD.replace('exit 2', 'true') + '\n')
        for name, path, want_inert in (('guarded', good, True), ('bare', bare, False)):
            w = judge(path)
            if (w == '') != want_inert:
                fails.append('%s: judged %r' % (name, w or 'inert'))
        if judge(broke) == '':
            fails.append('a guard with its exit removed was judged inert')
        r = subprocess.run([sys.executable, good], capture_output=True, text=True)
        if r.returncode != 0 or r.stdout.strip() != '1':
            fails.append('the guard changed what python runs: %r' % r.stdout)
    real = main(scanners())
    for f in fails:
        print('[bash-inert] SELFTEST FAIL', f)
    print('[bash-inert] selftest: %d fixture failure(s), real scanners %s' % (len(fails), 'inert' if real == 0 else 'NOT inert'))
    return 0 if not fails and real == 0 else 1


if __name__ == '__main__':
    if sys.argv[1:] == ['--selftest']:
        sys.exit(selftest())
    if sys.argv[1:]:
        print('usage: check_scanners_bash_inert.py [--selftest]'); sys.exit(2)
    sys.exit(main(scanners()))
