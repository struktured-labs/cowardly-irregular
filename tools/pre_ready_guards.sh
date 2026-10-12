#!/usr/bin/env bash
# pre_ready_guards.sh — run every guard your branch can RED but your own corpus cannot contain.
#
# TWO derivations, unioned, because they miss opposite things:
#   TEST-TREE guards  — judge the test files themselves, so a branch that ADDS a test file is in
#                       their corpus the moment it lands and has no symbol to grep for (the first
#                       .654 gate red on exactly that, 2026-10-12).
#   PER-FILE guards   — read a src/data/assets file as TEXT and pin lines inside it, so editing
#                       that file can red them from anywhere in it. 347 test files name
#                       src/battle/BattleManager.gd; a lane greping its own symbols sees none of
#                       them, and an inserted line above a pinned call reds one (measured, .655).
# Both sets are DERIVED, never listed: four lanes hand-curated four different lists in one hour.
# Exit codes are run_tests.sh's own, plus 2 when a derivation could not run or matched implausibly
# little — a selector that silently returns nothing looks exactly like a clean sweep.
set -uo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
MIN_GUARDS=10
BASE="${PRE_READY_BASE:-origin/main}"

mapfile -t TREE < <(grep -rlE 'res://test/unit"|res://test/unit/"|res://test"|dir_contents|get_files\(\)' \
  test/unit --include='test_*.gd' | xargs -r grep -lE '"res://test' | sort)

if [ "${#TREE[@]}" -lt "$MIN_GUARDS" ]; then
  echo "pre_ready_guards: derived ${#TREE[@]} test-tree guard(s), expected at least $MIN_GUARDS — the scan matched too little, refusing to call that a pass" >&2
  exit 2
fi

# Which files this branch touched: COMMITTED (since the merge base) plus anything still UNCOMMITTED.
# Both halves are load-bearing — you run this BEFORE committing, so a committed-only derivation
# reports "0 touched files" on the very edit you are checking, and that reads exactly like a clean
# sweep. Measured while building this: a planted insertion in src/battle/BattleManager.gd went
# undetected for that reason. A FAILED diff refuses rather than deriving nothing.
if ! COMMITTED=$(git diff --name-only "$BASE...HEAD" 2>&1); then
  echo "pre_ready_guards: git diff --name-only $BASE...HEAD failed, so the per-file set cannot be derived: $COMMITTED" >&2
  echo "pre_ready_guards: fetch the base or set PRE_READY_BASE=<ref>; refusing to report a pass from one derivation" >&2
  exit 2
fi
if ! WORKING=$(git diff --name-only HEAD 2>&1); then
  echo "pre_ready_guards: git diff --name-only HEAD failed, so uncommitted edits cannot be seen: $WORKING" >&2
  exit 2
fi
mapfile -t TOUCHED < <(printf '%s\n%s\n' "$COMMITTED" "$WORKING" | grep -E '^(src|data|assets)/' | sort -u)

PERFILE=()
for f in ${TOUCHED[@]+"${TOUCHED[@]}"}; do
  # -F and the FULL path on purpose: 'src/battle/' matches ~2,200 files through unrelated preloads,
  # and the shared gd_source helper another 310. Neither is a corpus. Naming the file gives 347.
  mapfile -t hits < <(grep -rlF "$f" test/unit --include='test_*.gd' | sort)
  PERFILE+=(${hits[@]+"${hits[@]}"})
done

mapfile -t FILES < <(printf '%s\n' ${TREE[@]+"${TREE[@]}"} ${PERFILE[@]+"${PERFILE[@]}"} | sort -u)
echo "pre_ready_guards: ${#TREE[@]} test-tree + ${#PERFILE[@]} per-file hits over ${#TOUCHED[@]} touched file(s) (committed + uncommitted) -> ${#FILES[@]} guards"
exec tools/run_tests.sh "${FILES[@]/#/res://}"
