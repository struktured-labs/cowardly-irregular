#!/usr/bin/env python3
"""Every polling loop in the deploy scripts must be bounded. Assert it, don't assume it.

WHY THIS EXISTS
---------------
`deploy_web.sh` shipped this for months:

    until "${BUTLER_BIN}" status "${ITCH_TARGET}" 2>/dev/null | grep -q "${VERSION}"; do sleep 8; done

No timeout. If the version never registered, the web chain did not fail — it never returned.
publish_all runs web LAST and blocks behind it, so one build itch never finished processing
stops the publish cadence with no RED, no exit code, and no log line. An infinite hang is the
worst of the three outcomes available to a guard: a failure says something, a false pass says
the wrong thing, a hang says nothing. **Absence is what you notice last.**

It survived because deploy_desktop.sh's own comment WROTE IT DOWN — "deploy_web.sh's equivalent
loop has no timeout" — while bounding only itself. A hazard you have documented reads, to every
later reader including its author, as a hazard you have considered and accepted. This file is
the difference between the note and the guard.

WHAT IT CHECKS
--------------
A POLLING LOOP is any loop whose body calls `sleep`. For each one:

  for X in <list>        BOUNDED   — the list is evaluated once at entry, so the count is fixed
  for ((init;cond;inc))  BOUNDED   — unless the condition field is empty (`for ((;;))`)
  while/until            BOUNDED   — only if the condition makes a numeric comparison AND some
                                     variable in that comparison is assigned in the body

That last clause is the whole point, and it is why this is not a grep for `-lt`. A condition
that compares a counter which nothing ever advances is not a bound; it is an unbounded loop
wearing the costume of a bounded one, and it is the single most likely way for this guard to be
defeated by a well-meaning edit. It gets its own selftest arm.

WHAT IT DELIBERATELY DOES NOT DO
--------------------------------
Read comments. A crude scan for this defect produces false positives on the file DOCUMENTING
the defect — the comment above quoting the old `until` line is textually indistinguishable from
the line itself. Full-line comments are stripped before analysis, and an arm asserts that a
defect appearing ONLY in a comment is not reported.

Known limits, stated rather than hidden: `do`/`done` are counted as words on comment-stripped
lines, so those keywords inside a quoted string or heredoc would miscount nesting; a trailing
`# ...` on a code line is NOT stripped (stripping it safely requires knowing about quoting);
and `for x in $(yes)` is treated as bounded because the finite-list assumption is nearly always
right and the alternative is a shell interpreter.

Usage:  check_polling_bounded.py [tools-dir]      default: the repo's tools/ beside this file
        check_polling_bounded.py --selftest
Exit:   0 every polling loop is bounded
        1 at least one is UNBOUNDED (named, with the reason)
        2 unusable — no target files, no pushers, or a pusher with no polling loop
"""
import importlib.util
import os
import re
import sys
import tempfile

# Targets are GLOB-DERIVED, not a hand-list. deploy_linux.sh and deploy_windows.sh already
# exist as thin wrappers; the next channel's script must be covered on the day it is written,
# not on the day someone remembers to add it here.
TARGET_GLOBS = ("deploy_", "publish_")

# ── the floor is DERIVED, not declared ───────────────────────────────────────────────────
# This was `EXPECT_MIN_LOOPS = 2`, a number measured off the tree. Two objections retired it:
#
#   1. @cowir-autogrind: THE TRAP WAS THE FIX. When that floor fired, this tool PRINTED the
#      one-line edit that disables it — "lower EXPECT_MIN_LOOPS deliberately". A guard is only
#      as good as the repair it invites at 2am, and mine invited its own removal.
#   2. It was corpus-dated. Measured across the repo's own tags, the count was 1 at
#      v3.33.29-alpha and 2 from .291 — so the number was right for one era and a false
#      positive on every earlier tree.
#
# The replacement is a RELATIONSHIP, and there is no number in it:
#
#     a script that PUSHES must be able to TIME OUT waiting for confirmation,
#     therefore every real push site's file carries at least one polling loop.
#
# Push sites are themselves derived from the call site by check_publish_is_optin.py, which is
# IMPORTED rather than re-implemented — two parses of the same thing is how they drift, and I
# spent a morning on exactly that. A stub push (a *STUB* binary, a test double) is exempt: it
# is not waiting on itch and has nothing to time out.
#
# ⛔ The repair when this fires is "restore the confirmation loop" or "fix the loop finder".
# Both are correct actions. Neither is a number you can lower.
def _pushers(tools_dir):
    """Files with a REAL push site, via the sibling guard's detector. Raises if it is absent —
    a missing guard is not a passing one, and silently falling back to a local copy of the
    regex would recreate the drift this import exists to prevent."""
    sib = os.path.join(os.path.dirname(os.path.abspath(__file__)), "check_publish_is_optin.py")
    if not os.path.isfile(sib):
        raise Unusable(f"[waits] BLOCKED: {sib} not found. This tool derives its expectation "
                       f"from that guard's push-site detector; without it there is nothing to "
                       f"check the loops against, and 'no pushers, all bounded' would be "
                       f"vacuous.")
    spec = importlib.util.spec_from_file_location("_optin", sib)
    optin = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(optin)
    out = {}
    for f in sorted(os.listdir(tools_dir)):
        if not f.endswith(".sh"):
            continue
        pushes, _find, _deleg, _stubs, _orch = optin.audit(os.path.join(tools_dir, f))
        if pushes:
            out[f] = pushes
    return out

