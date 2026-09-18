#!/usr/bin/env python3
"""Who already guards this symbol? — the pre-flight before writing a new guard.

Three times on 2026-09-18 this lane re-derived work it had already done and written
down, at about an hour each; the third SHIPPED. Every one would have been caught by
"grep test/ for the symbol before building a guard about it" — a habit written into
memory twice and not run either time. This makes it one command whose OUTPUT IS THE
THING YOU NEED TO READ rather than a list of paths that gets skipped.

    tools/who_guards.py play_ambient
    tools/who_guards.py _sfx_manifest volume_db --lines 6
    tools/who_guards.py --new          # derive the subject from test files git has not seen

⛔ It prints each test file's HEADER, not its name. The third instance shipped because
the file was already inside a 32-file regression corpus that had just been run and
reported as "163 passing" — the name was on screen and the prose was not. A corpus
assembled by pattern is also the list of everyone who has already worked your subject.

⚠️ AND THE HEADER IS THE FILE'S SUBJECT, WHICH IS NOT ALWAYS WHY IT MATCHED. Measured
2026-09-18 against another lane's case: searching "TRUNCATES" surfaces
test_remap_capture_names_the_escape_button_regression, whose header is about a capture
overlay naming the wrong button — while the truncate-on-open reasoning sits inside
_restore_input_config, a function body. A reader skimming that header dismisses the file.
So the MATCHED LINE is printed too. Subject and match coincide for a symbol search and
diverge for a mechanism search, which is the search you run when you do not yet know
which symbol owns the idea.

⚠️ WHAT THIS DOES NOT FIX, stated because the limit is real (cowir-controller, 2026-09-18):
it still has to be REMEMBERED, which is the property it was built to escape. Their own
re-derivation was not a bad search — they never searched, because you cannot query for
the existence of a thing you have not conceived of. `--new` is the most this tool can do
about that on its own: it removes the need to DECIDE what to search for, so the remembered
action costs one word. The trigger itself — "I am about to author a guard" — is free only
if something else fires it, and nothing here does.

Exit: 0 ran · 2 bad invocation · 3 corpus absent (nothing could have been searched).
A zero-hit run exits 0 and SAYS SO — a null and a failed run must not look alike.
"""
import argparse
import os
import re
import subprocess
import sys

CORPUS_DEFAULT = "test"
HEADER_LINE = re.compile(r"^\s*#")
CODE_LINE = re.compile(r"^\s*(extends|class_name|const|var|func|@)")


def header_of(path, max_lines):
    """The file's own prose: comment lines above the first real declaration."""
    out = []
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                stripped = line.rstrip("\n")
                if HEADER_LINE.match(stripped):
                    text = stripped.lstrip().lstrip("#").strip()
                    if text:
                        out.append(text)
                        if len(out) >= max_lines:
                            break
                elif CODE_LINE.match(stripped):
                    # `extends GutTest` sits above the header; keep looking past it.
                    if stripped.strip().startswith("extends") and not out:
                        continue
                    if out:
                        break
    except OSError as exc:
        return ["<unreadable: %s>" % exc]
    return out


def matching_lines(path, symbol, limit):
    """Why this file matched — the header is its SUBJECT and need not be the same thing."""
    out = []
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for num, line in enumerate(fh, 1):
                if symbol in line:
                    out.append((num, line.strip()))
                    if len(out) >= limit:
                        break
    except OSError:
        pass
    return out


