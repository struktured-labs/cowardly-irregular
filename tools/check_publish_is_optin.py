#!/usr/bin/env python3
"""No `butler push` may be reachable without --publish. Assert it; a comment is not a guard.

WHY THIS EXISTS
---------------
publish_all.sh's --dry-run says, in a comment:

    "Publishing is opt-in by construction in every deploy_*.sh — without --publish they run
     every gate and stop at gate 4 — so a dry run is not a separate code path that could
     drift from the real one."

Everything downstream leans on that sentence. `--dry-run` rehearses a publish by OMITTING one
flag. `--rollback` is only safe to exercise because `--dry-run` contains. If the sentence stops
being true in any one of the four deploy entry points, a rehearsal ships a build — and in the
rollback case it ships a SUPERSEDED build over a newer live one, which is the worst outcome
this lane can produce.

**The sentence was false within recent memory.** deploy_web.sh's own header records it:

    "Until 2026-08-22 this script PUBLISHED BY DEFAULT and you had to remember --gates-only to
     avoid it, while its sibling refused to publish unless you passed --publish. Two scripts in
     one lane, opposite defaults, and the dangerous one was the one whose header said THE
     canonical web deploy."

Note what that regression actually WAS. It was **not a missing gate** — the script had a gate.
The DEFAULT was wrong. So a check that merely finds a gate would have passed the exact defect
it exists to prevent, which is why the default gets its own assertion below.

WHAT IT CHECKS, per script that contains a push site
----------------------------------------------------
  1. The `--publish` argument sets some flag (the flag is DERIVED from the CLI contract, not
     hardcoded to the name `PUBLISH` — a rename must not be reported as a defect, and a check
     pinned to a spelling passes when the spelling is right and the value is wrong).
  2. That flag is initialised to the NOT-publishing value before the argument is parsed.
  3. A gate tests the flag and its body EXITS. An `if` that tests the flag and merely prints is
     not a gate.
  4. Every push site appears after that gate closes.

A script with no push site (deploy_linux.sh, deploy_windows.sh — thin wrappers that exec
deploy_desktop.sh) is reported as delegating and is not a finding. That is a vacuous pass by
construction, so EXPECT_MIN_PUSHERS below refuses to call the corpus clean if too few scripts
actually contain a push.

Usage:  check_publish_is_optin.py [tools-dir]
        check_publish_is_optin.py --selftest
Exit:   0 every push site is gated · 1 at least one is not · 2 unusable
"""
import os
import re
import sys
import tempfile

TARGET_PREFIXES = ("deploy_",)

# PARTLY contract-derived, and the comment used to claim it fully was. The CONTRACT is three
# channels across two scripts — web has its own, linux and windows share deploy_desktop.sh — so
# "at least 2 scripts push" does follow from the channel structure. But the exact 2 is still an
# OBSERVATION of origin/main @ 5aef5287 (2026-09-11), of a tree this lane writes.
# ⚠ Its job is to notice the push-site REGEX breaking, not to prove a fact about an independent
# corpus. Measured: deploy_desktop.sh
# and deploy_web.sh each contain exactly one push site; the linux/windows wrappers contain
# none. If FEWER than two scripts carry a push, the likely explanation is that the push-site
# regex stopped matching — not that the lane stopped publishing. "0 push sites, all gated" is
# this tool reporting its own blindness as success.
EXPECT_MIN_PUSHERS = 2