LOOP_HEAD_RE = re.compile(r'^\s*(while|until|for)\b')
# ⚠ `<` and `>` are COMPARISONS ONLY INSIDE (( )). Everywhere else in shell they are
# REDIRECTS, and the very defect this file exists to catch contains one:
#
#     until butler status "$T" 2>/dev/null | grep -q "$V"; do sleep 8; done
#                              ^ this `>` is a redirect
#
# A naive `[<>]=?` matches it, so the first version of this script called that loop unbounded
# for the reason "compares a counter the body never assigns" — the right verdict reached
# through a false premise, on the exact line the tool was written for. It passed its own
# selftest, because that arm asserted only that SOMETHING was named. Assert on WHY, not whether.
ARITH_CMP_RE = re.compile(r'-(?:lt|le|gt|ge|eq|ne)\b')
PAREN_CMP_RE = re.compile(r'[<>]=?|==|!=')


def has_comparison(cond):
    if ARITH_CMP_RE.search(cond):
        return True
    return any(PAREN_CMP_RE.search(m.group(1)) for m in re.finditer(r'\(\((.*?)\)\)', cond))


def cond_names(cond):
    """Variables the condition actually reads — $refs, plus bare identifiers inside (( )).

    Scraping every word gave `butler`, `grep`, `status`, `dev`, `null` as candidate counters.
    Harmless to the verdict, but it made the diagnostic read like noise, and a diagnostic
    nobody reads is how a wrong reason survives.
    """
    names = set(re.findall(r'\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?', cond))
    for m in re.finditer(r'\(\((.*?)\)\)', cond):
        names |= set(re.findall(r'\b([A-Za-z_][A-Za-z0-9_]*)\b', m.group(1)))
    return names


class Unusable(Exception):
    """Cannot evaluate — distinct from 'evaluated and found a defect'."""


def strip_comments(lines):
    """Blank out full-line comments, preserving indices so line numbers stay true."""
    out = []
    for l in lines:
        out.append('' if l.lstrip().startswith('#') else l)
    return out


def strip_heredocs(lines):
    """Blank heredoc BODY lines, preserving indices so line numbers stay true.

    ⚠ MEASURED 2026-09-11. The docstring used to STATE this limit and nothing enforced it —
    "do/done are counted as words, so those keywords inside a quoted string or heredoc would
    miscount nesting". Knowing a limitation and encoding it are different things, and the gap
    between them is invisible in the output.

    Constructed the trigger rather than reasoning about it:

        until butler status "$X" | grep -q "$V"; do
            cat <<'MSG'
            not done yet          <- \bdone\b matches HERE
        MSG
            sleep 8
        done

    `\bdone\b` on the prose line closed the loop range early, so the scanned body no longer
    contained the `sleep`, so it was not a polling loop, so **the unbounded loop vanished from
    the census entirely**. Not misclassified — ABSENT. The report read "0 UNBOUNDED".

    It was caught only because the vacuity check then failed the run. That
    is the vacuity floor doing exactly its job, and the first evidence I have that it earns its
    keep — but it only fires when the drop crosses the floor. A corpus with five polling loops
    losing one would have reported a clean census.

    Zero current exposure: the real deploy scripts contain 0 heredocs. Latent, not live.
    """
    out = list(lines)
    i = 0
    while i < len(out):
        m = re.search(r'<<-?\s*[\'"]?([A-Za-z_][A-Za-z0-9_]*)[\'"]?\s*$', out[i])
        if m:
            delim = m.group(1)
            j = i + 1
            while j < len(out) and out[j].strip() != delim:
                out[j] = ''
                j += 1
            if j < len(out):
                out[j] = ''      # the closing delimiter line
            i = j + 1
        else:
            i += 1
    return out


