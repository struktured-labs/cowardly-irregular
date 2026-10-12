#!/usr/bin/env bash
# pre_ready_guards.sh — run every guard whose corpus is a DIRECTORY rather than a symbol. Run it
# before READY: a guard that scans a tree names none of your symbols, so a symbol-derived corpus
# cannot contain it (the first .654 gate red on exactly that, 2026-10-12, and cowir-main's lesson
# the same day: "a lane corpus misses guards that scan src/ and assets/ as well as test/ — run the
# guards over the DIRECTORY you touched").
#
# NOTHING HERE IS LISTED — not the guards, and not the trees either. The first version of this file
# covered only test/, which is how the lesson it quotes went half-applied; the second hardcoded
# test/src/assets and still missed tools/ (11 guards) and data/ (116 — where every manifest lives).
# A hardcoded tree list is the same defect one level up, so the trees come from the DIFF and the
# guards come from the tree. Measured on c1054f593: test 87 · src 245 · data 116 · assets 38 ·
# tools 11 · addons 0.
#
# WHICH trees count is keyed to the diff, not to what you remember touching — a trigger that
# depends on the author noticing has already failed once per lane. If the diff cannot be read,
# EVERY tree runs: the failure direction has to be more work, never a silent pass.
#
# The derivation is a deliberate SUPERSET. "Walks a directory" plus "names this tree" also matches a
# file that merely preloads from the tree while walking another (a preload path is a symbol-reacher
# wearing a path), so src derives 245 where a binding-following scan finds 134. Over-wide costs
# seconds inside one run_tests.sh process; over-narrow costs a regate.
#
# `--list` prints the derivation and exits without running anything. It exists because the first
# attempt to test this file ran the whole suite six times: a tool that only ever execs is a tool
# whose own branching cannot be checked cheaply.
#
# Exit codes are run_tests.sh's own, plus 2 when the derivation itself looks broken.
set -uo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
LIST_ONLY=0
[ "${1:-}" = "--list" ] && LIST_ONLY=1

# Unions the walk forms with the two this file originally used, so it cannot derive less than it
# used to: measured, the generic form alone is already a strict superset of the original 38.
WALKS='DirAccess\.(open|get_files_at|get_directories_at)|list_dir_begin|dir_contents|get_files\(\)'

# POSITIVE CONTROL, not a floor on your branch. A floor per tree cannot work — addons/ legitimately
# derives 0 — so the thing to prove is that the WALK REGEX still matches, which is what silently
# breaks. If this trips, the scan is broken, not your change.
MIN_WALKERS=100

_walkers_naming() {  # $1 = tree, e.g. src
  grep -rlE "$WALKS" test/unit --include='test_*.gd' 2>/dev/null \
    | xargs -r grep -lE "\"res://$1" 2>/dev/null | sort
}

mapfile -t ALL_WALKERS < <(grep -rlE "$WALKS" test/unit --include='test_*.gd' 2>/dev/null | sort)
if [ "${#ALL_WALKERS[@]}" -lt "$MIN_WALKERS" ]; then
  echo "pre_ready_guards: the walk scan matched only ${#ALL_WALKERS[@]} file(s) in test/unit, expected at least $MIN_WALKERS." >&2
  echo "                  The DERIVATION is broken, not your branch. Refusing to call that a pass." >&2
  exit 2
fi

# ---- which trees the change can be seen from: ask the diff, and fail toward MORE ----
# PRE_READY_PATHS lets a caller state the changed paths instead of having this script infer them.
# The fold already knows exactly which files a batch touches, and inferring from one branch's
# merge-base cannot answer for a fold of sixteen. It is also the only way to exercise the
# "no tree has a walker" arm from a branch that itself edits tools/.
BASE=""
CHANGED="${PRE_READY_PATHS:-}"
if [ -z "${CHANGED//[[:space:]]/}" ]; then
  BASE="$(git merge-base HEAD origin/main 2>/dev/null || true)"
  if [ -n "$BASE" ]; then
    CHANGED="$({ git diff --name-only "$BASE" HEAD; git status --porcelain --no-renames | cut -c4-; } 2>/dev/null)"
  fi
fi

if [ -z "${CHANGED//[[:space:]]/}" ]; then
  mapfile -t TREES < <(printf 'test\nsrc\ndata\nassets\ntools\naddons\n')
  WHY="no readable diff vs origin/main — every tree"
else
  # Top-level directory of every changed path. A new top-level tree needs no edit here.
  mapfile -t TREES < <(printf '%s\n' "$CHANGED" | awk -F/ 'NF>1 && $1 != "" {print $1}' | sort -u)
  WHY="$(printf '%s ' "${TREES[@]}")"
fi

FILES=()
FIRED=0
for t in "${TREES[@]}"; do
  [ -n "$t" ] || continue
  mapfile -t L < <(_walkers_naming "$t")
  [ "${#L[@]}" -gt 0 ] || continue
  echo "pre_ready_guards: ${#L[@]} guards walk res://$t"
  FILES+=("${L[@]}")
  FIRED=1
done

if [ "$FIRED" = 0 ]; then
  echo "pre_ready_guards: no guard walks any tree this change touches ($WHY) — nothing directory-scoped can see it"
  exit 0
fi

# The trees overlap heavily (one guard can walk two), and run_tests.sh would run a duplicate twice.
mapfile -t FILES < <(printf '%s\n' "${FILES[@]}" | sort -u)
echo "pre_ready_guards: ${#FILES[@]} distinct guards for: $WHY"
[ "$LIST_ONLY" = 1 ] && exit 0
exec tools/run_tests.sh "${FILES[@]/#/res://}"