# `"${BUTLER_BIN}" push …`, `butler push …`, `$BUTLER push …`, `$(command -v butler) push …`
#
# ⚠ MEASURED 2026-09-11, by probing the half of this file I had hardened LESS. Every one of the
# eleven selftest probes spelled the push the SAME way — `"${BUTLER_BIN}" push`. So the
# JUDGEMENT half (gate, default, dominance, wrappers) was armed eight ways and the DETECTION
# half was armed once. Feeding ten real spellings through audit() found two invisible:
#
#     "${BUTLER_BIN}" \            <- line continuation: the push is on the NEXT line
#         push out/ "$T"
#     $(command -v butler) push …  <- substitution: `)` sits where the regex wants a name
#
# A push site this cannot SEE is reported as "no push site" — which, since the wrapper fix,
# means the file is checked for delegation instead and passes. **An undetected push is a
# silent exemption**, the same failure as the wrapper exemption and reached by a different
# road. Latent, not live: both shipped pushes use a detected form, 0 current violations.
PUSH_RE = re.compile(r'(?:\$\{?[A-Za-z_][A-Za-z0-9_]*\}?|\bbutler\b|\))["\']?\s+push\b')
# A script that hands off to another deploy script. DELIBERATELY OVER-BROAD: any mention of
# another deploy_*.sh counts as a delegation site. The first version required a leading
# exec/bash/sh/source keyword and missed `PLAT=linux "$D"/deploy_desktop.sh --publish "$@"` —
# an env-prefixed indirect call, which is an ordinary way to write it.
# Over-broad is the right error here: a false delegation site costs one extra line that is then
# checked for --publish, while a missed one is silent. (cowir-sprites' rule — for a corpus,
# over-broad beats precise, because precise fails by silent exclusion.)
DELEGATE_RE = re.compile(r'\bdeploy_[a-z_]+\.sh\b')
# the line that handles --publish, and the flag it sets
OPTIN_RE = re.compile(r'--publish\b')
SETS_RE = re.compile(r'\b([A-Za-z_][A-Za-z0-9_]*)=1\b')


class Unusable(Exception):
    """Cannot evaluate — distinct from 'evaluated and found a defect'."""


def strip_comments(lines):
    """Blank full-line comments, preserving indices. Both real scripts discuss pushing at
    length in prose; the word `push` in a comment is not a push site."""
    return ['' if l.lstrip().startswith('#') else l for l in lines]


def join_continuations(lines):
    """Fold `\\`-continued lines onto the first one, preserving INDICES so line numbers stay
    true and dominance comparisons against the gate remain valid.

    A long butler invocation is exactly the kind that gets wrapped — the real ones already
    carry `--userversion "$USERVERSION"` — so the continuation form is not hypothetical.
    """
    out = list(lines)
    i = 0
    while i < len(out):
        if out[i].rstrip().endswith('\\'):
            j = i
            merged = out[i].rstrip()[:-1]
            while j + 1 < len(out):
                j += 1
                merged += ' ' + out[j].strip()
                out[j] = ''          # consumed; index kept so numbering does not shift
                if not out[j - 1].rstrip().endswith('\\') and not merged.rstrip().endswith('\\'):
                    break
                if not lines[j].rstrip().endswith('\\'):
                    break
            out[i] = merged
            i = j + 1
        else:
            i += 1
    return out


def find_gate(lines, flag):
    """Line index of the `fi` closing an if-block that tests `flag` and exits. None if absent.

    Requiring the exit is the point: `if [ "$PUBLISH" != "1" ]; then echo "not publishing"; fi`
    reads exactly like a gate and stops nothing.
    """
    test_re = re.compile(rf'\bif\b.*\$\{{?{re.escape(flag)}\}}?\b')
    for i, l in enumerate(lines):
        if not test_re.search(l):
            continue
        depth = 0
        for j in range(i, len(lines)):
            depth += len(re.findall(r'\bif\b', lines[j]))
            depth -= len(re.findall(r'\bfi\b', lines[j]))
            if depth <= 0:
                body = '\n'.join(lines[i:j + 1])
                if re.search(r'\bexit\b', body):
                    return j
                break
    return None