def find_loops(lines):
    """Yield (start_idx, end_idx) for every loop, using do/done depth on stripped lines."""
    loops = []
    for i, l in enumerate(lines):
        if not LOOP_HEAD_RE.match(l):
            continue
        depth = 0
        started = False
        for j in range(i, len(lines)):
            depth += len(re.findall(r'\bdo\b', lines[j]))
            if depth:
                started = True
            depth -= len(re.findall(r'\bdone\b', lines[j]))
            if started and depth <= 0:
                loops.append((i, j))
                break
        else:
            # An unterminated loop is a syntax error the shell would catch; not our job, but
            # it must not silently vanish from the census.
            loops.append((i, len(lines) - 1))
    return loops


def classify(head, body):
    """Return (bounded: bool, reason: str) for one polling loop."""
    kw = LOOP_HEAD_RE.match(head).group(1)

    if kw == 'for':
        if 'for ((' in head.replace('for((', 'for (('):
            inner = head.split('((', 1)[1]
            fields = inner.split(';')
            if len(fields) >= 2 and fields[1].strip() == '':
                return False, "C-style `for` with an EMPTY condition field — never terminates"
            return True, "C-style `for` with a condition"
        return True, "`for` over a list evaluated once at entry — iteration count is fixed"

    # while / until: the condition is everything up to `; do` or a trailing `do`.
    cond = re.split(r';\s*do\b|\bdo\b', head, maxsplit=1)[0]
    cond = re.sub(r'^\s*(while|until)\b', '', cond).strip()

    if cond in ('true', ':', '[ 1 ]', '[[ 1 ]]'):
        return False, f"condition is the constant `{cond}` with no counter — never terminates"

    if not has_comparison(cond):
        return False, ("condition makes no numeric comparison, so nothing bounds the iteration "
                       "count — it runs until the polled thing happens, or forever")

    # A comparison is necessary but NOT sufficient: the counter has to actually move.
    names = cond_names(cond)
    body_text = '\n'.join(body)
    for n in names:
        if re.search(rf'(^|[\s;(]){re.escape(n)}\s*=|\(\(\s*{re.escape(n)}\b|'
                     rf'{re.escape(n)}\+=|\blet\s+{re.escape(n)}\b', body_text, re.M):
            return True, f"condition compares `{n}`, and the body advances it"

    return False, ("the condition compares a counter that the body NEVER assigns — this looks "
                   f"bounded and is not (names checked: {', '.join(sorted(names)) or 'none'})")


def scan_file(path):
    raw = open(path, encoding="utf-8", errors="replace").read().splitlines()
    lines = strip_heredocs(strip_comments(raw))
    found = []
    for (a, b) in find_loops(lines):
        body = lines[a:b + 1]
        if not any(re.search(r'\bsleep\b', l) for l in body):
            continue  # not a polling loop; a `while read` over a file is not our business
        ok, why = classify(lines[a], body)
        found.append((a + 1, raw[a].strip(), ok, why))
    return found


def run(tools_dir):
    if not os.path.isdir(tools_dir):
        raise Unusable(f"[waits] BLOCKED: {tools_dir} is not a directory.")
    targets = sorted(f for f in os.listdir(tools_dir)
                     if f.endswith('.sh') and f.startswith(TARGET_GLOBS))
    if not targets:
        raise Unusable(f"[waits] BLOCKED: no deploy_*.sh / publish_*.sh in {tools_dir}. "
                       f"An empty target set is not a clean result.")

    total = bad = 0
    print(f"[waits] {len(targets)} deploy script(s): {', '.join(targets)}")
    for t in targets:
        for (ln, text, ok, why) in scan_file(os.path.join(tools_dir, t)):
            total += 1
            if ok:
                print(f"[waits]   ok    {t}:{ln}  {why}")
            else:
                bad += 1
                print(f"[waits]   UNBOUNDED  {t}:{ln}", file=sys.stderr)
                print(f"[waits]              {text}", file=sys.stderr)
                print(f"[waits]              {why}", file=sys.stderr)

    print(f"[waits] {total} polling loop(s) examined · {total - bad} bounded · {bad} UNBOUNDED")

    # DERIVED EXPECTATION: every real pusher must carry a polling loop to time out on.
    pushers = _pushers(tools_dir)
    if not pushers:
        raise Unusable(
            "[waits] BLOCKED: no script in this directory contains a real push site, so there\n"
            "        is nothing whose post-push wait could be checked. Either the push-site\n"
            "        detector broke, or this is not a deploy tools directory. 'All bounded'\n"
            "        over an empty subject is vacuous.")
    missing = [f for f in pushers if not scan_file(os.path.join(tools_dir, f))]
    if missing:
        raise Unusable(
            f"[waits] BLOCKED: {', '.join(missing)} contains a butler push but NO polling loop.\n"
            f"        A script that pushes must be able to TIME OUT waiting for confirmation.\n"
            f"        Either the post-push wait was removed — a real regression, restore it —\n"
            f"        or this file's loop finder stopped matching. Both are worth stopping for,\n"
            f"        and neither is a number you can lower.")

    if bad:
        print(f"[waits] a hang is the quietest way for the publish cadence to stop — it produces "
              f"no RED, no exit code, and no log line.", file=sys.stderr)
        return 1
    return 0


