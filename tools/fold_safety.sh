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

# The ref being folded INTO. This was HEAD, which made the entire check vacuous
# whenever you ran it on the branch you had checked out: merge-base HEAD <branch>
# is then the branch tip itself, FILES comes back empty, and it printed SAFE having
# compared nothing. That is the highest-traffic case — you check your own branch
# right before asking for a fold. Explicit ref, overridable as $2.
MAIN="${2:-origin/main}"
git rev-parse --verify "$MAIN" >/dev/null 2>&1 || { echo "no such ref: $MAIN" >&2; exit 2; }

BASE=$(git merge-base "$MAIN" "$BRANCH")
# Files the branch touches — the only ones a file-level fold could substitute.
FILES=$(git diff --name-only "$BASE" "$BRANCH")
if [ -z "$FILES" ]; then
	# FLOOR. "Found nothing to check" and "checked everything, found nothing" print the
	# same word; only the second is an answer. A branch fully contained in MAIN really
	# has nothing to substitute — anything else means the base is wrong.
	if git merge-base --is-ancestor "$BRANCH" "$MAIN" 2>/dev/null; then
		echo "SAFE: $BRANCH is fully contained in $MAIN — nothing to substitute"
		exit 0
	fi
	echo "REFUSING TO ANSWER: no files against base ${BASE:0:8}, yet $BRANCH is not" >&2
	echo "contained in $MAIN. The base is wrong, so SAFE here would be vacuous." >&2
	exit 2
fi

HAZARD=0
TOTAL=0
while IFS= read -r f; do
	[ -z "$f" ] && continue
	# Skip binaries: a byte difference proves nothing once either side has been re-encoded,
	# and there is no line-level notion of "main has this and the branch does not".
	if ! git show "$MAIN:$f" >/dev/null 2>&1; then continue; fi
	if git diff --numstat "$MAIN" "$BRANCH" -- "$f" | grep -q '^-'; then continue; fi
	# STALENESS GATE. "main has a line this branch lacks" is ALSO what every ordinary
	# edit looks like: the branch replaced the line, so main's old version reads as
	# missing. Without this, the tool flags nearly every branch and becomes noise.
	#
	# The decidable difference is WHO MOVED LAST. If main has commits touching this
	# file since the merge base, the branch's copy predates them and a substitution
	# drops main's work. If main has not touched it, the only differences are the
	# branch's own deliberate edits. This is also why rebasing dissolves the question
	# (cowir-controller, msg 3442): afterwards the count is 0 by construction.
	MOVED=$(git rev-list --count "$BASE..$MAIN" -- "$f")
	if [ "${MOVED:-0}" -eq 0 ]; then continue; fi
	TOTAL=$((TOTAL + 1))
	# Lines main HAS that the branch LACKS. Direction matters: diff BRANCH -> MAIN, additions.
	LOST=$(git diff "$BRANCH" "$MAIN" -- "$f" | grep '^+' | grep -v '^+++' | sed 's/^+//' \
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