def audit(path):
    """Return (push_lines, findings, delegation_lines) for one script.

    delegation_lines is EMITTED, not just used: a wrapper whose hand-off this cannot see would
    otherwise print the same reassuring line as one that was genuinely checked. See run().
    """
    raw = open(path, encoding="utf-8", errors="replace").read().splitlines()
    lines = join_continuations(strip_comments(raw))

    pushes = [i for i, l in enumerate(lines) if PUSH_RE.search(l)]
    if not pushes:
        # ⛔ A SCRIPT WITH NO PUSH SITE IS NOT AUTOMATICALLY SAFE. deploy_linux.sh and
        # deploy_windows.sh contain no push of their own — they exec deploy_desktop.sh — so
        # the first version of this file printed "no push site (delegates)" and checked
        # nothing further. That asymmetry (two subjects examined, two waved through) had a
        # TRUE explanation, which is exactly why it was never interrogated: explaining why an
        # instrument treats two members of its subject differently answers a different
        # question from whether it SHOULD.
        #
        # A delegating wrapper IS a publish entry point. `tools/deploy_linux.sh --publish <tag>`
        # reaches butler push — measured 2026-09-11. So a wrapper that INJECTS the flag into
        # its delegate publishes without the caller ever passing it:
        #
        #     exec env PLAT=linux "$(dirname "$0")/deploy_desktop.sh" --publish "$@"
        #
        # Measured: that wrapper passed this guard GREEN, 0 findings, exit 0. The real ones are
        # safe because they forward "$@" untouched — safe by how they happen to be written,
        # which is not the same as checked.
        findings = []
        delegations = [i + 1 for i, l in enumerate(lines) if DELEGATE_RE.search(l)]

        # ⚠ The first version of this checked for --publish ONLY ON THE DELEGATION LINE. That
        # reads half the script and infers the rest, in the check whose whole subject is "a
        # wrapper must not introduce the flag". Measured — both of these injected it invisibly:
        #
        #     FLAG="--publish"; exec … deploy_desktop.sh $FLAG "$@"
        #     set -- --publish "$@"; exec … deploy_desktop.sh "$@"
        #
        # A wrapper's contract is that it FORWARDS the caller's arguments and adds no publish
        # flag of its own, so the predicate is "does the literal --publish appear anywhere in
        # this wrapper's code", not "on one line". Over-broad on purpose: a wrapper with a
        # legitimate reason to name the flag in live code is rare enough to be worth a look,
        # and a missed injection is silent. (Comments are already stripped, so a usage comment
        # mentioning --publish does not trip it.)
        if delegations:
            for i, l in enumerate(lines):
                if re.search(r'(^|[\s="\'(])--publish(\s|$|["\')])', l):
                    findings.append((i + 1,
                                     "a delegating wrapper NAMES --publish in its own code. A "
                                     "wrapper must forward the caller's arguments and add no "
                                     "publish flag of its own; calling it without the flag may "
                                     "still publish. A wrapper is a publish entry point, not "
                                     "an exemption"))
        return [], findings, delegations

    findings = []
    delegations = []

    optin_lines = [i for i, l in enumerate(lines) if OPTIN_RE.search(l)]
    flag = None
    for i in optin_lines:
        m = SETS_RE.search(lines[i])
        if m:
            flag, optin_at = m.group(1), i
            break
    if flag is None:
        findings.append((pushes[0] + 1,
                         "this script pushes, but nothing here parses --publish into a flag — "
                         "there is no opt-in to verify"))
        return pushes, findings, delegations

    # 2. default must be the NOT-publishing value, set before the argument is parsed.
    init = None
    for i in range(optin_at):
        if re.match(rf'\s*{re.escape(flag)}=(\S+)', lines[i]):
            init = re.match(rf'\s*{re.escape(flag)}=(\S+)', lines[i]).group(1).strip('"\'')
    if init is None:
        findings.append((optin_at + 1,
                         f"`{flag}` is never initialised before --publish is parsed; an unset "
                         f"flag is not a safe default"))
    elif init not in ('0', ''):
        findings.append((optin_at + 1,
                         f"`{flag}` DEFAULTS TO {init!r} — publishing is opt-OUT. This is the "
                         f"2026-08-22 web regression exactly: the gate was present and the "
                         f"default was wrong"))

    # 3./4. gate exists, exits, and dominates every push.
    gate = find_gate(lines, flag)
    if gate is None:
        findings.append((pushes[0] + 1,
                         f"no gate: nothing tests `{flag}` and exits before the push"))
    else:
        for p in pushes:
            if p <= gate:
                findings.append((p + 1,
                                 f"push site is NOT dominated by the `{flag}` gate "
                                 f"(gate closes at line {gate + 1}) — reachable without "
                                 f"--publish"))
    return pushes, findings, delegations


