#!/usr/bin/env bash
# Answer "is my work actually in this tree?" so that a ZERO is always readable.
#
# The hand-rolled form every lane reached for on 2026-09-11 was:
#
#     git show <ref>:<path> | grep -c SYMBOL
#
# On a MISSING path that yields an empty stream and scores 0 — identical to "file is there, symbol
# isn't". Five lanes used it that day and all five were safe BY OUTCOME: every count came back
# non-zero, and a non-zero count can only come from a file that was really read. Nobody was safe by
# construction. The hazard is worst in the failure case, which is the only case you run this for:
# a 0 is exactly what "my work is missing from the release" looks like AND exactly what "I typo'd
# the path" looks like, and you meet that ambiguity while hoping for one of the two answers.
#
# So the existence probe is not advice here, it is step one and it always runs. A positive result
# never needed it; by the time you do, you are the least able to remember.
#
# Usage:  tools/verify_symbols_in_tree.sh <ref> <path> <symbol> [<symbol>...]
# Exit:   0 every symbol found · 1 a symbol was absent · 2 the path or ref does not exist
#         3 the reader is broken (the built-in negative control matched)
set -uo pipefail

if [ $# -lt 3 ]; then
	echo "usage: $0 <ref> <path-in-tree> <symbol> [<symbol>...]" >&2
	exit 2
fi

REF="$1"; PATH_IN_TREE="$2"; shift 2

COMMIT=$(git rev-parse --verify --quiet "${REF}^{commit}") || {
	echo "REF DOES NOT RESOLVE: $REF — nothing was measured" >&2
	exit 2
}

# STEP ONE, UNCONDITIONALLY. Without this, every count below is uninterpretable at exactly the
# moment it matters. `git show` on a missing path exits non-zero but prints nothing to stdout, so a
# caller that only reads stdout sees a clean empty file.
if ! git cat-file -e "${COMMIT}:${PATH_IN_TREE}" 2>/dev/null; then
	echo "PATH ABSENT from ${REF} (${COMMIT:0:8}): ${PATH_IN_TREE}"
	echo "  -> a count of 0 here would have meant 'no such file', NOT 'symbol missing'"
	exit 2
fi

# A real file, never a pipe or a process substitution: this box's grep skips FIFOs and treats a
# NUL-bearing file as binary. -a on every read for the same reason.
WORK=$(mktemp "${TMPDIR:-/tmp}/verify_symbols.XXXXXX")
trap 'rm -f "$WORK"' EXIT
git show "${COMMIT}:${PATH_IN_TREE}" > "$WORK"

echo "tree ${REF} (${COMMIT:0:8})  path ${PATH_IN_TREE}  $(wc -c < "$WORK") bytes"

# NEGATIVE CONTROL, built in so it cannot be skipped. If a fabricated symbol matches, the reader is
# answering something other than the question and every count below is worthless.
CONTROL="zzz_verify_symbols_control_$$_zzz"
if command grep -c -aF "$CONTROL" "$WORK" 2>/dev/null | command grep -qv '^0$'; then
	echo "READER BROKEN: a fabricated symbol matched — counts below mean nothing" >&2
	exit 3
fi

MISSING=0
for sym in "$@"; do
	n=$(command grep -c -aF -- "$sym" "$WORK" || true)
	[ -z "$n" ] && n=0
	if [ "$n" -eq 0 ]; then
		printf '  ABSENT  x%-4s %s\n' "$n" "$sym"
		MISSING=$((MISSING + 1))
	else
		printf '  present x%-4s %s\n' "$n" "$sym"
	fi
done

if [ "$MISSING" -gt 0 ]; then
	echo "VERDICT: $MISSING of $# symbol(s) ABSENT from ${REF} — the file is present, the content is not"
	exit 1
fi
echo "VERDICT: all $# symbol(s) present in ${REF}"
