#!/usr/bin/env python3
"""Every LFS-tracked file's working bytes must match the oid its pointer pins at HEAD.

WHY THIS EXISTS, AND WHY NO OTHER GATE IN THIS LANE CAN DO IT
─────────────────────────────────────────────────────────────
Audio is stored in git-lfs (`.gitattributes`: `*.ogg filter=lfs …`). The tracked blob is a
three-line pointer carrying `oid sha256:<hash>`; the bytes live in the LFS store. So a commit
DOES pin the audio — but only for a tree whose LFS blobs were actually fetched.

⛔ A tree with a stale LFS blob is invisible to every gate this lane already runs, and the
mechanism is that the gates and the defect share a cause:

    godot --import     re-derives .oggstr FAITHFULLY from whatever bytes are on disk
    the suite          reads the .oggstr
    the export         packs the .oggstr
    check_pck_complete counts artifacts the .import sidecars declare

Every one of those reads the re-derived artifact. A stale blob produces a perfectly coherent
build of LAST WEEK'S AUDIO, and the whole chain reports green — a reader that refreshes its own
input cannot report that its input was stale. So this check must run BEFORE the import, and it
is the only thing between the fold and the store that looks at the raw bytes.

DESIGN CONSTRAINTS, each earned by a measurement on 2026-09-11
──────────────────────────────────────────────────────────────
  * NAMES FILES, NEVER A COUNT. Four lanes produced four different offender counts off one SHA
    that day; the counts were noise and the LISTS were the signal (two were identical, one a
    strict subset). "3 blobs stale" tells the next person nothing.
  * REPORTS `compared` ALONGSIDE `stale`. `stale=0` is equally satisfied by a comparator that
    never compared — a broken oid extraction sends every file to "no pointer" and still prints
    a clean zero. `compared == corpus` is the completeness half and it is asserted, not printed.
  * THE EXPECTATION IS DERIVED. Not a floor: `.gitattributes` says which patterns are LFS, so a
    repo declaring LFS patterns and finding zero files is a BROKEN DETECTOR, while a repo
    declaring none legitimately has nothing to do. No integer anyone can edit downward.
  * THE REFUSAL NAMES THE DESTROYED-DIAGNOSIS TRAP. @cowir-controller's point: whoever hits this
    will reach for `--import` first, and re-importing makes the layer unknowable — in layer 1
    the green never arrives, so the natural reading becomes "the fix didn't work, so the finding
    must be real." The message has to say that where it is read, not in a runbook.
"""
import hashlib
import os
import re
import subprocess
import sys

POINTER_RE = re.compile(rb'^version https://git-lfs\.github\.com/spec/v1\b.*?'
                        rb'^oid sha256:([a-f0-9]{64})\s*$', re.M | re.S)
TAG = "[lfs]"


class Unusable(Exception):
    pass


def _git(repo, *args, binary=False):
    p = subprocess.run(("git", "-C", repo) + args,
                       capture_output=True, text=not binary)
    return p.returncode, p.stdout


def _declared_patterns(repo):
    """LFS patterns .gitattributes declares. The corpus expectation is derived from THIS."""
    path = os.path.join(repo, ".gitattributes")
    if not os.path.isfile(path):
        return []
    pats = []
    for line in open(path, encoding="utf-8", errors="replace"):
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) > 1 and any(p == "filter=lfs" for p in parts[1:]):
            pats.append(parts[0])
    return pats


def _lfs_files(repo):
    """Paths git itself says are LFS-filtered. Asking git's attribute machinery rather than
    re-implementing .gitattributes matching: the pattern language has precedence rules and
    negations, and a hand-rolled glob would silently disagree with the filter that actually
    ran."""
    ec, out = _git(repo, "ls-files", "-z")
    if ec != 0:
        raise Unusable(f"{TAG} BLOCKED: `git ls-files` failed in {repo} — not a git "
                       f"repository, or git is unavailable. Nothing was examined.")
    names = [n for n in out.split("\0") if n]
    if not names:
        return []
    p = subprocess.run(("git", "-C", repo, "check-attr", "--stdin", "filter"),
                       input="\n".join(names), capture_output=True, text=True)
    if p.returncode != 0:
        raise Unusable(f"{TAG} BLOCKED: `git check-attr` failed in {repo}. The corpus could "
                       f"not be determined, so a clean result would be meaningless.")
    files = []
    for line in p.stdout.splitlines():
        # `check-attr` prints "<path>: filter: <value>"; the path may itself contain ": ".
        if line.endswith(": filter: lfs"):
            files.append(line[:-len(": filter: lfs")])
    return sorted(files)


