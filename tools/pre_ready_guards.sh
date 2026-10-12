#!/usr/bin/env bash
# pre_ready_guards.sh — run every guard your branch can RED that your own corpus cannot contain.
#
# THREE derivations, unioned, because each misses what the others catch:
#   TREE      a guard that WALKS a directory names none of your symbols, so a symbol-derived corpus
#             cannot contain it (the first .654 gate red was exactly that). Measured on c1054f593:
#             test 87 · src 245 · data 116 · assets 38 · tools 11 · addons 0 — and `data/` is where
#             every manifest lives, the most common edit shape in three lanes. (@cowir-music)
#   PER-FILE  a guard that reads a file as TEXT and pins lines inside it: 347 test files name
#             src/battle/BattleManager.gd, and an inserted line above a pinned call reds one. (@cowir-sfx)
#   CLASSNAME the same, for files reached by their declared class_name instead of their path. Measured:
#             src/llm/VoiceLines.gd has 0 path dependents and 10 by name, Combatant.gd 176 vs 688,
#             test/unit/helpers/wav_fixture.gd 0 vs 9 — so a path-only scan derives NOTHING for some
#             files. (@cowir-overworld found the helpers half; the class_name half is the same cause.)
#
# NOTHING IS LISTED — not the guards, not the trees, not the dependents. This file has twice shipped a
# hardcoded list one level up from the thing it derived: first the guards were derived while `test/` was
# the only tree, then three trees were listed while `tools/` and `data/` were missed. The trees come
# from the diff, the guards from the tree, the dependents from the file.
#
# WHICH trees count is keyed to the DIFF, never to what you remember touching. If the diff cannot be
# read, EVERY tree runs: the failure direction must be more work, never a silent pass.
#
# The derivation is a deliberate SUPERSET. Over-wide costs seconds inside one run_tests.sh process;
# over-narrow costs a regate.
#
# `--list` prints the derivation and exits without running: a tool that only ever execs is one whose
# own branching cannot be checked cheaply.
# `PRE_READY_PATHS="a b c"` states the changed paths instead of inferring them — the fold knows exactly
# what a 16-branch batch touches, and one branch's merge-base cannot answer for a fold.
#
# Exit codes are run_tests.sh's own, plus 2 when a derivation itself looks broken.
set -uo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
LIST_ONLY=0
[ "${1:-}" = "--list" ] && LIST_ONLY=1

WALKS='DirAccess\.(open|get_files_at|get_directories_at)|list_dir_begin|dir_contents|get_files\(\)'
MIN_WALKERS=100   # positive control on the WALK REGEX, not a floor on your branch

mapfile -t ALL_WALKERS < <(grep -rlE "$WALKS" test/unit --include='test_*.gd' 2>/dev/null | sort)
if [ "${#ALL_WALKERS[@]}" -lt "$MIN_WALKERS" ]; then
  echo "pre_ready_guards: the walk scan matched only ${#ALL_WALKERS[@]} file(s) in test/unit, expected at least $MIN_WALKERS." >&2
  echo "                  The DERIVATION is broken, not your branch. Refusing to call that a pass." >&2
  exit 2
fi

# PRE_READY_PATHS states the changed paths; PRE_READY_BASE names the ref to diff against. The fold
# knows exactly what a 16-branch batch touches, and one branch's merge-base cannot answer for a fold.
CHANGED="${PRE_READY_PATHS:-}"
STATED=1
if [ -z "${CHANGED//[[:space:]]/}" ]; then
  STATED=0
  REF="${PRE_READY_BASE:-origin/main}"
  # A BROKEN git command and an EMPTY change list are different answers and get different treatment:
  # the first means something is wrong and is refused loudly; the second is legitimate (you are on the
  # base) and widens to every tree. Conflating them would make a bad ref look like "nothing changed".
  if ! BASE="$(git merge-base HEAD "$REF" 2>&1)"; then
    echo "pre_ready_guards: git merge-base HEAD $REF failed, so the change list cannot be derived: $BASE" >&2
    echo "                  Fetch the base or set PRE_READY_BASE=<ref> / PRE_READY_PATHS=<paths>." >&2
    exit 2
  fi
  # Committed AND uncommitted: you run this BEFORE committing, and a committed-only derivation
  # reported "0 touched files" on a planted edit sitting in the working tree.
  if ! CHANGED="$({ git diff --name-only "$BASE" HEAD; git status --porcelain --no-renames | cut -c4-; } 2>&1)"; then
    echo "pre_ready_guards: reading the diff against $BASE failed: $CHANGED" >&2
    exit 2
  fi
fi

if [ -z "${CHANGED//[[:space:]]/}" ]; then
  mapfile -t TREES < <(printf 'test\nsrc\ndata\nassets\ntools\naddons\n')
  WHY="no changed paths$( [ "$STATED" = 1 ] && printf ' were stated' || printf " vs ${PRE_READY_BASE:-origin/main}" ) — every tree"
  mapfile -t TOUCHED < <(printf '')
else
  mapfile -t TREES < <(printf '%s\n' "$CHANGED" | awk -F/ 'NF>1 && $1 != "" {print $1}' | sort -u)
  WHY="$(printf '%s ' "${TREES[@]}")"
  mapfile -t TOUCHED < <(printf '%s\n' "$CHANGED" | grep -E '\.(gd|json|tscn|cfg|tres)$' | sort -u)
fi

FILES=()

for t in ${TREES[@]+"${TREES[@]}"}; do
  [ -n "$t" ] || continue
  mapfile -t L < <(printf '%s\n' "${ALL_WALKERS[@]}" | xargs -r grep -lE "\"res://$t" 2>/dev/null | sort)
  [ "${#L[@]}" -gt 0 ] || continue
  echo "pre_ready_guards: ${#L[@]} guards walk res://$t"
  FILES+=("${L[@]}")
done

for f in ${TOUCHED[@]+"${TOUCHED[@]}"}; do
  [ -f "$f" ] || continue
  mapfile -t BY_PATH < <(grep -rlF "$f" test/unit --include='test_*.gd' 2>/dev/null | sort)
  BY_NAME=()
  case "$f" in
    *.gd)
      # A file reached by `class_name X` has NO path dependents at all in some cases, so this leg is
      # not a refinement of the path leg — for VoiceLines.gd it is the only leg that finds anything.
      cn="$(sed -n 's/^class_name[[:space:]]\+\([A-Za-z_][A-Za-z0-9_]*\).*/\1/p' "$f" | head -1)"
      if [ -n "$cn" ]; then
        mapfile -t BY_NAME < <(grep -rlw "$cn" test/unit --include='test_*.gd' 2>/dev/null | sort)
      fi ;;
  esac
  n=$(( ${#BY_PATH[@]} + ${#BY_NAME[@]} ))
  [ "$n" -gt 0 ] || continue
  echo "pre_ready_guards: $f -> ${#BY_PATH[@]} by path + ${#BY_NAME[@]} by class_name${cn:+ ($cn)}"
  FILES+=(${BY_PATH[@]+"${BY_PATH[@]}"} ${BY_NAME[@]+"${BY_NAME[@]}"})
  cn=""
done

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "pre_ready_guards: no tree guard and no dependent can see this change ($WHY) — nothing directory- or file-scoped applies"
  exit 0
fi

mapfile -t FILES < <(printf '%s\n' "${FILES[@]}" | sort -u)
echo "pre_ready_guards: ${#FILES[@]} distinct guards for: $WHY"
[ "$LIST_ONLY" = 1 ] && exit 0
exec tools/run_tests.sh "${FILES[@]/#/res://}"
