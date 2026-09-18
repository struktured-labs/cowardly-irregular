#!/usr/bin/env python3
"""Who already guards this symbol? — the pre-flight before writing a new guard.

Three times on 2026-09-18 this lane re-derived work it had already done and written
down, at about an hour each; the third SHIPPED. Every one would have been caught by
"grep test/ for the symbol before building a guard about it" — a habit written into
memory twice and not run either time. This makes it one command whose OUTPUT IS THE
THING YOU NEED TO READ rather than a list of paths that gets skipped.

    tools/who_guards.py play_ambient
    tools/who_guards.py _sfx_manifest volume_db --lines 6

⛔ It prints each test file's HEADER, not its name. The third instance shipped because
the file was already inside a 32-file regression corpus that had just been run and
reported as "163 passing" — the name was on screen and the prose was not. A corpus
assembled by pattern is also the list of everyone who has already worked your subject.

Exit: 0 ran · 2 bad invocation · 3 corpus absent (nothing could have been searched).
A zero-hit run exits 0 and SAYS SO — a null and a failed run must not look alike.
"""
import argparse
import os
import re
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
    ap.add_argument("symbols", nargs="+", help="symbol or substring, e.g. play_ambient")
    ap.add_argument("--corpus", default=CORPUS_DEFAULT, help="directory to search (default: test)")
    ap.add_argument("--lines", type=int, default=4, help="header lines to print per file (default: 4)")
    args = ap.parse_args()

    if not os.path.isdir(args.corpus):
        print("who_guards: corpus '%s' is not a directory — nothing was searched" % args.corpus, file=sys.stderr)
        return 3

    files = gd_files(args.corpus)
    if not files:
        print("who_guards: corpus '%s' holds no .gd files — nothing was searched" % args.corpus, file=sys.stderr)
        return 3

    for symbol in args.symbols:
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
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
