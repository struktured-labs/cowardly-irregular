#!/usr/bin/env bash
# fold_safety.sh <branch> — does folding this branch DESTROY work that is on main?
#
# The fleet's branch ladder (2026-07-29) has three rungs and they all ask the same question:
#
#   rung 1  merge-base --is-ancestor   is the branch's tip reachable from main?
#   rung 2  git cherry (patch-id)      has the branch's diff landed on main?
#   rung 3  content / symbol check     is the branch's content on main?
#
# All three protect against DISCARDING work by dropping a branch. None protects against
# DESTROYING work by folding one. A branch held open for a good reason — waiting on a decision,
# waiting on another lane's ids — keeps accumulating main's changes that it does not have, and
# its copy of a shared file is a snapshot of the day it was cut.
#
# Absence has no patch-id, no symbol to grep, and no diff line. Every instrument built for the
# other three rungs searches for something PRESENT.
#
# Measured instances, both found within an hour of the class being named:
#   feature/sprite-raw-intermediate-purge  its sprite_manifest predates tonight's tier fix —
#       a file-level fold relabels four ARTIST starter sheets back to T1 ("safe to regenerate")
#       and de-registers four W3 masterites.
#   feature/cowardly-irregular-music       its CutsceneDirector lacks keep_music — a file-level
#       fold deletes another lane's feature, silently.
#
# A three-way merge is safe in both cases: the branch never modified those lines, so git keeps
# main's. The danger is every operation that SUBSTITUTES a file instead of merging it — squash,
# `git checkout <branch> -- <file>`, or resolving a conflict by taking "theirs".
#
# Exit 0 = safe to fold. Exit 1 = main has content this branch lacks; read before folding.

set -uo pipefail
BRANCH="${1:-}"
if [ -z "$BRANCH" ]; then
	echo "usage: tools/fold_safety.sh <branch-ref>   e.g. origin/feature/foo" >&2
	exit 2
fi
git rev-parse --verify "$BRANCH" >/dev/null 2>&1 || { echo "no such ref: $BRANCH" >&2; exit 2; }

BASE=$(git merge-base HEAD "$BRANCH")
# Files the branch touches — the only ones a file-level fold could substitute.
FILES=$(git diff --name-only "$BASE" "$BRANCH")
if [ -z "$FILES" ]; then
	echo "SAFE: branch touches no files relative to the merge base"
	exit 0
fi

HAZARD=0
TOTAL=0
while IFS= read -r f; do
	[ -z "$f" ] && continue
	# Skip binaries: a byte difference proves nothing once either side has been re-encoded,
	# and there is no line-level notion of "main has this and the branch does not".
	if ! git show "HEAD:$f" >/dev/null 2>&1; then continue; fi
	if git diff --numstat HEAD "$BRANCH" -- "$f" | grep -q '^-'; then continue; fi
	TOTAL=$((TOTAL + 1))
	# Lines main HAS that the branch LACKS. Direction matters: diff BRANCH -> HEAD, additions.
	LOST=$(git diff "$BRANCH" HEAD -- "$f" | grep '^+' | grep -v '^+++' | sed 's/^+//' \
		| grep -vE '^\s*$' | grep -vE '^\s*(#|##|//)' || true)
	N=$(printf '%s' "$LOST" | grep -c . || true)
	if [ "${N:-0}" -gt 0 ]; then
		HAZARD=$((HAZARD + 1))
		echo "  ⚠ $f — main has $N line(s) this branch lacks:"
		printf '%s\n' "$LOST" | head -4 | sed 's/^/      /'
		[ "$N" -gt 4 ] && echo "      … $((N - 4)) more"
	fi
done <<< "$FILES"

echo "checked $TOTAL text file(s) the branch touches; $HAZARD carry main-only content"
if [ "$HAZARD" -gt 0 ]; then
	cat <<'AMBIG'
STALE IN A MOVED FILE — and the COUNT ALONE CANNOT TELL YOU WHICH KIND.

  main has the FIX, branch lacks it   -> folding REGRESSES        (danger)
  main has the BUG, branch deletes it -> folding IS THE POINT     (fine)

Those produce an identical number. cowir-story and cowir-sprites both hit the
false-positive direction within an hour of this check existing, so read the
lines above, do not count them. The discriminator that worked (cowir-sprites):

  is the absent content INSIDE the branch's subject matter, or INCIDENTAL to it?
    inside      the branch holds the newer thinking on those lines — fold it
    incidental  stale collateral the branch dragged along — danger

  worked examples: _test_disable_persistence in a branch about session history,
  and four artist tiers in a branch about three Calibrant faces. Both incidental,
  both real. A branch's own subject matter is almost always the newer version.

DISPOSITION (cowir-controller) — the ambiguity only has to be resolved for a
branch you intend to DROP. If you intend to FOLD it, REBASE onto main and
re-gate: git replays only the branch's changes onto main's current content, so
the absence stops existing and nothing has to be adjudicated.
AMBIG
	exit 1
fi
echo "SAFE TO FOLD"
exit 0