def _pointer_oid(repo, path):
    """The oid HEAD's blob for `path` claims, or None if that blob is not an LFS pointer."""
    ec, raw = _git(repo, "cat-file", "blob", f"HEAD:{path}", binary=True)
    if ec != 0:
        return None
    m = POINTER_RE.search(raw)
    return m.group(1).decode() if m else None


def _disk_sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _looks_like_pointer(path):
    """The 'LFS never fetched this' shape: the working file IS the pointer text."""
    try:
        with open(path, "rb") as f:
            return POINTER_RE.search(f.read(4096)) is not None
    except OSError:
        return False


def run(repo="."):
    patterns = _declared_patterns(repo)
    corpus = _lfs_files(repo)

    # ── DERIVED EXPECTATION, asserted BEFORE any verdict is printed ──────────────────────
    if patterns and not corpus:
        raise Unusable(
            f"{TAG} BLOCKED: .gitattributes declares LFS pattern(s) {' '.join(patterns)} but git "
            f"reports NO LFS-filtered files.\n"
            f"        Either every LFS file was removed from the repo, or the corpus query "
            f"broke.\n"
            f"        'Nothing is stale' over an empty corpus is not a clean result.")
    if not patterns:
        print(f"{TAG} .gitattributes declares no filter=lfs patterns — no LFS content in this "
              f"repo.")
        print(f"{TAG} corpus 0 · compared 0 · stale 0")
        return 0

    compared, stale, unfetched, nopointer = 0, [], [], []
    for rel in corpus:
        full = os.path.join(repo, rel)
        if not os.path.isfile(full):
            continue          # tracked but not checked out; not this gate's question
        oid = _pointer_oid(repo, rel)
        if oid is None:
            nopointer.append(rel)
            continue
        compared += 1
        if _disk_sha256(full) != oid:
            (unfetched if _looks_like_pointer(full) else stale).append(rel)

    present = sum(1 for rel in corpus if os.path.isfile(os.path.join(repo, rel)))

    # ── COMPLETENESS, withheld-on-failure. `stale == 0` alone cannot distinguish a clean tree
    # from a comparator that never compared: if _pointer_oid stopped matching, every file lands
    # in `nopointer`, the loop still finishes, and the verdict is still zero.
    if nopointer:
        raise Unusable(
            f"{TAG} BLOCKED: {len(nopointer)} of {present} LFS file(s) have no readable pointer "
            f"in HEAD:\n"
            f"        {', '.join(nopointer[:8])}{' …' if len(nopointer) > 8 else ''}\n"
            f"        Either they were committed as raw bytes instead of pointers, or this "
            f"guard's\n"
            f"        pointer parse stopped matching. Both make the comparison vacuous, and a "
            f"green\n"
            f"        below would say 'nothing is stale' when the truth is 'nothing was "
            f"examined'.")
    if compared != present:
        raise Unusable(
            f"{TAG} BLOCKED: examined {compared} file(s) but {present} are present on disk. "
            f"Some\n        went unexamined and this guard cannot say which — refusing rather "
            f"than\n        reporting on the ones it happened to reach.")

    print(f"{TAG} corpus {len(corpus)} declared by {' '.join(patterns)} · "
          f"{present} present on disk · compared {compared}")

    if unfetched or stale:
        # NAMES, not a count — and the ordering advice is in the refusal because that is where
        # it is read.
        print(f"{TAG} BLOCKED: working bytes disagree with the oid HEAD pins.", file=sys.stderr)
        for rel in unfetched:
            print(f"{TAG}   NEVER FETCHED  {rel}  (the file on disk IS the pointer text)",
                  file=sys.stderr)
        for rel in stale:
            print(f"{TAG}   STALE BYTES    {rel}", file=sys.stderr)
        print(f"{TAG}", file=sys.stderr)
        print(f"{TAG}   Run `git lfs pull` (or `git lfs fetch --all && git lfs checkout`).",
              file=sys.stderr)
        print(f"{TAG}   ⛔ DO NOT re-import first. `--import` re-derives every artifact from "
              f"whatever", file=sys.stderr)
        print(f"{TAG}   bytes are on disk, so it will faithfully rebuild the WRONG audio and "
              f"destroy", file=sys.stderr)
        print(f"{TAG}   the evidence of which layer you were in. The green never arrives, and "
              f"the", file=sys.stderr)
        print(f"{TAG}   natural reading of that is 'the fix didn't work, so the finding must be "
              f"real'.", file=sys.stderr)
        print(f"{TAG}   Fix the bytes FIRST, then import.", file=sys.stderr)
        return 1

    print(f"{TAG} stale 0 · every compared file matches the oid HEAD pins")
    return 0


