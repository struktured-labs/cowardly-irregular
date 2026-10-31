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
## An unread argument is refused, not ignored: `--help` used to fall through to a full 300-script run.
case "$#:${1:-}" in
  0:) ;;
  1:--list) LIST_ONLY=1 ;;
  *) echo "pre_ready_guards: unknown argument(s): $* — the only flag is --list (prints the derivation, runs nothing)." >&2
     echo "                  Run with no arguments to run the guards; set PRE_READY_BASE / PRE_READY_PATHS to scope them." >&2
     exit 2 ;;
esac

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

# ONE PATH PER LINE from here on. PRE_READY_PATHS is documented as space-separated, and every
# derivation below reads lines — so a multi-path value arrived as ONE line, `awk -F/ '{print $1}'`
# returned only the FIRST path's tree, and the per-file legs got the whole string as a filename and
# were skipped by the `-f` test. Measured: a src+test set derived "src" alone and ran none of the ten
# test-dir guards, which are exactly what an added test file needs. (@cowir-ai, 2026-10-12)
CHANGED="$(printf '%s\n' "$CHANGED" | tr '[:space:]' '\n' | grep -v '^$' || true)"

if [ -z "${CHANGED//[[:space:]]/}" ]; then
  mapfile -t TREES < <(printf 'test\nsrc\ndata\nassets\ntools\naddons\n')
  WHY="no changed paths$( [ "$STATED" = 1 ] && printf ' were stated' || printf " vs ${PRE_READY_BASE:-origin/main}" ) — every tree"
  mapfile -t TOUCHED < <(printf '')
  mapfile -t CHANGED_PATHS < <(printf '')   # no stated paths: nothing to account for
else
  mapfile -t TREES < <(printf '%s\n' "$CHANGED" | awk -F/ 'NF>1 && $1 != "" {print $1}' | sort -u)
  WHY="$(printf '%s ' "${TREES[@]}")"
  mapfile -t TOUCHED < <(printf '%s\n' "$CHANGED" | grep -E '\.(gd|json|tscn|cfg|tres|godot|sh|py)$' | sort -u)
  mapfile -t CHANGED_PATHS < <(printf '%s\n' "$CHANGED" | grep -vE '^[[:space:]]*$' | sort -u)
fi

FILES=()
COVERED_TREES=()

for t in ${TREES[@]+"${TREES[@]}"}; do
  [ -n "$t" ] || continue
  mapfile -t L < <(printf '%s\n' "${ALL_WALKERS[@]}" | xargs -r grep -lE "\"res://$t" 2>/dev/null | sort)
  [ "${#L[@]}" -gt 0 ] || continue
  # ⛔ THE PREDICATE ABOVE IS A SUPERSET, NOT A WALK OF THIS TREE. It keeps any walk-capable
  # file that merely MENTIONS "res://$t — and 81 of test/'s 113 only `preload` a helper from
  # test/unit/helpers/, while walking res://src. A green over those is regression cover; it is
  # NOT evidence that a file you ADDED under res://$t was judged. Measured 2026-10-26 after
  # @cowir-music asked what their step-4 green covered, and the honest answer was 15 of 113.
  # DIRECT is a conservative floor: it counts only a walk form and the path on ONE line, so a
  # `const DIR := "res://$t"` walked three lines later is missed. Understating is the safe
  # direction here — the risk is a lane trusting the bigger number.
  # The discriminator is whether the file names a res://$t path that is a DIRECTORY: a helper
  # import is ".../helpers/gd_source.gd" and cannot be walked, while a walker holds
  # "res://$t" or "res://$t/unit" — usually in a const, which is why keying on "a walk form
  # and the path on ONE line" scored 5 of an actual ~15 and was too weak to be useful.
  DIRECT=0
  for _f in "${L[@]}"; do
    grep -oE "\"res://$t[^\"]*\"" "$_f" 2>/dev/null | grep -qvE '\.gd"$' && DIRECT=$((DIRECT+1))
  done
  # ⚠️ "N guards walk res://$t" IS A PARSED CONTRACT, not prose: test_the_pre_ready_sweep_derives_each_leg
  # finds that phrase and reads the number immediately before it. Rewording the line to "N guards
  # reference res://$t" red three of its arms with "derived -1 walkers" — the count went missing, not
  # wrong. So the substring stays verbatim and the correction is APPENDED after it.
  echo "pre_ready_guards: ${#L[@]} guards walk res://$t; >= $DIRECT hand it a res://$t path, the rest only import from it"
  if [ "$DIRECT" -lt "${#L[@]}" ]; then
    echo "pre_ready_guards:   an importer cannot see a file you ADD under res://$t — that part of a green is regression cover, not step-4 evidence"
  fi
  COVERED_TREES+=("$t")
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

# EVERY changed path is accounted for, or named. The per-file leg takes an extension allowlist, which
# is a branch set with no else: before 2026-10-12 a kind it did not list was dropped in silence, so a
# project.godot change derived 0 of the 39 guards that read it and the tool said "nothing applies".
# A path is covered if the per-file leg considered it, or its tree yielded walkers. Anything else is
# reported rather than absorbed — a reader can act on a named gap and cannot act on an absence.
UNSEEN=()
for c in ${CHANGED_PATHS[@]+"${CHANGED_PATHS[@]}"}; do
  [ -n "$c" ] || continue
  seen=0
  for f in ${TOUCHED[@]+"${TOUCHED[@]}"}; do [ "$f" = "$c" ] && seen=1 && break; done
  if [ "$seen" = 0 ] && [ "${c%%/*}" != "$c" ]; then
    for t in ${COVERED_TREES[@]+"${COVERED_TREES[@]}"}; do [ "$t" = "${c%%/*}" ] && seen=1 && break; done
  fi
  [ "$seen" = 1 ] || UNSEEN+=("$c")
done
if [ "${#UNSEEN[@]}" -gt 0 ]; then
  echo "pre_ready_guards: ${#UNSEEN[@]} changed path(s) NO LEG CAN SEE — derived from nowhere above, so a green here says nothing about them:"
  printf 'pre_ready_guards:     %s\n' "${UNSEEN[@]}"
fi

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "pre_ready_guards: no tree guard and no dependent can see this change ($WHY) — nothing directory- or file-scoped applies"
  exit 0
fi

mapfile -t FILES < <(printf '%s\n' "${FILES[@]}" | sort -u)
# Name the trees that actually YIELDED guards, not every tree in the change set: with a stated docs/
# path the summary read "guards for: docs src" two lines under a warning saying docs is seen by
# nothing — a plausible label contradicting the true one directly above it. A root-level file has no
# tree at all, so branch on the array COUNT, not on a string: `printf '%s '` over an empty array
# yields a SPACE, so `${X:-fallback}` never fires and the label looked empty while it was not.
if [ "${#COVERED_TREES[@]}" -gt 0 ]; then
  LABEL="$(printf '%s ' "${COVERED_TREES[@]}")"
else
  LABEL="per-file dependents only (no tree in the change set)"
fi
echo "pre_ready_guards: ${#FILES[@]} distinct guards for: $LABEL"
[ "$LIST_ONLY" = 1 ] && exit 0
exec tools/run_tests.sh "${FILES[@]/#/res://}"