# ── self-test ────────────────────────────────────────────────────────────────
# Third field is the REASON the verdict must be reached BY — not merely that a line was
# named. The first version of this table carried a boolean "was something named?", and that
# is exactly what let the redirect bug through: the `until` probe was called unbounded for a
# reason that was fiction, and the arm said ok. A verdict is not a result; the premise is.
PROBES = {
    # name: (script body, expected exit, reason fragment the probe's own loop must carry)
    "bounded while + counter the body advances": ("""#!/usr/bin/env bash
CONFIRM_BUDGET="${CONFIRM_BUDGET:-900}"
_waited=0
while [ "$_waited" -lt "$CONFIRM_BUDGET" ]; do
    butler status "$T" | grep -q "$V" && break
    sleep 8; _waited=$((_waited+8))
done
""", 0, "the body advances it"),

    "bounded, counter spelled differently": ("""#!/usr/bin/env bash
tries=0
while [ "$tries" -lt "$MAX_TRIES" ]; do
    poll && break
    sleep 5
    tries=$((tries+1))
done
""", 0, "compares `tries`"),

    "bounded `for` over seq — the desktop form": ("""#!/usr/bin/env bash
for _ in $(seq 1 40); do
    butler status "$T" | grep -q "$V" && break
    sleep 8
done
""", 0, "evaluated once at entry"),

    "UNBOUNDED until — the shipped web defect": ("""#!/usr/bin/env bash
until butler status "$T" 2>/dev/null | grep -q "$V"; do sleep 8; done
""", 1, "makes no numeric comparison"),

    "UNBOUNDED while true": ("""#!/usr/bin/env bash
while true; do
    poll && break
    sleep 8
done
""", 1, "constant `true`"),

    "UNBOUNDED for ((;;))": ("""#!/usr/bin/env bash
for ((;;)); do
    poll && break
    sleep 8
done
""", 1, "EMPTY condition field"),

    "counter compared but NEVER advanced": ("""#!/usr/bin/env bash
_waited=0
while [ "$_waited" -lt 900 ]; do
    poll && break
    sleep 8
done
""", 1, "NEVER assigns"),

    # A heredoc body is prose, not code. Before strip_heredocs these two were indistinguishable
    # from each other AND from a clean file: the unbounded one VANISHED from the census.
    "UNBOUNDED loop, heredoc body says 'done'": ("""#!/usr/bin/env bash
until butler status "$X" | grep -q "$V"; do
    cat <<'MSG'
    not done yet
MSG
    sleep 8
done
""", 1, "makes no numeric comparison"),

    "bounded loop, heredoc body says 'done'": ("""#!/usr/bin/env bash
n=0
while [ "$n" -lt 40 ]; do
    cat <<'MSG'
    not done yet
MSG
    sleep 8; n=$((n+1))
done
""", 0, "compares `n`"),

    "defect appears ONLY in a comment": ("""#!/usr/bin/env bash
# This was `until butler status | grep -q "$V"; do sleep 8; done` — an UNBOUNDED wait.
# while true; do sleep 8; done
n=0
while [ "$n" -lt 40 ]; do
    poll && break
    sleep 8; n=$((n+1))
done
""", 0, "compares `n`"),

    "a non-polling loop is not our business": ("""#!/usr/bin/env bash
while IFS= read -r a; do echo "$a"; done < f
for CH in linux windows web; do echo "$CH"; done
n=0
while [ "$n" -lt 40 ]; do poll && break; sleep 8; n=$((n+1)); done
""", 0, "compares `n`"),
}


