#!/usr/bin/env python3
# Derive the set of publish-path tools whose own selftest arms must run before a publish.
#
# Lived inside publish_all.sh until 2026-09-18. Moved out for one reason: publish_all.sh
# is the one script on this path that by convention has no selftest, so the derivation was
# the only guard here with no arms -- while being the guard that decides which OTHER guards
# get checked. A wrong answer here is silent by construction: too few members runs fewer
# arms and still prints success. Two defects in it in one day (a scope widened in one of two
# places; a docstring read as code) were each caught by a floor or by chasing an unexpected
# member, not by a test. Arms now live in derive_selftest_corpus_selftest.py.
#
# Contract: cwd = repo root. stdout = space-separated basenames. Any failure exits nonzero
# with the reason on stderr; publish_all.sh treats that as BLOCKED.
import os, re, subprocess, sys
# BOTH globs, or REF's language list is decorative: the frontier check below rejects any name
# not in `tracked`, so listing only *.sh silently vetoed every python tool no matter what REF
# said. Two places encoded the same scope and only one was widened — caught immediately by the
# membership floor below, which is the whole reason it is a membership floor and not a count.
tracked = set(os.path.basename(p) for p in subprocess.run(
    ["git", "ls-files", "tools/*.sh", "tools/*.py"], capture_output=True, text=True).stdout.split())
if not tracked:
    sys.exit("could not list tracked shell tools")
# A reference is ANY tracked tool basename in a non-comment line. Anchoring on "tools/"
# looked tighter and silently lost the entire desktop chain: deploy_linux.sh reaches it as
#     exec env PLAT=linux "$(dirname "$0")/deploy_desktop.sh" "$@"
# so deploy_desktop.sh and everything it invokes were invisible to the derivation.
# BOTH LANGUAGES. This was `.sh` only until 2026-09-18, which excluded every PYTHON gate on
# the publish path BY CONSTRUCTION — a derivation that cannot name a whole language. Measured
# then: 7 .py gates invoked by this chain, their arms run from THREE separate hand-lists in two
# files, and check_pck_complete.py — called at deploy_desktop:574, deploy_web:464 and
# make_web_stage:303, on every desktop AND web publish — had 8 working arms that nothing ran.
REF = re.compile(r"([A-Za-z0-9_]+\.(?:sh|py))")
# DISPATCHES on the flag: a case arm, a test against $1, or python's quoted form.
DISP = re.compile(r'^[^#]*(--selftest\)|=[ \t]*"?--selftest"?|["\']--selftest["\'])')
seen, frontier = set(), ["publish_all.sh"]
while frontier:
    b = frontier.pop()
    if b in seen:
        continue
    p = os.path.join("tools", b)
    if not os.path.isfile(p):
        continue
    seen.add(b)
    # PYTHON PROSE IS NOT CODE. Skipping only `#` lines was right while this scanned shell; the
    # moment it began reading .py it inherited the docstring hole this repo already knows about
    # -- a stripper that handles its own language's comments and nothing else. Measured
    # 2026-09-18: check_unbound_vars.py:184 cites "verify_release_artifact.sh:120" inside a
    # docstring, as prose about where a defect was once found, and that citation alone pulled
    # verify_release_artifact.sh into the selftest corpus. Admitted by the PATTERN, not by the
    # criterion -- and it has working arms, so nothing broke, which is exactly why a false
    # admission survives: an inflated corpus reads as thoroughness.
    # (Triple quotes are built with chr() so this block can be edited by scripts that are
    # themselves python without the delimiters colliding -- that collision ate the first
    # attempt at this patch.)
    _TQ = chr(34) * 3
    _SQ = chr(39) * 3
    _in_doc = None
    for line in open(p, encoding="utf-8", errors="replace"):
        if b.endswith(".py"):
            _t = line.strip()
            if _in_doc is not None:
                if _in_doc in _t:
                    _in_doc = None
                continue
            _opened = False
            for _q in (_TQ, _SQ):
                if _t.startswith(_q):
                    # Opens AND closes on one line -> encloses nothing further.
                    if not (len(_t) > len(_q) and _t.endswith(_q)):
                        _in_doc = _q
                    _opened = True
                    break
            if _opened:
                continue
        if line.lstrip().startswith("#"):
            continue
        for m in REF.finditer(line):
            if m.group(1) in tracked and m.group(1) not in seen:
                frontier.append(m.group(1))
# STRUCTURAL FLOOR, not a magic number: this chain publishes desktop and web, so a closure
# that has not reached both channel scripts did not walk the chain. That is exactly the bug
# the "tools/" anchor caused, and a count-based floor would have passed straight over it.
for required in ("deploy_desktop.sh", "deploy_web.sh"):
    if required not in seen:
        sys.exit("closure never reached %s -- the derivation is broken, not the tree" % required)
# TWO CONVENTIONS, and a tool qualifies under either: a --selftest FLAG, or a sibling
# <base>_selftest.py holding the arms. The sibling files are themselves EXCLUDED — they ARE
# the arms, not a subject with arms, exactly as the .sh selftest files always were.
def _has_arms(b):
    p = os.path.join("tools", b)
    if any(DISP.match(l) for l in open(p, encoding="utf-8", errors="replace")):
        return True
    return b.endswith(".py") and os.path.isfile(os.path.join("tools", b[:-3] + "_selftest.py"))

corpus = sorted(
    b for b in seen - {"publish_all.sh"}
    if not b.endswith(("_selftest.sh", "_selftest.py")) and _has_arms(b))

# ⛔ MEMBERSHIP FLOOR, NOT A COUNT. A count floor is satisfied by a SURVIVOR: if the REF
# pattern regressed to .sh-only the corpus would still be 18 tools and still look healthy,
# which is how the python half was invisible for months. Requiring one member of EACH
# language makes a whole language going missing LOUD. (cowir-controller, 2026-09-18.)
if not any(b.endswith(".sh") for b in corpus):
    sys.exit("derived corpus contains no .sh tool -- the derivation is broken, not the tree")
if not any(b.endswith(".py") for b in corpus):
    sys.exit("derived corpus contains no .py tool -- the derivation is broken, not the tree")
print(" ".join(corpus))
