#!/usr/bin/env python3
"""Arms for check_unbound_vars.py, refereed by BASH ITSELF.

Every arm is a RUNNABLE straight-line fixture. Each is judged three ways and
all three must agree:

    expected   what I claim the arm is about, named explicitly per arm
    tool       what check_unbound_vars.py reports
    oracle     what `bash -u` actually does — its stderr names the variable
               and the line, so the oracle is not my opinion about bash

The oracle is why this file exists. Seven of this tool's first findings were
its own parser, not the tree, and I only caught them by reading each site. An
arm that encodes my belief about bash cannot catch a belief that is wrong; an
arm that RUNS bash can. Arms are straight-line so the failing expansion is
actually reached — an unbound variable behind a false branch never fires, and
`set -u` aborts at the FIRST one, so no fixture carries two.

DELIBERATE DIVERGENCE: `${V:?msg}` aborts under bash and is NOT reported. It is
an author asserting a precondition on purpose, which is the opposite of the
silent class this tool exists for. That divergence has its own arm rather than
an exemption in the comparison, so it cannot widen without a test going red.
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, 'check_unbound_vars.py')
WORK = os.path.join(os.path.dirname(HERE), 'tmp', 'uvselftest')
ORACLE_RE = re.compile(r'line \d+: ([A-Za-z_][A-Za-z0-9_]*)(?:\[[^\]]*\])?: unbound variable')

# (name, script, expected UNBOUND names, oracle_applies, why)
ARMS = [
    ('bare_unset', 'set -u\necho "$NOPE"\n', {'NOPE'}, True,
     'the floor: a plain expansion of a name assigned nowhere'),
    ('assigned', 'set -u\nX=1\necho "$X"\n', set(), True,
     'the vacuity control: if this reports, everything below is noise'),
    ('default_dash', 'set -u\necho "${NOPE:-d}"\n', set(), True,
     '${V:-d} supplies a default and cannot abort'),
    ('default_numeric', 'set -u\necho "${NOPE:-2700}"\n', set(), True,
     'REGRESSION: ":-2700" reads as colon+digits and was called a substring'),
    ('default_nocolon', 'set -u\necho "${NOPE-d}"\n', set(), True,
     '${V-d} is the unset-only form, still a default'),
    ('substring', 'set -u\nechoic="${NOPE:1:2}"\necho "$echoic"\n', {'NOPE'}, True,
     '${V:1:2} has no default and DOES abort — the near-miss of default_numeric'),
    ('length', 'set -u\necho "${#NOPE}"\n', {'NOPE'}, True,
     '${#V} aborts too; the # prefix is not a default'),
    ('strip_suffix', 'set -u\necho "${NOPE%%.sh}"\n', {'NOPE'}, True,
     'parameter-expansion operators are not defaults'),
    ('mapfile_t', 'set -u\nmapfile -t ARR < <(printf "a\\nb\\n")\necho "${#ARR[@]}"\n', set(), True,
     'REGRESSION: mapfile -t takes NO argument, so ARR is the target not the arg'),
    ('mapfile_missing', 'set -u\necho "${#ARR[@]}"\n', {'ARR'}, True,
     'and the same array with no mapfile still fires — mapfile_t is not blanket'),
    ('read_d_empty', 'set -u\nprintf "a\\0" | while IFS= read -r -d "" f; do echo "$f"; done\n',
     set(), True, "REGRESSION: blanking '' to spaces let -d consume f as its delimiter"),
    ('read_two_calls', 'set -u\nread -r a b <<<"1 2"\nread -r c d <<<"3 4"\necho "$a$b$c$d"\n',
     set(), True, 'REGRESSION: a greedy match ate the line, hiding the second read'),
    ('read_missing', 'set -u\nread -r a <<<"1"\necho "$a$zz"\n', {'zz'}, True,
     'a read on the line does not bless every name on it'),
    ('read_a_array', 'set -u\nread -r -a f <<<"x y"\necho "${f[0]}"\n', set(), True,
     'REGRESSION: read -a NAME assigns NAME; -a was treated as consuming a non-name (blocked .484)'),
    ('read_a_missing', 'set -u\nread -r -a f <<<"x y"\necho "${f[0]}$zz"\n', {'zz'}, True,
     'read -a blesses only its array, not every name on the line'),
    ('read_t_consumes', 'set -u\nread -r -t 5 v <<<"1"\necho "$v"\n', set(), True,
     '-t still consumes its argument; the target after it is still recorded'),
    ('pid_then_text', 'set -u\nC="x_$$_zzz"\necho "$C"\n', set(), True,
     'REGRESSION: $$ is the PID; _zzz after it is literal, not an expansion'),
    ('pid_then_real', 'set -u\nC="x_$$"\necho "$C$_zzz"\n', {'_zzz'}, True,
     'and a REAL $_zzz still fires — pid_then_text is not blanket'),
    ('arith_cmdsub', 'set -u\nB="%s"\necho "$(( $(stat -c%%s "$B") / 1 ))"\n' % TOOL, set(), True,
     'REGRESSION: $(stat -c%s "$B") inside $(( )) read as vars stat, c, s'),
    ('arith_bare', 'set -u\necho "$(( NOPE + 1 ))"\n', {'NOPE'}, True,
     'a BARE name inside $(( )) is a real expansion and must still fire'),
    ('heredoc_quoted', 'set -u\ncat <<"EOF"\n$NOPE\nEOF\n', set(), True,
     'REGRESSION: a quoted delimiter means the body is not expanded'),
    ('heredoc_unquoted', 'set -u\ncat <<EOF\n$NOPE\nEOF\n', {'NOPE'}, True,
     'an UNQUOTED delimiter does expand the body — the discriminating pair'),
    ('single_quoted', "set -u\necho '$NOPE'\n", set(), True,
     'no expansion inside single quotes'),
    ('comment', 'set -u\n# echo "$NOPE"\necho ok\n', set(), True,
     'a commented expansion is not an expansion'),
    ('for_var', 'set -u\nfor i in 1 2; do echo "$i"; done\n', set(), True,
     'the loop variable is assigned by the loop'),
    ('printf_v', 'set -u\nprintf -v OUT "%s" hi\necho "$OUT"\n', set(), True,
     'printf -v assigns its target'),
    ('colon_assign', 'set -u\n: "${NOPE:=fallback}"\necho "$NOPE"\n', set(), True,
     '${V:=d} assigns as well as expands, so the later bare $NOPE is bound'),
    ('exit_not_unbound', 'set -u\nexit 3\n', set(), True,
     'ORACLE CONTROL: bash exits non-zero for a reason that is NOT unbound. '
     'If the oracle keyed on exit code instead of the message, this arm passes '
     'while proving nothing.'),
    ('assert_form', 'set -u\necho "${NOPE:?required}"\n', set(), False,
     'DELIBERATE DIVERGENCE: bash aborts, the tool stays silent. ${V:?} is an '
     'author asserting a precondition on purpose; the silent class is the point.'),
]


def run_tool(path):
    p = subprocess.run([sys.executable, TOOL, path], capture_output=True, text=True)
    return set(re.findall(r'UNBOUND\s+\S+:\d+\s+\$(\S+)', p.stdout)), p.returncode


def run_oracle(path):
    """(names bash called unbound, did bash abort at all, stderr).

    The two are NOT the same question, and conflating them cost an arm.
    `${V:?msg}` aborts with the AUTHOR'S message -- `NOPE: required` -- and
    never says "unbound variable", so an oracle keyed on that string sees a
    clean run. The names answer "which expansion was unbound"; the abort flag
    answers "did bash stop", which is what the divergence arm is about."""
    p = subprocess.run(['bash', path], capture_output=True, text=True,
                       cwd=os.path.dirname(TOOL), timeout=30)
    return set(ORACLE_RE.findall(p.stderr)), p.returncode != 0, p.stderr


def main():
    os.makedirs(WORK, exist_ok=True)
    fails = []
    for name, script, expect, oracle_applies, why in ARMS:
        path = os.path.join(WORK, 'arm_%s.sh' % name)
        with open(path, 'w') as fh:
            fh.write(script)
        got, ec = run_tool(path)
        oracle, aborted, err = run_oracle(path)
        bad = []
        if got != expect:
            bad.append('tool reported %s, expected %s' % (sorted(got) or '{}', sorted(expect) or '{}'))
        if (ec != 0) != bool(expect):
            bad.append('exit code %d disagrees with its own report' % ec)
        if oracle_applies and oracle != expect:
            bad.append('BASH says %s, expected %s' % (sorted(oracle) or '{}', sorted(expect) or '{}'))
        if not oracle_applies:
            # Assert the divergence in BOTH directions with the instrument that
            # can actually see it: bash must ABORT (on its own message, not the
            # unbound one) while the tool stays silent. If either half changes
            # this goes red rather than quietly becoming a no-op.
            if not aborted:
                bad.append('bash no longer aborts on ${V:?}, so there is no '
                           'divergence left to document')
            elif 'required' not in err:
                bad.append("bash aborted but not on the author's message: %r"
                           % err.strip()[-80:])
            elif oracle:
                bad.append('bash now calls it unbound (%s); the tool should '
                           'report it too' % sorted(oracle))
        status = 'FAIL' if bad else ('ok  ' if oracle_applies else 'ok* ')
        print('  %s %-18s %s' % (status, name, why))
        for b in bad:
            print('         ^ %s' % b)
        if bad:
            fails.append(name)
    n_oracle = sum(1 for a in ARMS if a[3])
    print('\n[unbound-vars selftest] %d arm(s), %d refereed by bash, %d failed'
          % (len(ARMS), n_oracle, len(fails)))
    if fails:
        print('  failed: %s' % ', '.join(fails))
        return 1
    print('  ok* = deliberate divergence from bash, asserted in BOTH directions')
    return 0


if __name__ == '__main__':
    sys.exit(main())
