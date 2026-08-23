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

# COVERAGE — the parse below keys on a LINE PATTERN, and a line pattern reports on however
# many presets it HAPPENED to match. A preset whose filter is formatted differently, or a
# preset added with no exclude_filter at all, parses clean and audits a SUBSET — which is
# indistinguishable in the output from a complete audit. That is the same shape as the
# never-matched/zero split this script exists to disambiguate, one level up: "covered and
# clean" and "never looked at" must not print the same.
#
#   Measured 2026-08-09 on main: 5 preset sections, one exclude_filter each.
#
# CHECKED PER SECTION, NOT BY COUNT. The first version of this guard compared
# `count(presets)` against `count(exclude_filter lines)` — and a count cannot tell
# "one each" from "one preset carrying two while another carries none." Equal totals,
# one preset silently unaudited. A count catches a filter that VANISHED; it never
# catches one that MOVED, and moved is the case that leaves the report looking complete.
# Naming which section is uncovered is the property this audit actually depends on.
#
# `^exclude_filter=` anchors to line start so it cannot match `encryption_exclude_filters=`.
#
# WARNS, does not block. A preset legitimately may carry no exclude_filter — that ships
# everything, which is a decision, not a parse failure. Blocking here would refuse a
# correct config; staying silent would let a partial audit read as a full one.
# ENUMERATE FIRST, AND PROVE THE ENUMERATION IS NON-EMPTY. This guard exists so that
# "covered and clean" and "never looked at" stop printing the same — and its own section
# scan had exactly that defect: if /^\[preset\.N\]/ stops matching (Godot renames the
# section, adds whitespace, changes the numbering), awk prints nothing, UNCOVERED is
# empty, and the guard is SILENT — byte-identical to a clean audit.
# MEASURED 2026-08-22: headers rewritten to [exportpreset.N] -> 0 sections enumerated,
# EC=0, no COVERAGE line, output indistinguishable from the real config's.
# This is cowir-sprites' rule — "a guard that enumerates from the data it checks can only
# confirm that data agrees with itself" — and the fix is to check the ENUMERATION against
# something the enumeration cannot produce: the raw section count.
SECTIONS="$(command grep -ac '^\[preset\.[0-9]*\]' "$CFG" || true)"
[ "${SECTIONS:-0}" -gt 0 ] || {
  echo "[patterns] BLOCKED: parsed 0 preset sections from $CFG — the section scan is wrong," >&2
  echo "        not the config. A zero here would otherwise print as a clean coverage" >&2
  echo "        report, which is the exact confusion this guard exists to prevent." >&2; exit 2; }

# ⚠️ BLOCKING ON *ZERO* IS NOT ENOUGH — a scan that HALF works is silent too, and my
# first attempt at this was the very defect it was fixing. Measured 2026-08-22:
#   rename ONE of five preset headers -> SECTIONS is 4, which is > 0, so a zero-check
#   passes while that preset is never audited. EC=0, no COVERAGE line, no BLOCKED line.
# I then "fixed" it by having awk count what it saw and comparing to the grep count —
# BOTH DERIVED FROM THE SAME PATTERN, so a renamed header drops both to 4 and they agree.
# That is cowir-sprites' rule ("a guard that enumerates from the data it checks can only
# confirm that data agrees with itself") reproduced inside the fix for it.
#
# The witness has to be INDEPENDENT of the thing it witnesses. Godot writes exactly one
# [preset.N.options] block per [preset.N], so the options blocks count the presets without
# reading the preset headers at all. Rename a header and the pairing breaks: 4 vs 5.
OPTIONS="$(command grep -ac '^\[preset\.[0-9]*\.options\]$' "$CFG" || true)"
[ "${SECTIONS:-0}" = "${OPTIONS:-0}" ] || {
  echo "[patterns] BLOCKED: $SECTIONS preset header(s) but $OPTIONS options block(s) in $CFG." >&2
  echo "        Godot writes one [preset.N.options] per [preset.N], so a mismatch means the" >&2
  echo "        header scan is missing presets — and every verdict below would describe a" >&2
  echo "        SUBSET while reading like a full audit." >&2; exit 2; }

