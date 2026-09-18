#!/usr/bin/env python3
"""Find variables a bash script EXPANDS but never ASSIGNS — fatal under `set -u`.

WHY THIS EXISTS
  v3.33.409-alpha went RED with nothing published on:
      ./tools/deploy_desktop.sh: line 599: _RAW_TOOLS: unbound variable
  One gate block was written once and pasted into two files with different
  preludes. deploy_web.sh defined _RAW_TOOLS; deploy_desktop.sh defined
  _RAW_CHECK inline and never _RAW_TOOLS.

  Nothing in the repo could see it:
    `bash -n`          parses. An unbound expansion is a RUNTIME error.
    the selftests      exercise the python gates, not their shell call sites.
    my own extraction  the harness preamble SET _RAW_TOOLS itself, so the test
                       supplied the precondition the file lacked.
  It is only reachable on a real publish, past the point where builds are made.

WHAT IT REPORTS
  UNBOUND  expanded with no default, and assigned NOWHERE in the file
           (nor in anything it sources). This is the .409 bug exactly.
  LATE     expanded at top level before its first assignment. Inside a function
           body this is normal (the function runs later), so function-body uses
           are classified separately and reported as INFO, never as a failure.

EXPANSIONS THAT ARE SAFE under set -u and are NOT reported:
  ${V:-d} ${V-d} ${V:+d} ${V+d} ${V:=d} ${V=d} ${V:?m} ${V?m}
EXPANSIONS THAT ARE NOT SAFE and ARE reported:
  $V  ${V}  ${#V}  ${V%x}  ${V#x}  ${V/a/b}  ${V:1:2}  ${V[@]}  $((V+1))

EXIT: 0 clean · 1 findings · 2 usage/IO error
"""
import os
import re
import sys

# Set by bash itself or by any POSIX login environment. Everything else that is
# never assigned is a finding — including project env vars like BUTLER_API_KEY,
# because under `set -u` an unexported one is exactly the .409 failure.
ALWAYS_SET = {
    'IFS', 'PWD', 'OLDPWD', 'HOME', 'PATH', 'USER', 'LOGNAME', 'SHELL', 'TERM',
    'LANG', 'TMPDIR', 'HOSTNAME', 'SHLVL', 'UID', 'EUID', 'PPID', 'RANDOM',
    'SECONDS', 'LINENO', 'BASHPID', 'BASH', 'BASH_VERSION', 'BASH_SOURCE',
    'BASH_REMATCH', 'BASH_SUBSHELL', 'FUNCNAME', 'PIPESTATUS', 'OSTYPE',
    'MACHTYPE', 'HOSTTYPE', 'EPOCHSECONDS', 'EPOCHREALTIME', 'COLUMNS', 'LINES',
    'REPLY', 'OPTARG', 'OPTIND', 'PS1', 'PS2', 'PS4', 'GROUPS', 'DIRSTACK',
}

NAME = r'[A-Za-z_][A-Za-z0-9_]*'
QCH = '~'   # placeholder for single-quoted text: not a name, not a flag, not '.'
HEREDOC_RE = re.compile(r'<<(?!<)-?\s*(["\']?)(' + NAME + r')\1')
USE_RE = re.compile(r'\$(?:\{([!#]?)(' + NAME + r')|(' + NAME + r'))')
ARITH_STMT_RE = re.compile(r'\(\((.*?)\)\)', re.S)
IDENT_RE = re.compile(r'(?<![\$\w])(' + NAME + r')')
# `X=` / `X+=` / `local -r X=` / `export X=` / `arr[0]=`, at a command position.
ASSIGN_RE = re.compile(
    r'(?:^|[;&|(]|\s)(?:(?:local|declare|typeset|export|readonly)\s+(?:-[A-Za-z]+\s+)*)?'
    r'(' + NAME + r')(?:\[[^\]]*\])?\+?=')
# bare declarations: `local X` / `declare -a X` / `export X`
DECL_RE = re.compile(r'(?:^|[;&|(]|\s)(?:local|declare|typeset|export|readonly)\s+((?:-[A-Za-z]+\s+)*)(' + NAME + r')(?![\w=])')
FOR_RE = re.compile(r'(?:^|[;&|(]|\s)for\s+(' + NAME + r')\s+in\b')
SELECT_RE = re.compile(r'(?:^|[;&|(]|\s)select\s+(' + NAME + r')\s+in\b')
PRINTF_V_RE = re.compile(r'printf\s+(?:[^|;&]*?\s)?-v\s+(' + NAME + r')')
GETOPTS_RE = re.compile(r'getopts\s+\S+\s+(' + NAME + r')')
# ${V:=d} and ${V=d} ASSIGN as well as expand.
DEFAULT_ASSIGN_RE = re.compile(r'\$\{(' + NAME + r')(?:\[[^\]]*\])?:?=')
SOURCE_RE = re.compile(r'(?:^|[;&|(]|\s)(?:source|\.)\s+("?)([^\s;&|"]+)\1')
# `read` option flags that consume the NEXT token (so it is not a variable name).
READ_ARGFLAGS = {'read': set('adeinNptu'), 'mapfile': set('dnOscCu'),
                 'readarray': set('dnOscCu')}


