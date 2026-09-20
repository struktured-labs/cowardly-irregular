#!/usr/bin/env python3
"""`cmd; VAR=$?` in a `set -e` script makes every non-zero arm dead code. Assert it never ships.

WHY THIS EXISTS
---------------
2026-09-19. `v3.33.466-alpha` would not publish and the store sat EIGHT tags behind. One
character, in tools/make_web_audio.sh, shipped by me in 31991aeeb:

    $SEAM_AUDIT --from "$OUT_DIR" > "$_seam_out" 2>&1; _seam_ec=$?

That file runs `set -euo pipefail`. Under `set -e` a non-zero command is FATAL BEFORE THE NEXT
STATEMENT, so the assignment never happens, the `case` below it is unreachable, and the script
dies where it stands. Measured three ways:

    set -e; (exit 1); ec=$?; echo REACHED       -> nothing printed, exit 1
    set -e; ec=0; (exit 1) || ec=$?; echo ...   -> REACHED, ec=1
    set -e; (exit 0); ec=$?; echo REACHED       -> REACHED     <- why every test passed

⛔ THE ARM THAT HELD EVERY RELEASE WAS THE ARM WRITTEN SO THAT IT WOULD NOT. Exit 1 from that
audit means "a bed crossed the 12 dB line", and the comment three lines above it reads "A
CROSSING WARNS, IT DOES NOT BLOCK". The audit returned 1 for the exact bed that comment names.
Exit 2's BLOCKED message was equally unreachable. Only the exit-0 path ever ran, which is why
the change was green in every test and killed the store in production.

Three sites existed, all in `set -e` files: make_web_audio.sh, deploy_desktop.sh, deploy_web.sh.
Both deploy sites documented "only EC 2 blocks" and neither could print its BLOCKED diagnostic.

WHAT IT CHECKS
--------------
In each tools/*.sh that enables `set -e` (`set -e`, `set -eu`, `set -euo pipefail`, `set -o
errexit`), a statement of the form

    <command> ; VAR=$?

is a finding. The correct form is `VAR=0` first, then `<command> || VAR=$?`.

WHAT IT DELIBERATELY DOES NOT DO
--------------------------------
Flag `cmd || VAR=$?` (the fix), `if cmd; then` / `while cmd; do` (condition context, where
`set -e` is suspended), `VAR=$(cmd)` (a different construct), or anything in a comment — this
docstring is full of the defective form and must not report itself.

⚠️ ITS OWN FIRST VERSION RETURNED 0 FINDINGS WITH THE DEFECT ON THE LINE IT WAS WRITTEN FOR.
The pattern required a space before `;` and the real line has none. The arm
`no space before the semicolon` pins that, because a guard that cannot find the instance that
motivated it is decoration.

EXIT
----
0  clean       2  a finding, or the corpus floor was not met
"""
import re
import sys
from pathlib import Path

SET_E = re.compile(r"^\s*set\s+-[a-zA-Z]*e[a-zA-Z]*\b|^\s*set\s+-o\s+errexit\b", re.M)
# The defect: a command, then `;`, then VAR=$?. `[^|&;]` before the `;` keeps `||`/`&&`/`;;`
# out. No space is required anywhere — that omission is what made the first version vacuous.
DEFECT = re.compile(r"[^\s|&;][ \t]*;[ \t]*([A-Za-z_][A-Za-z_0-9]*)=\$\?")
# ⛔ THERE IS NO if/while EXEMPTION, AND THE FIRST VERSION HAD ONE THAT WAS WORSE THAN DEAD.
# The reasoning was "condition context suspends `set -e`". True, and irrelevant: `; VAR=$?`
# cannot OCCUR in a condition, because what follows the `;` there is `then`/`do`. So the
# exemption never fired for its stated purpose -- and a mutation that DELETED it reded nothing,
# which is how it was found. It did fire on a one-liner whose BODY holds the real defect:
#     if [ -f x ]; then ./y.sh; ec=$?; fi     <- `set -e` applies in the body; silently exempt
# A rule that cannot help and can hurt is not conservative. The arm below pins the one-liner.


