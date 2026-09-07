#!/usr/bin/env bash
# pck_manifest.sh — record WHAT a build shipped, so two builds can be compared.
#
# WHY THIS EXISTS
#   A deploy reports `pck 148.8 MiB · FITS`. That is a scalar summary of ten thousand
#   decisions, and every deploy defect found this week was invisible in it:
#     · 1146 test scripts + the GUT addon packed into the player's binary
#     · 629 KiB of dead audio (30s raw sources of cues that ship at 1.5s)
#     · an exclusion pattern (*futuristic*) matching zero files, for months
#     · 54 W4-W6 ending tracks excluded from web
#   Each cost an evening to find. Each is one line of a diff.
#
#   And size CANNOT distinguish the two directions. A pck that shrank is what
#   compression looks like AND what dropping content looks like. That ambiguity is
#   not theoretical here: the 48k audio tier made the web pck SMALLER while adding
#   54 tracks, and the only reason a content loss would have been noticed is that
#   an assertion happened to block a good build and made someone look.
#
# THE MANIFEST IS DERIVED FROM THE EXPORT'S OWN ACCOUNT OF ITSELF
#   Godot logs one `Storing File: res://...` per resource it packs. That is the
#   artifact describing what it did, not an inference from export_presets or from
#   the filesystem — both of which have been wrong about the shipped set before.
#
# Usage:
#   tools/pck_manifest.sh <export.log> [out.manifest]     record a build
#   tools/pck_manifest.sh --diff <old.manifest> <new.manifest>
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

_extract() {   # export log -> sorted resource paths
    # `grep -a`: godot logs contain NUL bytes, and the session grep treats a file
    # with NULs as binary and prints NOTHING — a silent zero on the primary artifact.
    command grep -a 'Storing File:' "$1" \
      | sed 's/.*Storing File: //' \
      | sed 's/[[:space:]]*$//' \
      | sort -u
}

if [ "${1:-}" = "--diff" ]; then
    OLD="${2:?need old manifest}"; NEW="${3:?need new manifest}"
    for f in "$OLD" "$NEW"; do
        [ -s "$f" ] || { echo "[pck] BLOCKED: $f is empty or missing — a manifest that" >&2
                         echo "        recorded nothing diffs as 'everything was removed'." >&2; exit 2; }
    done
    # Real files, never process substitution: this box's `comm` short-reads a pipe
    # (single read(), no loop to EOF) and silently returns FEWER differences than
    # exist — worst case 0, which reads as a clean audit. Documented in CLAUDE.md.
    T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
    sort -u "$OLD" > "$T/old"; sort -u "$NEW" > "$T/new"
    comm -13 "$T/old" "$T/new" > "$T/added"
    comm -23 "$T/old" "$T/new" > "$T/removed"

    # comm's own sanity check: against /dev/null it must return every line. Unsorted
    # input makes comm return everything and the /dev/null control cannot see that,
    # so `sort -c` is checked too.
    for s in old new; do
        n=$(wc -l < "$T/$s"); c=$(comm -23 "$T/$s" /dev/null | wc -l)
        [ "$n" -eq "$c" ] || { echo "[pck] BLOCKED: comm short-read $s ($c of $n)" >&2; exit 3; }
        sort -c "$T/$s" 2>/dev/null || { echo "[pck] BLOCKED: $s not sorted" >&2; exit 3; }
    done

    A=$(wc -l < "$T/added"); R=$(wc -l < "$T/removed")
    echo "[pck] $(wc -l < "$T/old") -> $(wc -l < "$T/new") resources   (+${A} / -${R})"
    echo
    _bucket() {   # summarise by top-level area so 1146 test files are one line
        [ -s "$1" ] || { echo "    (none)"; return 0; }
        sed 's|^res://||' "$1" | awk -F/ '{print ($2=="") ? $1 : $1"/"$2}' \
          | sort | uniq -c | sort -rn | head -12 | sed 's/^/    /'
    }
    echo "  ADDED (${A}):";   _bucket "$T/added"
    echo
    # Removals get named individually, not bucketed. Content leaving a build is the
    # direction size cannot see and the one nobody goes looking for.
    echo "  REMOVED (${R}):"
    if [ "$R" -eq 0 ]; then echo "    (none)"
    elif [ "$R" -le 40 ]; then sed 's/^/    - /' "$T/removed"
    else _bucket "$T/removed"; echo "    ⚠ ${R} removals — listed by area; full list in the manifest diff"
    fi
    echo
    [ "$R" -gt 0 ] && echo "  ⚠ ${R} resource(s) present in the OLD build and absent from the NEW one." >&2
    exit 0
fi

LOG="${1:?usage: pck_manifest.sh <export.log> [out.manifest]}"
OUT="${2:-${LOG%.log}.manifest}"
[ -s "$LOG" ] || { echo "[pck] BLOCKED: $LOG missing or empty" >&2; exit 2; }
_extract "$LOG" > "$OUT"
N=$(wc -l < "$OUT")
# A manifest of 0 is what a wrong log path produces, and it would diff as "the whole
# build was deleted". Refuse rather than record it.
[ "$N" -gt 0 ] || { echo "[pck] BLOCKED: no 'Storing File:' lines in $LOG — wrong log, or" >&2
                    echo "        the export never packed anything. Refusing to write an empty manifest." >&2
                    rm -f "$OUT"; exit 2; }
echo "[pck] ${N} resources -> ${OUT}"

# ⚠️ A DIFF IS ONLY MEANINGFUL IF THE TWO BUILDS DIFFER IN ONE THING.
# First real use compared a STAGED build (endings swapped in, 48k tier) against a
# NORMAL export and reported "-54 assets/audio". True, and the headline was
# misleading: those endings were never in the normal build. The tool cannot know
# which differences you intended. Diff like against like -- same preset, same
# staging -- or read every bucket rather than the summary line.
