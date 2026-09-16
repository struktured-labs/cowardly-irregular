#!/usr/bin/env bash
# Print the branches a fold actually merged, read from the tree rather than from memory.
# A release note written from lanes' announcements describes the queue you INTENDED;
# after a rebuild (a killed gate, a held branch) the two disagree and nothing checks prose
# against a tree. v3.33.358-alpha shipped three clauses for branches it did not contain.
#   usage: tools/fold_note.sh <from-ref> [<to-ref>]
set -uo pipefail
FROM="${1:?usage: fold_note.sh <from-ref> [<to-ref>]}"
TO="${2:-HEAD}"
git rev-parse --verify -q "$FROM" >/dev/null || { echo "no such ref: $FROM" >&2; exit 2; }
git rev-parse --verify -q "$TO"   >/dev/null || { echo "no such ref: $TO"   >&2; exit 2; }

MERGES=$(git log --merges --format='%s' "$FROM..$TO" \
  | sed "s/Merge remote-tracking branch //; s/'//g; s|origin/||" | sort)
N=$(printf '%s\n' "$MERGES" | command grep -c . || true)
test "$N" -gt 0 || { echo "no merges in $FROM..$TO — a fold with nothing in it is not a release" >&2; exit 3; }

echo "# branches merged in $FROM..$TO  ($N)"
printf '%s\n' "$MERGES" | sed 's/^/  /'
echo
echo "# every clause in the note must name one of the above."
echo "# verify a claim by CONTENT too, not only by ancestry:"
echo "#   git show $TO:<file> | grep -c <symbol>"