def run(tools_dir):
    if not os.path.isdir(tools_dir):
        raise Unusable(f"[optin] BLOCKED: {tools_dir} is not a directory.")
    targets = sorted(f for f in os.listdir(tools_dir)
                     if f.endswith('.sh') and f.startswith(TARGET_PREFIXES))
    if not targets:
        raise Unusable(f"[optin] BLOCKED: no deploy_*.sh in {tools_dir}. An empty target set "
                       f"is not a clean result.")

    pushers = 0
    bad = 0
    print(f"[optin] {len(targets)} deploy script(s): {', '.join(targets)}")
    for t in targets:
        pushes, findings, delegations = audit(os.path.join(tools_dir, t))
        if not pushes and not findings:
            if delegations:
                # EMIT THE SET. @cowir-story's rule: a probe that prints what it LOCATED cannot
                # have a missing positive control. Measured before this change — a wrapper that
                # delegates AND injects --publish through a form the regex missed printed the
                # IDENTICAL line to the safe real wrapper, exit 0. The verdict got more
                # confident than the check.
                print(f"[optin]   ok    {t}  no push site; delegates at line(s) "
                      f"{delegations} without injecting --publish")
            else:
                bad += 1
                print(f"[optin]   NEITHER PUSHES NOR DELEGATES  {t}", file=sys.stderr)
                print(f"[optin]     this script has no push site AND no reference to another "
                      f"deploy_*.sh.", file=sys.stderr)
                print(f"[optin]     If it is a wrapper, the delegation detector missed it and "
                      f"the hand-off is", file=sys.stderr)
                print(f"[optin]     UNCHECKED for an injected --publish. If it genuinely does "
                      f"neither, it does not", file=sys.stderr)
                print(f"[optin]     belong in the deploy_* namespace this guard trusts.",
                      file=sys.stderr)
            continue
        if not pushes:
            for (ln, why) in findings:
                bad += 1
                print(f"[optin]   PUBLISHES WITHOUT --publish  {t}:{ln}", file=sys.stderr)
                print(f"[optin]                                {why}", file=sys.stderr)
            continue
        pushers += 1
        if not findings:
            print(f"[optin]   ok    {t}  push at line(s) {[p + 1 for p in pushes]} gated on "
                  f"--publish, flag defaults to off")
        for (ln, why) in findings:
            bad += 1
            print(f"[optin]   REACHABLE WITHOUT --publish  {t}:{ln}", file=sys.stderr)
            print(f"[optin]                                {why}", file=sys.stderr)

    print(f"[optin] {pushers} script(s) contain a push site · {bad} finding(s)")

    if pushers < EXPECT_MIN_PUSHERS:
        raise Unusable(
            f"[optin] BLOCKED: only {pushers} script(s) contain a push site, expected at least "
            f"{EXPECT_MIN_PUSHERS}.\n"
            f"        Far likelier that the push-site regex stopped matching than that the lane\n"
            f"        stopped publishing. '0 push sites, all gated' is this tool reporting its\n"
            f"        own blindness as success. If a channel was genuinely retired, lower\n"
            f"        EXPECT_MIN_PUSHERS deliberately in the same commit.")

    if bad:
        print(f"[optin] publish_all --dry-run and --rollback both rehearse by WITHHOLDING "
              f"--publish. If that flag is not what decides, a rehearsal ships a build.",
              file=sys.stderr)
        return 1
    return 0


