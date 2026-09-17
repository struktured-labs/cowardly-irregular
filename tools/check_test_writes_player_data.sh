#!/usr/bin/env bash
# Does this test file write the PLAYER'S data? Run it before you fold a new test.
#
# WHY THIS EXISTS
# ---------------
# 2026-09-17: eight unit tests were writing into user:// — six left autobattle/profiles.json,
# two left settings.json. A full-suite run in a virgin sandbox found two of them; an exhaustive
# per-file sweep of all 1997 files found all eight.
#
# WHAT GREP CAN AND CANNOT DO HERE — corrected 2026-09-17 after @cowir-battle measured it, because
# the first version of this header claimed these were invisible to every source census and that is
# FALSE. The distinction is the PATTERN SHAPE:
#
#     Receiver.api(   MISSES them. The route is dynamic on both ends —
#                       get_node_or_null("/root/AutobattleSystem")   autoload by STRING
#                       abs.set_character_script(char_id, ...)       api via a LOCAL
#                     so the literal appears neither in the test nor at the call site.
#     \.api(          FINDS the producer: Combatant.gd:1570 and nine others. Receiver-agnostic
#                     is immune to the string route by construction.
#
# ⛔ SO GREP CAN POINT AND CANNOT BOUND. The receiver-agnostic census is correct and yields ~1044
# candidate test files, and it cannot say which of them actually writes — the three real writers
# were inside that corpus and were lost when it was narrowed to 56 for being noisy. THAT is the
# reason to run the thing: not that the census is blind, but that its honest output is a thousand
# maybes and only execution turns those into a list.
#
# ⛔ TWO HAZARDS, TWO GRANULARITIES. Conflating them is what made the sound sweep look
# unaffordable, so this script fixes both and neither is negotiable:
#
#   MASKING           `_test_disable_persistence` is a per-PROCESS autoload global. A test that
#                     sets it and never restores SILENCES EVERY LATER LEAKER IN THAT PROCESS.
#                     Measured: masker+leaker in one process -> nothing written; the same pair
#                     in two processes -> still written. => ONE FILE PER INVOCATION.
#   NET BLINDNESS     run_tests.sh snapshots the netted dirs (script_exports autogrind autobattle
#                     input) and restores with `cp -a`, which carries MTIME. In a REUSED sandbox a
#                     write is invisible to a content hash AND to mtime. The net only arms if the
#                     dir already exists. => ONE FRESH SANDBOX PER RUN.
#
# ⚠️ AND `0 files` IS AMBIGUOUS BY ITSELF — it is equally what you get when the redirect never
# fired and godot wrote somewhere else entirely. Two controls, closing two different vacuities:
#   A. dirs created under the sandbox   => godot really ran HERE (autoload _ready makes them)
#   B. plant a file, rescan, see it     => the scan can actually report a write
# A positive result supplies B for free; a null needs it stated.
#
# 📌 END-STATE ONLY. A test that writes then deletes leaves nothing, and this says "clean".
# "clean" means NOTHING SURVIVED, never "nothing was written".
#
# Usage:   tools/check_test_writes_player_data.sh <name> [<name> ...]
#          tools/check_test_writes_player_data.sh --all-autogrind
# Exit:    0 nothing written · 1 a test left player data · 2 bad invocation

set -u
cd "$(dirname "$0")/.." || exit 2

UD_REL='godot/app_userdata/Cowardly Irregular'
# Engine artifacts, not player data. logs/ is godot's own; shader_cache is a build artifact.
# grep, not sed: the pattern contains `/`, which terminates sed's `/.../d` address.
# That bug emptied the file list and the plant control caught it -- kept as the reason.
IGNORE_RE='^\./(logs/|shader_cache/)'

[ "$#" -ge 1 ] || { echo "usage: $0 <test-name> [...]  |  --all-autogrind" >&2; exit 2; }

NAMES=()
if [ "$1" = "--all-autogrind" ]; then
  for f in test/unit/test_autogrind*.gd; do
    [ -e "$f" ] || { echo "$0: no test_autogrind*.gd found" >&2; exit 2; }
    n="${f##*/test_}"; NAMES+=("${n%.gd}")
  done
else
  NAMES=("$@")
fi

leaked=0
scanned=0

for name in "${NAMES[@]}"; do
  sb="$PWD/tmp/pdw_$$"
  rm -rf "$sb"; mkdir -p "$sb" || exit 2

  XDG_DATA_HOME="$sb" timeout 900 tools/run_tests.sh "$name" > "tmp/pdw_$$.log" 2>&1
  ec=$?
  ud="$sb/$UD_REL"

  # CONTROL A -- did the redirect fire? No dirs means godot never ran against THIS sandbox,
  # so an empty file list says nothing at all. Pair it with the exit code: EC!=0 beside
  # dirs=0 is the signature of a bad invocation, not of a clean test.
  dirs=0
  [ -d "$ud" ] && dirs=$(find "$ud" -type d 2>/dev/null | wc -l)

  files=""
  [ -d "$ud" ] && files="$( cd "$ud" && find . -type f 2>/dev/null | grep -vE "$IGNORE_RE" | sort )"

  if [ "$dirs" -eq 0 ]; then
    echo "SKIPPED  $name -- redirect did not fire (EC=$ec). An empty result here is vacuous, not clean." >&2
    rm -rf "$sb" "tmp/pdw_$$.log"
    leaked=1
    continue
  fi

  if [ -n "$files" ]; then
    echo "WRITES   $name  (EC=$ec)"
    echo "$files" | sed 's/^/           /'
    leaked=1
  else
    # CONTROL B -- only needed for a null. Plant a file and confirm the same scan reports it;
    # without this, "clean" and "the scan is broken" are the same output.
    mkdir -p "$ud/autobattle"
    : > "$ud/autobattle/.pdw_probe.json"
    seen="$( cd "$ud" && find . -type f 2>/dev/null | grep -vE "$IGNORE_RE" | wc -l )"
    rm -f "$ud/autobattle/.pdw_probe.json"
    if [ "$seen" -lt 1 ]; then
      echo "BROKEN   $name -- the scan could not see a planted file; this 'clean' proves nothing." >&2
      leaked=1
    else
      echo "clean    $name  (EC=$ec, ${dirs} dirs, detector verified)"
    fi
  fi

  scanned=$((scanned + 1))
  rm -rf "$sb" "tmp/pdw_$$.log"
done

echo "--- scanned $scanned file(s), one process and one virgin sandbox each ---"
exit $leaked
