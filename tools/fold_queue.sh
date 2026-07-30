#!/usr/bin/env bash
# fold_queue.sh — which remote branches are actually foldable, and which are traps.
#
# My hand-rolled queue derivation was wrong FOUR ways in one evening (2026-07-29), each time
# reported by the lane whose branch I missed. Every failure was the same shape: the query answered
# a narrower question than "what should I fold."
#
#   1  "ahead of main, touched in 24h"   missed a branch already folded once at an OLDER tip —
#                                        my filter read it as done (cowir-sprites)
#   2  same filter                       missed two branches pushed AFTER my snapshot; I published
#                                        a snapshot as a standing fact (cowir-ai, cowir-sprites)
#   3  patch-id alone                    lists 67 unlanded patches on a branch whose fold REVERTS
#                                        84 asset files, 3085 behind main (cowir-sprites)
#   4  ancestry alone                    a rebased/orphaned tip is non-ancestral while its content
#                                        IS on main — the inverse of the orphaned-SHA trap, and
#                                        both directions appeared in this repo the same night
#
# So: patch-id for UNLANDED (rebase-aware, date-blind), behind-count + file overlap for REVERT RISK,
# and a content check is still required on any verdict you act on. This script narrows the list; it
# does not replace reading the diff.
set -uo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
MAIN="${1:-origin/main}"
RECENT_HOURS="${2:-0}"   # 0 = all branches; e.g. 6 = only those touched in the last 6h

git fetch -q origin 2>/dev/null || true
git rev-parse --verify "$MAIN" >/dev/null 2>&1 || { echo "no such ref: $MAIN" >&2; exit 2; }

NOW=$(git log -1 --format='%ct' "$MAIN")
FOLDABLE=0; REVERT=0; SKIPPED=0

printf "%-46s %6s %8s %7s  %s\n" "BRANCH" "AHEAD" "BEHIND" "OVERLAP" "VERDICT"
for b in $(git for-each-ref --format='%(refname:short)' refs/remotes/origin \
		| grep -v "^${MAIN#origin/}\$" | grep -v 'origin/main$\|origin/HEAD'); do
	# UNLANDED via patch-id. Catches content that landed by cherry-pick or rebase, which
	# ancestry cannot, and is blind to dates, which is how two pushes slipped past me.
	AHEAD=$(git cherry "$MAIN" "$b" 2>/dev/null | grep -c '^+')
	[ "${AHEAD:-0}" -eq 0 ] && continue

	if [ "$RECENT_HOURS" -gt 0 ]; then
		T=$(git log -1 --format='%ct' "$b" 2>/dev/null)
		[ $(( (NOW - T) / 3600 )) -gt "$RECENT_HOURS" ] && { SKIPPED=$((SKIPPED+1)); continue; }
	fi

	BASE=$(git merge-base "$MAIN" "$b")
	BEHIND=$(git rev-list --count "$BASE..$MAIN")
	# REVERT RISK: files the branch changed that MAIN has ALSO moved since the base. On a badly
	# behind branch every such file shows as a deletion in the diff, so "the merge kept main's
	# side" has to be checked per-file rather than once (cowir-sprites' generalisation of the
	# audit_artist_currency.py near-miss).
	OVERLAP=0
	while IFS= read -r f; do
		[ -z "$f" ] && continue
		N=$(git rev-list --count "$BASE..$MAIN" -- "$f" 2>/dev/null)
		[ "${N:-0}" -gt 0 ] && OVERLAP=$((OVERLAP+1))
	done < <(git diff --name-only "$BASE" "$b" 2>/dev/null)

	if [ "$OVERLAP" -gt 0 ]; then
		V="⚠ REVERT RISK — $OVERLAP file(s) main moved too; read the diff"
		REVERT=$((REVERT+1))
	else
		V="foldable (still read it)"
		FOLDABLE=$((FOLDABLE+1))
	fi
	printf "%-46s %6s %8s %7s  %s\n" "${b#origin/}" "$AHEAD" "$BEHIND" "$OVERLAP" "$V"
done

echo
echo "foldable $FOLDABLE · revert-risk $REVERT · skipped-by-age $SKIPPED"
# CONTROL. A derivation that silently enumerated nothing looks exactly like an empty queue, which
# is the claim I got wrong twice. Prove the walk resolves.
REFS=$(git for-each-ref --format='%(refname:short)' refs/remotes/origin | wc -l)
echo "control: walked $REFS remote ref(s); main vs itself unlanded = $(git cherry "$MAIN" "$MAIN" 2>/dev/null | grep -c '^+') (want 0)"
[ "$REFS" -lt 2 ] && { echo "REFUSING: only $REFS remote refs visible — the walk did not resolve" >&2; exit 2; }
exit 0
