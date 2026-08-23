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

# NAMED-MEMBER CANARY, ON THE OUTPUT SIDE (cowir-sfx / cowir-ai, 2026-08-22).
# The zero-check above catches TOTAL parse failure only. A pipeline that drops SOME
# patterns — one preset's line formatted differently, an anchor that stops matching one
# spelling — still yields a non-empty array, and a partial parse reports FEWER dead
# patterns, which reads as a CLEANER audit. Same total-vs-partial split that made the
# coverage guard hollow twice.
#
# cowir-ai's refinement is why this reads the OUTPUT, not the input: a canary naming a
# member of the computation's INPUT (the cfg is readable, it has exclude_filter lines)
# survives a broken computation intact — a reader test wearing a canary's clothes. The
# member must sit DOWNSTREAM of what can break, so this asserts that a pattern extracted
# by a SECOND, INDEPENDENT method is present in what the pipeline produced.
#
# awk -F'"' / -F',' shares no sed expression, no tr and no sort with the mapfile above, so
# the two agree only if the extraction actually worked. Checked PER LINE, because a
# whole-file canary passes while one preset's filter is silently dropped.
# ⚠️ THE FIRST VERSION OF THIS CANARY CHECKED ONLY EACH LINE'S FIRST TOKEN, and it was
# STRUCTURALLY INCAPABLE of firing. Measured 2026-08-22: this cfg has 5 exclude_filter
# lines and exactly TWO distinct first tokens (*.pre_normalize.png x4, *.jpg x1), so
# dropping a whole line leaves its first token in PATTERNS via another line. Two landed
# mutations — drop one whole line, drop the alphabetically-first pattern — both passed
# EC=0 with no BLOCKED line. A canary that names a member SHARED across the population
# it is sampling cannot detect the loss of any one member.
# Every token is checked, so a dropped line must lose at least its preset-specific ones.
#
# ⚠️ STATED GRANULARITY (cowir-sfx: "a canary detects at the CARDINALITY of the member it
# names" — so the comment must say which, or a reader assumes the finer one). Measured
# 2026-08-22 by deleting each exclude_filter line in turn and re-deriving the set:
#     [preset.0] Linux            no unique tokens  -> loss INVISIBLE here
#     [preset.2] Windows Desktop  no unique tokens  -> INVISIBLE
#     [preset.3] macOS            no unique tokens  -> INVISIBLE
#     [preset.1] Web              13 unique         -> DETECTED
#     [preset.4] Android          no unique tokens  -> INVISIBLE
# That blind spot is not a weakness: PATTERNS is `sort -u` deduped and every verdict below
# derives from it alone, so dropping a line whose tokens are all duplicated changes the
# audit's output by NOTHING. The canary is blind to exactly the losses that are semantically
# null — and it sees the one line that carries the deploy-critical music/tools/test globs.
# A preset losing its filter ENTIRELY is a different failure and is caught per-preset by the
# COVERAGE arm above; do not read this canary as covering that.
while IFS= read -r _line; do
    while IFS= read -r _canary; do
        [ -n "$_canary" ] || continue
        _found=0
        for _p in "${PATTERNS[@]}"; do [ "$_p" = "$_canary" ] && { _found=1; break; }; done
        [ "$_found" -eq 1 ] || {
          echo "[patterns] BLOCKED: '${_canary}' appears on an exclude_filter line in $CFG —" >&2
          echo "        read with awk, independently of the sed/tr/sort pipeline — but it is NOT" >&2
          echo "        among the ${#PATTERNS[@]} patterns that pipeline produced." >&2
          echo "        The extraction is dropping patterns. Every verdict below would describe a" >&2
          echo "        SUBSET while reading like a complete audit, and the non-empty check above" >&2
          echo "        cannot see a partial failure." >&2; exit 2; }
    done < <(printf '%s' "$_line" | awk -F'"' '{print $2}' | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
done < <(command grep -a '^exclude_filter=' "$CFG")

# ⚠️ CANARY ON THE COUNTER, added 2026-08-22. The canary above is downstream of the
# EXTRACTION and UPSTREAM of `_count_now`, which is what decides every verdict below.
# cowir-sprites' rule: being downstream of SOMETHING is not being downstream of the thing
# that breaks. Measured — `_count_now` stubbed to always return 1:
#     "24 distinct exclude pattern(s): 24 matching now, 0 historical, 0 never-matched"  EC=0
# A perfectly clean audit from a completely dead counter, and not one cardinal moved.
#
# Both comparands are TYPED LITERALS, never derived (cowir-sfx: a literal cannot co-vary
# with the thing it checks; a check you can write without knowing the answer cannot be
# wrong and cannot be right). The positive uses `tools/*` because THIS SCRIPT lives under
# tools/ — so a working counter must find at least one file, and no repo change can make
# that stale without also deleting the script doing the asking.
_CN_POS="$(_count_now 'tools/*')"
_CN_NEG="$(_count_now 'ZZZ_no_such_path_ever_*')"
if [ "${_CN_POS:-0}" -le 0 ] || [ "${_CN_NEG:-1}" -ne 0 ]; then
  echo "[patterns] BLOCKED: the file counter is not working — 'tools/*' counted ${_CN_POS}" >&2
  echo "        (this script lives under tools/, so a working counter cannot return 0) and" >&2
  echo "        a fabricated pattern counted ${_CN_NEG} (must be 0)." >&2
  echo "        Every verdict below is decided by that counter: a counter stuck high reports" >&2
  echo "        every pattern as live and prints a CLEAN audit; stuck low reports them all" >&2
  echo "        dead. Neither moves an exit code or a count on its own." >&2; exit 2; fi

# THE SAME FOR `_count_ever`, which splits STALE from PROPHYLACTIC — i.e. "someone wrote
# this against a name that never existed, act on it" from "a guard against a file type
# nobody has added, fine". A dead _count_ever calls EVERY never-matched pattern
# prophylactic-and-fine, which is the exact mislabel fixed earlier tonight arriving by a
# different route. Typed literals again; `tools/*` because this script's own directory
# must have files added in history for the script to exist at all.
_CE_POS="$(_count_ever 'tools/*')"
_CE_NEG="$(_count_ever 'ZZZ_no_such_path_ever_*')"
if [ "${_CE_POS:-0}" -le 0 ] || [ "${_CE_NEG:-1}" -ne 0 ]; then
  echo "[patterns] BLOCKED: the history counter is not working — 'tools/*' counted ${_CE_POS}" >&2
  echo "        (files under tools/ were certainly added at some point — this script is one)" >&2
  echo "        and a fabricated pattern counted ${_CE_NEG} (must be 0)." >&2
  echo "        That counter decides STALE vs PROPHYLACTIC, so a dead one labels every" >&2
  echo "        never-matched pattern 'prophylactic, fine' — the reassuring verdict." >&2; exit 2; fi

# ⚠️ PER-PRESET VIEW — added 2026-08-22 after cowir-sfx/cowir-adhoc's PERMUTATION finding.
# Everything below this point reasons over PATTERNS, which is `sort -u` across ALL presets:
# a UNION. Measured: moving `assets/audio/music/*industrial*` from the Web preset to Android
# produces BYTE-IDENTICAL output — 24 patterns, 19 live, 3 prophylactic, 2 never-matched,
# EC=0, zero BLOCKED lines, both before and after. The set is unchanged; only the
# preset->pattern PAIRING moved, and a set-based check cannot see a permutation by
# construction.
#
# That is deploy-relevant rather than academic: the web preset is the size-capped one, so a
# pattern migrating off it silently adds its files to the pck. `*industrial*` alone is
# 18.8 MiB against 34 MiB of headroom — under the cap, so gate 3 is blind to it too. Both
# instruments miss the same event, for unrelated reasons.
#
# Reported, not blocked: a preset legitimately may carry a different filter from its
# siblings (Web carries 24 to the desktop presets' 11, by design). The fix is to make the
# distribution VISIBLE so a migration shows up as a count that moved, rather than to pin a
# per-preset membership list — which would be a use-site pin and would red on every
# legitimate edit.
echo "[patterns] per-preset distribution (a UNION cannot show a pattern MOVING between presets):"
awk '/^\[preset\.[0-9]+\]$/{sec=$0}
     /^name=/{if(sec!="")nm[sec]=$0}
     /^exclude_filter=/{if(sec!=""){n=split($0,a,","); printf "             %-12s %-24s %2d pattern(s)\n", sec, nm[sec], n}}' "$CFG"

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
        elif [ -n "$dir" ] && [ ! -d "$dir" ]; then
            # A THIRD SHAPE, added 2026-08-22 after a control landed outside the taxonomy.
            # The two documented buckets are "bare extension guard" (*.jpg — prophylactic,
            # correct) and "real directory prefix, dead spelling" (*futuristic* — STALE,
            # act on it). A pattern whose prefix names a directory that DOES NOT EXIST is
            # neither: it cannot be prophylactic, because a prophylactic guards a file TYPE
            # and names no path. Printing "fine" for it asserts intent this script cannot
            # observe — and a typo'd or renamed directory is exactly what it looks like.
            echo "             ${p}"
            echo "                 ^ its prefix '${dir}' IS NOT A DIRECTORY in this repo."
            echo "                   Not prophylactic (those name a file type, not a path)."
            echo "                   Either the directory was renamed/removed and this"
            echo "                   pattern is now dead, or the path was mistyped when"
            echo "                   written — in both cases whatever it MEANT to exclude"
            echo "                   is shipping unless another pattern catches it."
        else
            echo "             ${p}   (bare file-type guard, no path component — prophylactic, fine)"
        fi
    done
fi
exit 0