def strip_dollar_spans(text):
    """Blank $(...), ${...} and $NAME. Inside `$(( ))` only BARE identifiers are
    variable references; a `$`-prefixed one is already counted by USE_RE, and a
    nested command substitution is not arithmetic at all. Not doing this read
    `$(( $(stat -c%s "$BIN") / 1048576 ))` as three variables: stat, c and s."""
    out, i, n = [], 0, len(text)
    while i < n:
        if text[i] == '$' and i + 1 < n and text[i + 1] in '({':
            close = ')' if text[i + 1] == '(' else '}'
            depth, j = 0, i + 1
            while j < n:
                if text[j] in '({':
                    depth += 1
                elif text[j] in ')}':
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            out.append(' ' * (min(j + 1, n) - i))
            i = j + 1
            continue
        if text[i] == '$':
            m = re.match(NAME, text[i + 1:])
            if m:
                out.append(' ' * (len(m.group(0)) + 1))
                i += len(m.group(0)) + 1
                continue
        out.append(text[i])
        i += 1
    return ''.join(out)


def arith_spans(code):
    """(offset, body) for each `$(( ... ))`, matched with balanced parens so a
    nested `$(...)` cannot terminate the span early."""
    spans, i, n = [], 0, len(code)
    while i < n - 2:
        if code[i:i + 3] == '$((':
            depth, j = 2, i + 3
            while j < n and depth > 0:
                if code[j] == '(':
                    depth += 1
                elif code[j] == ')':
                    depth -= 1
                j += 1
            spans.append((i, code[i + 3:max(j - 2, i + 3)]))
            i = j
            continue
        i += 1
    return spans


def _strip(raw, in_double):
    """Blank single-quoted spans and trailing comments; keep expandable text."""
    out, i, n, in_single = [], 0, len(raw), False
    while i < n:
        c = raw[i]
        if in_single:
            out.append(QCH)
            if c == "'":
                in_single = False
            i += 1
            continue
        if c == '\\':
            out.append('  ' if i + 1 < n else ' ')
            i += 2
            continue
        if c == "'" and not in_double:
            in_single = True
            out.append(QCH)
            i += 1
            continue
        if c == '"':
            in_double = not in_double
            out.append(c)
            i += 1
            continue
        if c == '#' and not in_double and (i == 0 or raw[i - 1] in ' \t;|&('):
            break
        out.append(c)
        i += 1
    return ''.join(out), in_double


def logical_lines(text):
    """(lineno, expandable_code, raw) with heredocs and quotes honoured."""
    out, heredoc, in_double = [], None, False
    for i, raw in enumerate(text.split('\n'), 1):
        if heredoc is not None:
            delim, expand = heredoc
            if raw.strip() == delim:
                heredoc = None
                out.append((i, '', raw))
                continue
            out.append((i, raw if expand else '', raw))
            continue
        code, in_double = _strip(raw, in_double)
        m = HEREDOC_RE.search(raw[:len(code)])
        if m:
            # quoted delimiter => body is NOT expanded
            heredoc = (m.group(2), m.group(1) == '')
            code = code[:m.start()]
        out.append((i, code, raw))
    return out


def _read_targets(code):
    """Variable names assigned by a `read`/`mapfile`/`readarray` call.

    The argument span is bounded by [^;&|<>] INSIDE the pattern rather than
    trimmed afterwards: a greedy `(.*)$` swallows the rest of the line, so
    `read -r a b; read -r c d` matched once and the second read's targets were
    never recorded (verify_release_artifact.sh:120)."""
    names = []
    for m in re.finditer(r'(?:^|[;&|(]|\s)(read|mapfile|readarray)\b([^;&|<>]*)', code):
        cmd, argflags = m.group(1), READ_ARGFLAGS[m.group(1)]
        toks, j = m.group(2).split(), 0
        while j < len(toks):
            t = toks[j]
            if t.startswith('-'):
                j += 2 if (len(t) == 2 and t[1] in argflags) else 1
                continue
            if re.fullmatch(NAME, t):
                names.append(t)
            j += 1
    return names