# ── self-test ────────────────────────────────────────────────────────────────
GOOD = """#!/usr/bin/env bash
PUBLISH=0
[ "${1:-}" = "--publish" ] && { PUBLISH=1; shift; }
run_gates
if [ "$PUBLISH" != "1" ]; then
    echo "gates passed, nothing pushed"
    exit 0
fi
"${BUTLER_BIN}" push out/ "$T" --userversion "$V"
"""

# name: (src, expected exit, reason fragment the verdict must be reached BY; "" = no finding)
PROBES = {
    "gated, default off — the shipped shape": (GOOD, 0, ""),

    "flag named differently": (GOOD.replace("PUBLISH", "DO_PUBLISH"), 0, ""),

    "DEFAULT IS ON — the 2026-08-22 regression": (
        GOOD.replace("PUBLISH=0", "PUBLISH=1"), 1, "DEFAULTS TO '1'"),

    "no gate at all": ("""#!/usr/bin/env bash
PUBLISH=0
[ "${1:-}" = "--publish" ] && { PUBLISH=1; shift; }
"${BUTLER_BIN}" push out/ "$T"
""", 1, "no gate"),

    "push BEFORE the gate": ("""#!/usr/bin/env bash
PUBLISH=0
[ "${1:-}" = "--publish" ] && { PUBLISH=1; shift; }
"${BUTLER_BIN}" push out/ "$T"
if [ "$PUBLISH" != "1" ]; then
    exit 0
fi
echo done
""", 1, "NOT dominated"),

    "gate tests the flag but never exits": ("""#!/usr/bin/env bash
PUBLISH=0
[ "${1:-}" = "--publish" ] && { PUBLISH=1; shift; }
if [ "$PUBLISH" != "1" ]; then
    echo "not publishing"
fi
"${BUTLER_BIN}" push out/ "$T"
""", 1, "no gate"),

    "flag never initialised": ("""#!/usr/bin/env bash
[ "${1:-}" = "--publish" ] && { PUBLISH=1; shift; }
if [ "$PUBLISH" != "1" ]; then
    exit 0
fi
"${BUTLER_BIN}" push out/ "$T"
""", 1, "never initialised"),

    "pushes but parses no --publish": ("""#!/usr/bin/env bash
"${BUTLER_BIN}" push out/ "$T"
""", 1, "nothing here parses --publish"),

    "wrapper that INJECTS --publish into its delegate": ("""#!/usr/bin/env bash
# a thin wrapper with no push of its own — but it publishes anyway
exec env PLAT=linux "$(dirname "$0")/deploy_desktop.sh" --publish "$@"
""", 1, "NAMES --publish in its own code"),

    "wrapper that forwards \"$@\" untouched": ("""#!/usr/bin/env bash
exec env PLAT=linux "$(dirname "$0")/deploy_desktop.sh" "$@"
""", 0, ""),

    # These two arms prove DETECTION by demanding a finding that is only reachable if the push
    # is seen at all. If PUSH_RE misses the form, the script reports "no push site" and exits 0
    # — so a passing arm here cannot be satisfied by blindness.
    "push SPLIT ACROSS LINES, before the gate": ("""#!/usr/bin/env bash
PUBLISH=0
[ "${1:-}" = "--publish" ] && { PUBLISH=1; shift; }
"${BUTLER_BIN}" \\
    push out/ "$T" --userversion "$V"
if [ "$PUBLISH" != "1" ]; then
    exit 0
fi
echo done
""", 1, "NOT dominated"),

    "push via $(command -v butler), no gate": ("""#!/usr/bin/env bash
PUBLISH=0
[ "${1:-}" = "--publish" ] && { PUBLISH=1; shift; }
$(command -v butler) push out/ "$T"
""", 1, "no gate"),

    "wrapper delegating via an INDIRECT form": ("""#!/usr/bin/env bash
D="$(dirname "$0")"
PLAT=linux "$D"/deploy_desktop.sh --publish "$@"
""", 1, "NAMES --publish in its own code"),

    "wrapper injecting --publish via a VARIABLE": ("""#!/usr/bin/env bash
FLAG="--publish"
exec env PLAT=linux "$(dirname "$0")/deploy_desktop.sh" $FLAG "$@"
""", 1, "NAMES --publish in its own code"),

    "wrapper prepending --publish via set --": ("""#!/usr/bin/env bash
set -- --publish "$@"
exec env PLAT=linux "$(dirname "$0")/deploy_desktop.sh" "$@"
""", 1, "NAMES --publish in its own code"),

    "wrapper naming --publish only in a COMMENT": ("""#!/usr/bin/env bash
# to publish: tools/deploy_linux.sh --publish <tag>
exec env PLAT=linux "$(dirname "$0")/deploy_desktop.sh" "$@"
""", 0, ""),

    "push appears only in a comment": ("""#!/usr/bin/env bash
# "${BUTLER_BIN}" push out/ "$T"   <- this is prose about the push, not a push
# butler push would go here without the gate
PUBLISH=0
[ "${1:-}" = "--publish" ] && { PUBLISH=1; shift; }
if [ "$PUBLISH" != "1" ]; then
    exit 0
fi
"${BUTLER_BIN}" push out/ "$T"
""", 0, ""),
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
        if extra is not None:
            ok2, detail = extra()
            if not ok2:
                failed += 1
                print(f"  FAIL  {name:48} exit {got} — {detail}")
                return
        if got == want:
            passed += 1
            print(f"  ok    {name:48} exit {got}{(' — ' + detail) if detail else ''}")
        else:
            failed += 1
            print(f"  FAIL  {name:48} exit {got} (wanted {want})")

    with tempfile.TemporaryDirectory() as d:
        for i, (name, (src, want, frag)) in enumerate(PROBES.items()):
            td = os.path.join(d, f"t{i}")
            os.makedirs(td)
            open(os.path.join(td, "deploy_probe.sh"), "w").write(src)
            # Pad to the pusher floor with known-good scripts so the vacuity check never masks
            # the arm under test. TWO, not one: a WRAPPER probe contributes zero pushers, so a
            # single filler left the dir at 1 < EXPECT_MIN_PUSHERS and both wrapper arms came
            # back Unusable(2) instead of their real verdict. The floor is a vacuity control and
            # it suppressed the exact finding it exists to protect — worth remembering that a
            # control can mask as well as reveal, and that a fixture has to clear it explicitly.
            open(os.path.join(td, "deploy_filler.sh"), "w").write(GOOD)
            open(os.path.join(td, "deploy_filler2.sh"), "w").write(GOOD)

            def check(td=td, frag=frag):
                _p, f, _d = audit(os.path.join(td, "deploy_probe.sh"))
                if frag == "":
                    return (not f), (f"falsely found {f[0][1][:40]!r}" if f else "no finding")
                if not f:
                    return False, f"no finding at all; wanted ...{frag}..."
                if not any(frag in why for (_ln, why) in f):
                    return False, (f"RIGHT VERDICT, WRONG REASON: wanted ...{frag}... got "
                                   f"{f[0][1]!r}")
                return True, frag

            arm(name, want, lambda td=td: run(td), check)

        # ── instrument-died arms ──
        empty = os.path.join(d, "empty")
        os.makedirs(empty)
        arm("no deploy scripts at all", 2, lambda: run(empty))

        nopush = os.path.join(d, "nopush")
        os.makedirs(nopush)
        open(os.path.join(nopush, "deploy_a.sh"), "w").write(
            '#!/usr/bin/env bash\nexec env PLAT=linux "$(dirname "$0")/deploy_desktop.sh" "$@"\n')
        arm("only wrappers — too few push sites to trust", 2, lambda: run(nopush))

        arm("missing directory is unusable, not clean", 2,
            lambda: run(os.path.join(d, "nope")))

    print()
    print(f"selftest: {passed} passed, {failed} failed")
    if not {0, 1, 2} <= saw:
        print(f"selftest: BROKEN — outcomes observed {sorted(saw)}; all of 0/1/2 required.",
              file=sys.stderr)
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
