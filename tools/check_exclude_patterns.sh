#!/usr/bin/env bash
# check_exclude_patterns.sh — find exclude_filter patterns that match NOTHING.
#
# WHY THIS EXISTS
#   export_presets.cfg's exclude_filter is a HAND-WRITTEN LIST, and a hand-written list
#   fails in both directions: it names things that are fine and misses things that aren't.
#   The failure that costs content is silent — a pattern stops matching (files renamed,
#   a directory moved) and the exclusion simply stops happening. Nothing reports it. The
#   pck just gets bigger, and size cannot distinguish "we added content" from "an
#   exclusion quietly died".
#
#   Measured 2026-08-06 on main: 6 of 24 distinct patterns match zero files, and
#   `assets/audio/music/*futuristic*` has matched zero files in the repo's ENTIRE
#   HISTORY — it was written against a name that never existed. The tracks it was meant
#   to catch are named *industrial* / *digital* / *abstract*, and they are excluded by
#   other patterns, so nothing leaked. That is luck, not design.
#
# THE DISCRIMINATOR: "matches nothing NOW" has two very different causes
#   PROPHYLACTIC   never matched, and nothing of that kind was ever committed (*.jpg).
#                  Correct and intentional — a guard against a file type nobody has added.
#   INTERMEDIATE   matched historically, gitignored, absent between pipeline runs
#                  (*.pre_palette.png). Correct — it fires during a real sprite build.
#   STALE          matched nothing now AND nothing ever, but names something specific
#                  enough that it was clearly meant to catch real files. This is the
#                  vocabulary-mismatch class and the only one worth acting on.
#
#   The instrument for the split is git history, not the working tree. A working-tree
#   count alone reports all three identically — one zero, three causes.
#
# NON-BLOCKING BY DESIGN. A dead pattern does not necessarily ship wrong content, and a
# deploy that refuses over a prophylactic *.jpg would be worse than the problem. It
# reports; a human decides. Exit is always 0 unless the config itself is unreadable.
#
# Usage: tools/check_exclude_patterns.sh [export_presets.cfg]
set -uo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
CFG="${1:-export_presets.cfg}"
[ -s "$CFG" ] || { echo "[patterns] BLOCKED: $CFG missing or empty" >&2; exit 2; }

# Glob -> ERE. Only `*` is meaningful in Godot's filters; escape everything else that
# regex would otherwise interpret, or `.` in `*.jpg` matches any character and a dead
# pattern reports as live — a false NEGATIVE, the direction that hides.
_to_ere() { printf '%s' "$1" | sed 's/[][().^$+?{}|\\]/\\&/g; s/\*/.*/g; s/^/^/; s/$/$/'; }

_count_now() {   # working-tree files matching the pattern
    find . -path ./.git -prune -o -type f -print 2>/dev/null \
      | sed 's|^\./||' | command grep -c -- "$(_to_ere "$1")" 2>/dev/null || true
}
_count_ever() {  # files EVER added anywhere in history matching the pattern
    git log --all --diff-filter=A --name-only --format= -- "$1" 2>/dev/null \
      | command grep -av '^$' | sort -u | wc -l
}

mapfile -t PATTERNS < <(
  command grep -a 'exclude_filter=' "$CFG" \
    | sed 's/.*exclude_filter="//; s/"$//' \
    | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
    | command grep -av '^$' | sort -u
)
[ "${#PATTERNS[@]}" -gt 0 ] || {
  echo "[patterns] BLOCKED: parsed 0 patterns from $CFG — the parse is wrong, not the config." >&2
  echo "        A zero here would otherwise report as 'no dead patterns', which is the" >&2
  echo "        vacuous-pass shape this script exists to prevent elsewhere." >&2; exit 2; }

STALE=(); PROPH=(); LIVE=0
for p in "${PATTERNS[@]}"; do
    if [ "$(_count_now "$p")" -gt 0 ]; then LIVE=$((LIVE + 1))
    elif [ "$(_count_ever "$p")" -gt 0 ]; then PROPH+=("$p")
    else STALE+=("$p")
    fi
done

echo "[patterns] ${#PATTERNS[@]} distinct exclude pattern(s): ${LIVE} matching now, ${#PROPH[@]} historical/prophylactic, ${#STALE[@]} never-matched"
[ "${#PROPH[@]}" -gt 0 ] && { echo "[patterns] matched historically, absent now (pipeline intermediates — expected):"
                              printf '             %s\n' "${PROPH[@]}"; }
if [ "${#STALE[@]}" -gt 0 ]; then
    echo "[patterns] ⚠️  NEVER matched a file in this repo's history:"
    printf '             %s\n' "${STALE[@]}"
    echo "[patterns]    Prophylactic (*.jpg guarding a type nobody has added) is FINE."
    echo "[patterns]    A pattern naming something specific is a VOCABULARY MISMATCH:"
    echo "[patterns]    it excludes nothing, and whatever it was meant to catch still ships."
fi
exit 0