def strip_comment(line):
    """Drop a trailing comment, respecting quotes. A '#' inside a string is not a comment."""
    out, q = [], None
    for i, ch in enumerate(line):
        if q:
            out.append(ch)
            if ch == q and line[i - 1] != "\\":
                q = None
            continue
        if ch in "'\"":
            q = ch
            out.append(ch)
            continue
        if ch == "#" and (i == 0 or line[i - 1] in " \t"):
            break
        out.append(ch)
    return "".join(out)


def findings(text):
    if not SET_E.search(text):
        return []
    hits = []
    for n, raw in enumerate(text.splitlines(), 1):
        if raw.lstrip().startswith("#"):
            continue
        line = strip_comment(raw)
        m = DEFECT.search(line)
        if m:
            hits.append((n, m.group(1), raw.strip()))
    return hits


def _selftest():
    E = "set -euo pipefail\n"
    cases = [
        ("the shipped defect, no space before ';'",
         E + 'cmd --from "$D" > "$out" 2>&1; _seam_ec=$?', 1),
        ("no space before the semicolon",              E + './x.sh; _PAT_EC=$?', 1),
        ("spaces around the semicolon",                E + './x.sh ; _PAT_EC=$?', 1),
        ("the FIX is not a finding",                   E + '_ec=0\n./x.sh || _ec=$?', 0),
        ("`set -e` absent -> not a finding",           './x.sh; _ec=$?', 0),
        ("`set -o errexit` counts",                    'set -o errexit\n./x.sh; _ec=$?', 1),
        ("`set -eu` counts",                           'set -eu\n./x.sh; _ec=$?', 1),
        # `ec=$?` after `then`/`do` follows a KEYWORD, not a `;`, so it was never a finding --
        # these two pin that it stays that way for the right reason.
        ("`then ec=$?` is not this defect",            E + 'if ./x.sh; then ec=$?; fi', 0),
        ("`do ec=$?` is not this defect",              E + 'while ./x.sh; do ec=$?; done', 0),
        # THE ARM THE DELETED EXEMPTION WAS HIDING.
        ("a one-line if BODY is NOT exempt",           E + 'if [ -f x ]; then ./y.sh; ec=$?; fi', 1),
        ("a full-line comment is not code",            E + '#  ./x.sh; _ec=$?', 0),
        ("a TRAILING comment is not code",             E + 'echo hi   # ./x.sh; _ec=$?', 0),
        ("  ...but a '#' inside a string is not a comment",
         E + 'echo "a#b"; _ec=$?', 1),
        ("`;;` (case arm) is not a finding",           E + 'case $x in a) y;; esac', 0),
        ("VAR=$(cmd) is a different construct",        E + '_ec=$(./x.sh)', 0),
        ("`||` before the ';' is not this defect",     E + './x.sh || true; _ec=$?', 1),
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
    print(f"[exit-capture] selftest: {p} passed, {f} failed")
    return 0 if f == 0 else 1


def main(argv):
    if "--selftest" in argv:
        return _selftest()
    root = Path(argv[1]) if len(argv) > 1 else Path("tools")
    files = sorted(root.glob("*.sh"))
    # VACUITY CONTROL. A green over an empty corpus reads exactly like a green.
    guarded = [f for f in files if SET_E.search(f.read_text(errors="replace"))]
    if len(guarded) < 5:
        print(f"[exit-capture] BLOCKED: only {len(guarded)} `set -e` shell file(s) under {root} "
              "— that is not this tree, so a clean result would mean nothing.", file=sys.stderr)
        return 2
    bad = 0
    for fp in guarded:
        for ln, var, src in findings(fp.read_text(errors="replace")):
            bad += 1
            print(f"[exit-capture] DEAD ARM  {fp}:{ln}  {src[:100]}", file=sys.stderr)
            print(f"[exit-capture]   `set -e` kills this before {var}=$? runs. "
                  f"Use `{var}=0` then `… || {var}=$?`.", file=sys.stderr)
    if bad:
        print(f"[exit-capture] BLOCKED: {bad} exit-capture(s) unreachable under `set -e` "
              f"across {len(guarded)} guarded file(s).", file=sys.stderr)
        return 2
    print(f"[exit-capture] {len(guarded)} `set -e` shell file(s) of {len(files)} scanned, "
          "0 unreachable exit captures.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