# ⚠️ MEASURED 2026-08-22 on the MERGED tree: this arm tested for the WRONG FORM of the
# defect. Deleting a preset's `exclude_filter=` line fired the COVERAGE warning; setting it
# to `exclude_filter=""` was COMPLETELY SILENT — EC=0, no warning — while that preset ships
# EVERYTHING, which is the exact condition this script exists to detect. And the empty form
# is the LIKELIER one: Godot's export dialog writes `exclude_filter=""` when the field is
# cleared in the UI; hand-deleting the line is the mutation a human would have to author.
# So the arm matched on the line's PRESENCE when the semantics live in its VALUE.
# Mutation placement is a parameter of the answer: I had tested delete and never empty.
UNCOVERED="$(awk '
    /^\[preset\.[0-9]+\]/ { if (s != "" && !f) print s; s = $0; f = 0; next }
    /^exclude_filter=/    { v = $0; sub(/^exclude_filter=/, "", v)
                            gsub(/["[:space:]]/, "", v)
                            if (s != "" && v != "") f = 1 }
    END                   { if (s != "" && !f) print s }
' "$CFG")"
if [ -n "$UNCOVERED" ]; then
    echo "[patterns] ⚠️  COVERAGE: preset section(s) with NO EFFECTIVE exclude_filter (absent OR empty) — not audited:" >&2
    echo "$UNCOVERED" | sed 's/^/               /' >&2
    echo "             A preset with no exclude_filter — or an EMPTY one — ships EVERYTHING. Nothing" >&2
    echo "             below this line describes it; the report is silent about what it never read." >&2
fi

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
    # SPLIT THE NEVER-MATCHED SET, because "delete it" is right for one half and
    # DANGEROUS for the other. cowir-music, 2026-08-06: *futuristic* was not a name that
    # never existed — it is the WORLD-ID vocabulary aimed at the MUSIC-KEY namespace.
    # World 5 is called Futuristic in monsters.json, in map ids, and in
    # GameLoop._get_world_for_map; its music tracks are all named *_digital, because
    # SoundManager's suffix function returns `digital`. The two vocabularies agree on
    # five of six worlds, which is why it survived the repo's entire history.
    #
    # So the INTENT was live and only the SPELLING was dead. Deleting such a pattern
    # drops a real exclusion silently — the opposite of the fix. Deleting a prophylactic
    # *.jpg costs nothing.
    #
    # The discriminator is whether the pattern AIMS AT A POPULATED DIRECTORY. A pattern
    # with a real directory prefix that holds files was written to catch something that
    # exists; a bare extension guard was not.
    echo "[patterns] ⚠️  NEVER matched a file in this repo's history:"
    for p in "${STALE[@]}"; do
        dir="${p%%\**}"; dir="${dir%/}"
        if [ -n "$dir" ] && [ -d "$dir" ] && [ "$(find "$dir" -type f 2>/dev/null | head -1)" ]; then
            echo "             ${p}"
            echo "                 ^ AIMED AT A POPULATED DIRECTORY ($(find "$dir" -type f | wc -l) files)."
            echo "                   The intent was probably LIVE and only the SPELLING is dead."
            echo "                   ⛔ Do NOT just delete it — first confirm the files it MEANT"
            echo "                      to exclude are caught by another pattern."
            echo "                      Known trap — stated as a RULE, not a count of vocabularies"
            echo "                      (that count went 2 -> 3 -> 4 in forty minutes on 2026-08-06):"
            echo "                        W5 is spelled differently by different systems, and each"
            echo "                        spelling is CORRECT in its own namespace. It is wrong only"
            echo "                        when a map/monster id reaches a consumer expecting the"
            echo "                        AUDIO FILENAME spelling. An exclude pattern IS a file path,"
            echo "                        so it has exactly one valid reading: the filename's."
        else
            echo "             ${p}   (no populated target dir — prophylactic, fine)"
        fi
    done
fi
exit 0