def new_test_files():
    """Test files git has not seen — untracked or newly added. The moment you are authoring one
    is the moment prior art matters, and it is the only self-announcing step in the workflow."""
    try:
        proc = subprocess.run(["git", "status", "--porcelain", "--", "test"],
                              capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return None
    if proc.returncode != 0:
        return None
    out = []
    for line in proc.stdout.splitlines():
        status, _, path = line.partition(" ")
        path = line[3:].strip()
        if not path.endswith(".gd"):
            continue
        if line[:2].strip() in ("??", "A", "AM"):
            out.append(path)
    return sorted(set(out))


def symbols_from(paths):
    """The receivers a new guard reaches — what to look up prior art FOR, so the caller does not
    have to decide. Deliberately narrow: `sm.<name>(` and `<Autoload>.<name>(` shapes only."""
    found = {}
    call = re.compile(r"\b[A-Za-z_][A-Za-z_0-9]*\.([a-z_][a-z_0-9]*)\(")
    for path in paths:
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                body = fh.read()
        except OSError:
            continue
        for name in call.findall(body):
            if len(name) > 4 and not name.startswith("assert"):
                found[name] = found.get(name, 0) + 1
    # Most-reached first: the subject a new guard drives hardest is the one to check.
    return [n for n, _c in sorted(found.items(), key=lambda kv: -kv[1])]


def gd_files(root):
    found = []
    for dirpath, _dirnames, filenames in os.walk(root):
        for name in filenames:
            if name.endswith(".gd"):
                found.append(os.path.join(dirpath, name))
    # bfs/os.walk order is not guaranteed stable across runs; sort so two runs of this
    # tool on one tree are diffable.
    return sorted(found)


def main():
    ap = argparse.ArgumentParser(description="Show the test files that already reach a symbol, with their headers.")
    ap.add_argument("symbols", nargs="*", help="symbol or substring, e.g. play_ambient")
    ap.add_argument("--new", action="store_true",
                    help="derive symbols from test files git has not seen yet")
    ap.add_argument("--top", type=int, default=5, help="with --new, how many symbols to check")
    ap.add_argument("--corpus", default=CORPUS_DEFAULT, help="directory to search (default: test)")
    ap.add_argument("--lines", type=int, default=4, help="header lines to print per file (default: 4)")
    ap.add_argument("--hits", type=int, default=2, help="matched lines to print per file (default: 2)")
    args = ap.parse_args()

    symbols = list(args.symbols)
    if args.new:
        fresh = new_test_files()
        if fresh is None:
            print("who_guards: --new needs a working git repo; none answered", file=sys.stderr)
            return 2
        if not fresh:
            print("who_guards: no new or untracked .gd under test/ — nothing to derive a subject from")
            return 0
        print("new test file(s) git has not seen: %s" % ", ".join(fresh))
        derived = symbols_from(fresh)[:args.top]
        if not derived:
            print("who_guards: those files reach no `<receiver>.<method>(` calls — pass a symbol yourself", file=sys.stderr)
            return 2
        print("deriving prior-art lookups for: %s\n" % ", ".join(derived))
        symbols += derived
    if not symbols:
        print("who_guards: give a symbol, or --new to derive one", file=sys.stderr)
        return 2

    if not os.path.isdir(args.corpus):
        print("who_guards: corpus '%s' is not a directory — nothing was searched" % args.corpus, file=sys.stderr)
        return 3

    files = gd_files(args.corpus)
    if not files:
        print("who_guards: corpus '%s' holds no .gd files — nothing was searched" % args.corpus, file=sys.stderr)
        return 3

    for symbol in symbols:
        hits = []
        for path in files:
            try:
                with open(path, encoding="utf-8", errors="replace") as fh:
                    if symbol in fh.read():
                        hits.append(path)
            except OSError:
                continue
        print("=" * 72)
        print("%s — %d of %d file(s) in %s/ already reach it" % (symbol, len(hits), len(files), args.corpus))
        print("=" * 72)
        if not hits:
            # Said explicitly: a null is an answer, and must not read like a failed run.
            print("  NO PRIOR GUARD. The corpus was searched and holds nothing naming this.\n")
            continue
        for path in hits:
            print("\n  %s" % path)
            head = header_of(path, args.lines)
            if not head:
                print("      (no header prose — open it)")
            for line in head:
                print("      %s" % line)
            for num, text in matching_lines(path, symbol, args.hits):
                print("      :%-5d %s" % (num, text[:110]))
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