def selftest():
    passed = failed = 0
    saw = set()

    def arm(name, want, fn, extra=None):
        nonlocal passed, failed
        try:
            got = fn()
        except Unusable:
            got = 2
        saw.add(got)
        detail = ""
        if got == want and extra is not None:
            ok2, detail = extra()
            if not ok2:
                failed += 1
                print(f"  FAIL  {name:52} exit {got} but {detail}")
                return
        if got == want:
            passed += 1
            print(f"  ok    {name:52} exit {got}{(' — ' + detail) if detail else ''}")
        else:
            failed += 1
            print(f"  FAIL  {name:52} exit {got} (wanted {want})")

    with tempfile.TemporaryDirectory() as d:
        # Each probe gets its OWN tools dir, padded with a known-bounded PUSHER so the
        # filler so the floor check never masks the arm under test.
        # The filler must PUSH as well as poll: the expectation is now derived from push
        # sites, so a dir with no pusher is Unusable and would mask every arm.
        FILLER = ("#!/usr/bin/env bash\nPUBLISH=0\n"
                  "[ \"${1:-}\" = \"--publish\" ] && { PUBLISH=1; shift; }\n"
                  "if [ \"$PUBLISH\" != \"1\" ]; then exit 0; fi\n"
                  "k=0\nwhile [ \"$k\" -lt 9 ]; do sleep 1; k=$((k+1)); done\n"
                  "\"${BUTLER_BIN}\" push out/ \"$T\"\n")
        for i, (name, (src, want, frag)) in enumerate(PROBES.items()):
            td = os.path.join(d, f"t{i}")
            os.makedirs(td)
            open(os.path.join(td, "deploy_probe.sh"), "w").write(src)
            open(os.path.join(td, "deploy_filler.sh"), "w").write(FILLER)

            def check(td=td, frag=frag, want=want):
                hits = scan_file(os.path.join(td, "deploy_probe.sh"))
                if len(hits) != 1:
                    return False, f"expected exactly 1 polling loop in the probe, found {len(hits)}"
                ln, _text, ok, why = hits[0]
                if ok != (want == 0):
                    return False, f"line {ln} classified bounded={ok}, wrong direction"
                if frag not in why:
                    return False, (f"RIGHT VERDICT, WRONG REASON at line {ln}: "
                                   f"wanted ...{frag}... got {why!r}")
                return True, f"line {ln}: {frag}"

            arm(name, want, lambda td=td: run(td), check)

        # ── instrument-died arms: absence of input must NOT read as clean ──
        empty = os.path.join(d, "empty")
        os.makedirs(empty)
        arm("no deploy scripts at all — must not pass", 2, lambda: run(empty))

        # THE DERIVED RELATIONSHIP, armed directly: a pusher whose post-push wait was removed.
        # This is the arm that replaces EXPECT_MIN_LOOPS, and note what a red here tells you —
        # "restore the confirmation" or "fix the finder", never "lower a number".
        noloop = os.path.join(d, "noloop")
        os.makedirs(noloop)
        open(os.path.join(noloop, "deploy_pusher.sh"), "w").write(
            '#!/usr/bin/env bash\nPUBLISH=0\n'
            '[ "${1:-}" = "--publish" ] && { PUBLISH=1; shift; }\n'
            'if [ "$PUBLISH" != "1" ]; then exit 0; fi\n'
            '"${BUTLER_BIN}" push out/ "$T"\n')          # pushes, never waits
        arm("a PUSHER with no polling loop — wait was removed", 2, lambda: run(noloop))

        nopoll = os.path.join(d, "nopoll")
        os.makedirs(nopoll)
        open(os.path.join(nopoll, "deploy_x.sh"), "w").write(
            "#!/usr/bin/env bash\nfor CH in linux windows web; do echo $CH; done\n")
        arm("zero polling loops found — finder may be broken", 2, lambda: run(nopoll))

        arm("a missing directory is unusable, not clean", 2,
            lambda: run(os.path.join(d, "does-not-exist")))

    print()
    print(f"selftest: {passed} passed, {failed} failed")
    if not {0, 1, 2} <= saw:
        print(f"selftest: BROKEN — outcomes observed {sorted(saw)}; all of 0/1/2 are required, "
              f"or the arms are not exercising both directions.", file=sys.stderr)
        return 1
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    try:
        if len(sys.argv) > 1 and sys.argv[1] == "--selftest":
            sys.exit(selftest())
        here = os.path.dirname(os.path.abspath(__file__))
        sys.exit(run(sys.argv[1] if len(sys.argv) > 1 else here))
    except Unusable as e:
        print(str(e), file=sys.stderr)
        sys.exit(2)
