#!/usr/bin/env python3
"""Self-test for who_guards.py — drives the real tool against a built corpus.

⛔ THE LOAD-BEARING PROPERTY IS THE PROSE, NOT THE HIT COUNT. A version that printed
only paths would satisfy every count check here and would be useless for the failure
this tool exists to prevent: the file was already on screen as a NAME and the reasoning
was not. Arm 3 is the one that has to fail if the tool degrades.
"""
import os
import subprocess
import sys
import tempfile

TOOL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "who_guards.py")
FAILURES = []


def check(name, cond, detail=""):
    if cond:
        print("  ok   %s" % name)
    else:
        print("  FAIL %s %s" % (name, detail))
        FAILURES.append(name)


def run(args, corpus):
    proc = subprocess.run([sys.executable, TOOL] + args + ["--corpus", corpus],
                          capture_output=True, text=True)
    return proc.returncode, proc.stdout, proc.stderr


def main():
    with tempfile.TemporaryDirectory() as tmp:
        corpus = os.path.join(tmp, "test")
        os.makedirs(corpus)
        with open(os.path.join(corpus, "test_alpha.gd"), "w", encoding="utf-8") as fh:
            fh.write("extends GutTest\n\n"
                     "## ALPHA HEADER PROSE, the sentence a reader needs.\n"
                     "## second line of it.\n\n"
                     "const X := 1\n\n"
                     "func test_a():\n\tsm.play_widget(\"k\")\n")
        with open(os.path.join(corpus, "test_beta.gd"), "w", encoding="utf-8") as fh:
            fh.write("extends GutTest\n\nfunc test_b():\n\tpass\n")

        print("who_guards selftest")

        code, out, _ = run(["play_widget"], corpus)
        check("a present symbol exits 0", code == 0, "(got %d)" % code)
        check("it names the file that reaches it", "test_alpha.gd" in out)
        # THE ARM THAT MATTERS: the reason this tool exists is that a NAME is not enough.
        check("it prints the file's HEADER PROSE, not just the path",
              "ALPHA HEADER PROSE" in out, "<-- a path-only tool passes every other arm")
        check("it does not name a file that lacks the symbol", "test_beta.gd" not in out)

        code, out, _ = run(["zz_no_such_symbol_anywhere"], corpus)
        check("a zero-hit search still exits 0", code == 0, "(got %d)" % code)
        check("and SAYS the corpus was searched", "NO PRIOR GUARD" in out,
              "<-- a silent null is indistinguishable from a failed run")

        code, _, err = run(["play_widget"], os.path.join(tmp, "does_not_exist"))
        check("an absent corpus exits 3, not 0", code == 3, "(got %d)" % code)
        check("and says nothing was searched", "nothing was searched" in err)

        # ⚠️ A DEDICATED EMPTY DIR. My first version passed `tmp` itself, which CONTAINS the
        # corpus — os.walk descends, found both files and correctly exited 0. The arm was wrong,
        # not the tool, and it would have read as a tool defect.
        empty = os.path.join(tmp, "empty_corpus")
        os.makedirs(empty)
        code, out, _ = run(["play_widget"], empty)
        check("a corpus with no .gd files exits 3", code == 3, "(got %d)" % code)

    print()
    if FAILURES:
        print("FAILED: %d arm(s): %s" % (len(FAILURES), FAILURES))
        return 1
    print("all arms passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
