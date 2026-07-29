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

# PRECONDITION (cowir-sfx, msg 3458). A branch whose commits have all landed has no
# fold question left — and worse, the staleness gate below counts THE FOLD ITSELF as
# main moving the file, so a just-folded branch reads as a hazard against its own
# content. That is the mechanism behind fold_safety returning exit 1 on four correct
# folds. Ask "is there anything to fold" before "is folding it dangerous".
if [ -z "$(git cherry "$MAIN" "$BRANCH" 2>/dev/null | grep '^+')" ]; then
	echo "MOOT: every commit on $BRANCH has landed on $MAIN — nothing left to fold"
	exit 0
fi

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
# WHY-ZERO ACCOUNTING. The FILES floor above catches "the branch touches nothing". It does not
# catch the commoner shape: the branch touches files, every one is skipped below, and TOTAL
# prints 0 — identical output to an enumeration that silently failed. A count of zero is only an
# answer when it comes with the reason it is zero, so each skip is attributed.
SKIP_ABSENT=0
SKIP_DELETES=0
SKIP_UNMOVED=0
SEEN=0
while IFS= read -r f; do
	[ -z "$f" ] && continue
	SEEN=$((SEEN + 1))
	# Skip binaries: a byte difference proves nothing once either side has been re-encoded,
	# and there is no line-level notion of "main has this and the branch does not".
	if ! git show "$MAIN:$f" >/dev/null 2>&1; then SKIP_ABSENT=$((SKIP_ABSENT + 1)); continue; fi
	if git diff --numstat "$MAIN" "$BRANCH" -- "$f" | grep -q '^-'; then
		SKIP_DELETES=$((SKIP_DELETES + 1)); continue
	fi
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
	if [ "${MOVED:-0}" -eq 0 ]; then SKIP_UNMOVED=$((SKIP_UNMOVED + 1)); continue; fi
	TOTAL=$((TOTAL + 1))
	# STRUCTURED DATA: compare PARSED objects, not lines. A line diff is true of how the file is
	# WRITTEN; the parse is true of the thing (cowir-sfx's rule). cowir-battle hit the failure —
	# 15 "missing" lines on monsters.json were pure em-dash re-escaping. Falls back to the line
	# diff if either side does not parse.
	case "$f" in
	*.json)
		if PARSED=$(python3 "$(dirname "$0")/_fold_json_diff.py" "$BRANCH" "$MAIN" "$f" 2>/dev/null); then
			N=$(printf '%s' "$PARSED" | head -1)
			if [ "${N:-0}" -gt 0 ]; then
				HAZARD=$((HAZARD + 1))
				echo "  ⚠ $f — main has $N parsed key(s) this branch lacks or differs on:"
				printf '%s\n' "$PARSED" | tail -n +2
			fi
			continue
		fi
		;;
	esac
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

# TEST DELETION (@cowir-cutscenes msg-3555). gate.sh proves scripts-run == test files on disk,
# which certifies every test file PRESENT. A branch that DELETES one drops both counts in step,
# so the gate still reads clean while the coverage is simply gone — and a fold is exactly where
# that enters the trunk. Whole-corpus comparison, not per-touched-file: a branch can delete a
# test without the diff naming it as "touched" in the sense the loop above uses.
# Deleting a test is a legitimate act, so this REPORTS and does not refuse.
#
# NOT `comm` (@cowir-ai msg-3557 found it, my control reproduced it): comm -23 <(main) /dev/null
# returned 974 against a 1134-file corpus, SILENTLY — nothing on stderr, in either collation. It
# is the one tool here that mis-answers rather than errors on input it dislikes. grep -Fxv -f
# passes both controls: minus-empty == 1134, minus-itself == 0.
_tests_in() { git ls-tree -r --name-only "$1" -- test/unit | grep '^test/unit/test_.*\.gd$'; }
DELETED_TESTS=$(_tests_in "$MAIN" | grep -Fxv -f <(_tests_in "$BRANCH") || true)
if [ -n "$DELETED_TESTS" ]; then
	echo "NOTE — this branch removes $(printf '%s\n' "$DELETED_TESTS" | grep -c .) test file(s) $MAIN has:"
	printf '%s\n' "$DELETED_TESTS" | head -5 | sed 's/^/    /'
	echo "  gate.sh cannot see this: scripts-run and files-on-disk both drop, so it still reads clean."
fi

MAIN_AHEAD=$(git rev-list --count "$BASE..$MAIN")
echo "branch touches $SEEN file(s); $MAIN has moved $MAIN_AHEAD commit(s) since the base"
echo "  compared $TOTAL · skipped $SKIP_UNMOVED (main never moved them) $SKIP_ABSENT (not on $MAIN) $SKIP_DELETES (branch deletes)"
if [ "$TOTAL" -eq 0 ] && [ "$SEEN" -gt 0 ]; then
	echo "  zero compared is the ANSWER here, not a silence: every file the branch touches is one"
	echo "  $MAIN has not modified since the base, so a substitution could not drop anything."
fi
echo "$HAZARD file(s) carry main-only content"
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