# ── selftest ─────────────────────────────────────────────────────────────────────────────
# Fixtures use `filter.lfs.clean=cat`, so git stores exactly what is written and no git-lfs
# binary is needed: an "LFS repo" is a .gitattributes declaring the pattern plus a committed
# blob that happens to be pointer text. That is structurally what LFS produces, and it means
# these arms test THIS code rather than LFS's.
def _pointer_text(oid, size):
    return (f"version https://git-lfs.github.com/spec/v1\n"
            f"oid sha256:{oid}\nsize {size}\n").encode()


def _mkrepo(d, patterns, files):
    """files: {relpath: (committed_bytes, disk_bytes_or_None)}

    ⛔ THE CONTENT IS COMMITTED BEFORE .gitattributes EXISTS, deliberately. The first version
    wrote .gitattributes first and passed `-c filter.lfs.clean=cat` to `git add`, intending to
    store exactly the given bytes. It did not: git-lfs installs `filter.lfs.process`, which
    TAKES PRECEDENCE over clean/smudge, so the override was ignored and git-lfs really cleaned
    the file — committing a genuine pointer whose oid matched the disk bytes. The arm designed
    to see "no readable pointer" was handed a perfectly clean tree and reported exit 0, which
    looks exactly like the guard failing to refuse. The fixture was the broken party.

    Committing first means no filter is configured for those paths yet, so the blob is byte-
    exact; .gitattributes lands in a second commit and check-attr still reports `filter: lfs`
    from the working tree.
    """
    os.makedirs(d, exist_ok=True)
    subprocess.run(("git", "init", "-q", d), check=True, capture_output=True)
    for k, v in (("user.email", "t@t"), ("user.name", "t"), ("commit.gpgsign", "false")):
        subprocess.run(("git", "-C", d, "config", k, v), check=True, capture_output=True)

    for rel, (committed, _) in files.items():
        full = os.path.join(d, rel)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        open(full, "wb").write(committed)
    subprocess.run(("git", "-C", d, "add", "-A"), check=True, capture_output=True)
    subprocess.run(("git", "-C", d, "commit", "-qm", "content"), check=True, capture_output=True)

    if patterns:
        open(os.path.join(d, ".gitattributes"), "w").write(
            "".join(f"{p} filter=lfs diff=lfs merge=lfs -text\n" for p in patterns))
        subprocess.run(("git", "-C", d, "add", ".gitattributes"), check=True,
                       capture_output=True)
        subprocess.run(("git", "-C", d, "commit", "-qm", "attrs"), check=True,
                       capture_output=True)

    # ASSERT THE FIXTURE LANDED. Without this the miswired version above was indistinguishable
    # from a guard that failed to fire — the defect suppressed its own evidence.
    for rel, (committed, _) in files.items():
        ec, got = _git(d, "cat-file", "blob", f"HEAD:{rel}", binary=True)
        if ec != 0 or got != committed:
            raise AssertionError(
                f"fixture {d}: HEAD:{rel} is not the bytes requested "
                f"({len(got) if ec == 0 else 'missing'} vs {len(committed)}) — a filter "
                f"rewrote it, so this arm would test something other than its subject.")

    for rel, (_, disk) in files.items():           # diverge the working tree AFTER committing
        if disk is not None:
            open(os.path.join(d, rel), "wb").write(disk)
    return d