def collect(text):
    """-> (assigns {name: first_line}, uses [(line, name, in_func)])"""
    assigns, uses = {}, []
    depth, func_depth = 0, None
    for ln, code, _raw in logical_lines(text):
        if not code.strip():
            continue
        for rx, grp in ((ASSIGN_RE, 1), (FOR_RE, 1), (SELECT_RE, 1),
                        (PRINTF_V_RE, 1), (GETOPTS_RE, 1),
                        (DEFAULT_ASSIGN_RE, 1), (DECL_RE, 2)):
            for m in rx.finditer(code):
                assigns.setdefault(m.group(grp), ln)
        for nm in _read_targets(code):
            assigns.setdefault(nm, ln)
        for m in ARITH_STMT_RE.finditer(code):
            for a in re.finditer(r'(?<![\$\w])(' + NAME + r')\s*(?:[-+*/%]?=(?!=)|\+\+|--)', m.group(1)):
                assigns.setdefault(a.group(1), ln)

        in_func = func_depth is not None
        ucode = code.replace('$$', QCH * 2)
        for m in USE_RE.finditer(ucode):
            name = m.group(2) or m.group(3)
            if m.group(2) is not None:  # ${...} — check for a default operator
                # ${V:-d} is a DEFAULT. ${V:1:2} is a SUBSTRING and is unsafe.
                # They differ only in the character after the colon: an operator
                # (-=+?) means default, anything else (digit, space, $) means
                # substring. `${V:-2700}` reads as ":" + "-" + digits, so a
                # discriminator that looked for a digit called it a substring
                # and reported a safe expansion — measured on deploy_desktop:512.
                if re.match(r'^:?[-=+?]', ucode[m.end():]):
                    continue
            uses.append((ln, name, in_func))
        for start, body in arith_spans(ucode):
            body = strip_dollar_spans(body)
            for a in IDENT_RE.finditer(body):
                nm = a.group(1)
                if re.match(r'\s*(?:[-+*/%]?=(?!=)|\+\+|--)', body[a.end():]):
                    assigns.setdefault(nm, ln)
                else:
                    uses.append((ln, nm, in_func))

        if re.search(r'(?:^|\s)(?:function\s+)?' + NAME + r'\s*\(\)\s*\{', code) and func_depth is None:
            func_depth = depth
        depth += code.count('{') - code.count('}')
        if func_depth is not None and depth <= func_depth:
            func_depth = None
    return assigns, uses


def sourced_assigns(path, text, seen=None):
    """Assignments reachable through `source`/`.` — a sourced file really does
    define them, so counting only the file's own would be a false alarm."""
    seen = seen or set()
    extra, root = {}, os.path.dirname(os.path.abspath(path))
    repo = os.path.dirname(root) if os.path.basename(root) == 'tools' else root
    for _ln, code, _raw in logical_lines(text):
        for m in SOURCE_RE.finditer(code):
            tgt = m.group(2)
            if '$' in tgt:
                tgt = re.sub(r'\$\{?[A-Za-z_][A-Za-z0-9_]*\}?', '', tgt).lstrip('/')
            for cand in (os.path.join(root, os.path.basename(tgt)),
                         os.path.join(repo, tgt), tgt):
                cand = os.path.abspath(cand)
                if cand in seen or not os.path.isfile(cand):
                    continue
                seen.add(cand)
                try:
                    sub = open(cand, encoding='utf-8', errors='replace').read()
                except OSError:
                    continue
                a, _ = collect(sub)
                extra.update(a)
                extra.update(sourced_assigns(cand, sub, seen))
    return extra


def audit(path):
    try:
        text = open(path, encoding='utf-8', errors='replace').read()
    except OSError as exc:
        print('ERROR: %s' % exc, file=sys.stderr)
        return None
    assigns, uses = collect(text)
    assigns = dict(sourced_assigns(path, text), **assigns)
    unbound, late, info = {}, {}, {}
    for ln, name, in_func in uses:
        if name in ALWAYS_SET or name.isdigit() or name == '_':
            continue
        if name not in assigns:
            unbound.setdefault(name, ln)
        elif ln < assigns[name]:
            (info if in_func else late).setdefault(name, (ln, assigns[name]))
    return unbound, late, info, len(uses), len(assigns)


def main(argv):
    if len(argv) < 2 or argv[1] in ('-h', '--help'):
        print(__doc__)
        return 2
    strict = '--strict' in argv          # also fail on LATE
    paths = [a for a in argv[1:] if not a.startswith('-')]
    bad = 0
    for p in paths:
        r = audit(p)
        if r is None:
            return 2
        unbound, late, info, nuse, nassign = r
        tag = 'UNBOUND' if unbound else ('LATE' if (late and strict) else 'ok')
        print('[unbound-vars] %-34s %s  (%d expansions, %d names assigned)'
              % (os.path.basename(p), tag, nuse, nassign))
        for name, ln in sorted(unbound.items(), key=lambda kv: kv[1]):
            print('    UNBOUND  %s:%d  $%s expanded, assigned nowhere -> set -u aborts here'
                  % (p, ln, name))
        for name, (u, a) in sorted(late.items(), key=lambda kv: kv[1][0]):
            print('    LATE     %s:%d  $%s used at top level before its assignment (line %d)'
                  % (p, u, name, a))
        for name, (u, a) in sorted(info.items(), key=lambda kv: kv[1][0]):
            print('    info     %s:%d  $%s used inside a function before line %d (normal)'
                  % (p, u, name, a))
        if unbound or (late and strict):
            bad += 1
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
