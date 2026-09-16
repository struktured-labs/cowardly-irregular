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

# A dirty worktree is not the tree you are about to tag. v3.33.362-alpha was tagged with an
# untracked .import sidecar present: the gate ran WITH it, the tag's tree is WITHOUT it, and
# tag_gate_evidence.sh correctly returned VERDICT=RUN — after the tag was already pushed.
# This runs before the tag, which is the only place the check is cheap.
DIRTY=$(git status --porcelain)
if [ -n "$DIRTY" ]; then
    echo "fold_note.sh: REFUSING — the worktree is not clean, so it is not the tree you would tag:" >&2
    printf '%s\n' "$DIRTY" | sed 's/^/  /' >&2
    echo "  (an untracked file here is usually a generated sidecar an --import produced; commit it or remove it)" >&2
    exit 4
fi

MERGES=$(git log --merges --format='%s' "$FROM..$TO" \
  | sed "s/Merge remote-tracking branch //; s/'//g; s|origin/||" | sort)
N=$(printf '%s\n' "$MERGES" | command grep -c . || true)
test "$N" -gt 0 || { echo "no merges in $FROM..$TO — a fold with nothing in it is not a release" >&2; exit 3; }

echo "# branches merged in $FROM..$TO  ($N)"
printf '%s\n' "$MERGES" | sed 's/^/  /'
echo
echo "# every clause in the note must name one of the above."
echo "# ⚠️ BUILD THE TAG MESSAGE WITH A QUOTED HEREDOC. An unquoted <<MSG runs backticks as"
echo "#    command substitution: v3.33.366-alpha lost \`is_action_pressed(...)\` from its note"
echo "#    that way, silently, because the substitution failed and left an empty string."
echo "#      cat > tmp/tagmsg <<'\''EOF'\''   # quoted: backticks stay literal"
echo "#      ...prose...                  EOF"
echo "#      tools/fold_note.sh <from> <to> | sed -n '2,20p' >> tmp/tagmsg"
echo "#      git tag -a <tag> -F tmp/tagmsg"
echo "# verify a claim by CONTENT too, not only by ancestry:"
echo "#   git show $TO:<file> | grep -c <symbol>"