def selftest():
    import contextlib
    import io
    import tempfile

    passed = failed = 0
    last = {"msg": ""}

    def _said(fragment):
        return fragment in last["msg"]

    # ⛔ `extra` is REQUIRED, not optional. Measured on this lane's sibling harnesses the same
    # day: their only collective control is `{0,1,2} <= saw`, which quantifies over EXIT CODES
    # OBSERVED — so deleting every arm's assertion left them at "37 passed, 0 failed". Requiring
    # a reason check per arm makes a REMOVED assertion loud.
    # ⚠️ KNOWN LIMIT, stated rather than implied: a WEAKENED extra (one that cannot fail) is
    # still invisible here, as it is everywhere. Only a mutation finds that, and the mutations
    # are recorded rather than inferred.
    def arm(name, want, fn, extra):
        nonlocal passed, failed
        if not callable(extra):
            raise AssertionError(
                f"arm {name!r} carries no reason check. An arm asserting a bare exit code is "
                f"satisfied by any of this file's four refusal paths, including a broken "
                f"fixture — which is how a removed assertion goes unnoticed elsewhere in this "
                f"lane. Give it an `extra`, or delete the arm deliberately.")
        last["msg"] = ""
        try:
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
                got = fn()
            last["msg"] = buf.getvalue()
        except Unusable as e:
            got = 2
            last["msg"] = str(e)
        ok, detail = extra()
        if got == want and ok:
            passed += 1
            print(f"  ok    {name:52} exit {got} — {detail}")
        else:
            failed += 1
            why = detail if not ok else f"wanted exit {want}"
            print(f"  FAIL  {name:52} exit {got} — {why}")

    BYTES_A = b"REAL-AUDIO-AAA" * 40
    BYTES_B = b"REAL-AUDIO-BBB" * 40
    OID_A = hashlib.sha256(BYTES_A).hexdigest()
    PTR_A = _pointer_text(OID_A, len(BYTES_A))

    with tempfile.TemporaryDirectory() as td:
        # 1. clean — pointer oid matches the bytes on disk
        clean = _mkrepo(os.path.join(td, "clean"), ["*.ogg"],
                        {"a/x.ogg": (PTR_A, BYTES_A)})
        arm("clean tree — bytes match the oid HEAD pins", 0, lambda: run(clean),
            lambda: (_said("compared 1") and _said("stale 0"),
                     "reports compared 1 alongside stale 0"))

        # 2. stale bytes — the live failure this gate exists for
        stale = _mkrepo(os.path.join(td, "stale"), ["*.ogg"],
                        {"a/x.ogg": (PTR_A, BYTES_B)})
        arm("stale blob — different real bytes on disk", 1, lambda: run(stale),
            lambda: (_said("STALE BYTES") and _said("a/x.ogg"),
                     "NAMES the file, not a count"))

        # 3. never fetched — the working file IS the pointer
        unf = _mkrepo(os.path.join(td, "unfetched"), ["*.ogg"],
                      {"a/x.ogg": (PTR_A, None)})
        arm("never fetched — disk holds the pointer text", 1, lambda: run(unf),
            lambda: (_said("NEVER FETCHED") and _said("a/x.ogg"),
                     "distinguishes never-fetched from stale-bytes"))

        # 4. the refusal must carry the ordering warning where it is READ
        arm("refusal names the destroyed-diagnosis trap", 1, lambda: run(stale),
            lambda: (_said("DO NOT re-import first") and _said("git lfs pull"),
                     "says fix the bytes before importing"))

        # 5. DERIVED EXPECTATION: patterns declared, corpus empty -> the detector broke
        ghost = _mkrepo(os.path.join(td, "ghost"), ["*.ogg"], {"readme.md": (b"hi", None)})
        arm("LFS declared but no LFS files — detector broke", 2, lambda: run(ghost),
            lambda: (_said("NO LFS-filtered files"), "refuses an empty corpus"))

        # 6. no patterns at all is legitimately nothing to do — the OTHER direction, so the
        #    arm above cannot be satisfied by a guard that simply always refuses.
        plain = _mkrepo(os.path.join(td, "plain"), [], {"readme.md": (b"hi", None)})
        arm("no filter=lfs patterns — legitimately clean", 0, lambda: run(plain),
            lambda: (_said("no filter=lfs patterns"), "says why it had nothing to do"))

        # 7. ⛔ THE COMPLETENESS CONTROL. Blob committed as RAW BYTES, so the pointer parse
        #    finds nothing. Pre-check this returned "stale 0" — indistinguishable from clean.
        raw = _mkrepo(os.path.join(td, "raw"), ["*.ogg"], {"a/x.ogg": (BYTES_A, BYTES_A)})
        arm("no readable pointer — vacuous, not clean", 2, lambda: run(raw),
            lambda: (_said("no readable pointer") and _said("nothing was examined"),
                     "refuses rather than reporting stale 0"))

        # 8. not a git repo
        nogit = os.path.join(td, "nogit")
        os.makedirs(nogit)
        arm("not a git repository", 2, lambda: run(nogit),
            lambda: (_said("not a git"), "names the cause"))

    print(f"\nselftest: {passed} passed, {failed} failed")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    args = [a for a in sys.argv[1:]]
    if "--selftest" in args:
        sys.exit(selftest())
    try:
        sys.exit(run(args[0] if args else "."))
    except Unusable as e:
        print(str(e), file=sys.stderr)
        sys.exit(2)
