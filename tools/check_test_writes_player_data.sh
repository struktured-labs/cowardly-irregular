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
#          tools/check_test_writes_player_data.sh --selftest      # no live defect required
#          tools/check_test_writes_player_data.sh --all                # every test file; no corpus decision
#          tools/check_test_writes_player_data.sh --all <substring>    # FILENAME match -- NOT lane coverage
#          tools/check_test_writes_player_data.sh --all-autogrind        # alias, kept
# Exit:    0 nothing written · 1 a test left player data · 2 bad invocation

set -u
cd "$(dirname "$0")/.." || exit 2

UD_REL='godot/app_userdata/Cowardly Irregular'
# Engine artifacts, not player data. logs/ is godot's own; shader_cache is a build artifact.
# grep, not sed: the pattern contains `/`, which terminates sed's `/.../d` address.
# That bug emptied the file list and the plant control caught it -- kept as the reason.
IGNORE_RE='^\./(logs/|shader_cache/)'

# ONE definition of "what counts as player data", used by the real path AND by --selftest.
# If these diverged, the selftest would certify a scanner the tool does not use.
scan_ud() {  # $1 = a user:// root; prints the player-data files under it, one per line
  [ -d "$1" ] || return 0
  ( cd "$1" && find . -type f 2>/dev/null | grep -vE "$IGNORE_RE" | sort )
}

# ⛔ THE LEAK-DIRECTION CONTROL HAS A SHELF LIFE MEASURED IN FOLDS (@cowir-music, 2026-09-17).
# Pointing it at a real leaker proves the WRITES path -- until someone fixes that leaker, and then
# the strongest half of the self-test is unreproducible by anyone. So it is fabricated here instead:
# a synthetic user:// tree exercises both directions forever, with no live defect required.
if [ "${1:-}" = "--selftest" ]; then
  t="$PWD/tmp/pdw_selftest_$$"; rm -rf "$t"; mkdir -p "$t/autobattle" "$t/logs"
  : > "$t/logs/godot.log"                      # engine noise -- MUST be ignored
  echo '{}' > "$t/autobattle/profiles.json"    # player data -- MUST be reported
  got="$(scan_ud "$t" | tr '\n' ' ')"
  rm -rf "$t"
  fail=0
  case "$got" in *autobattle/profiles.json*) ;; *) echo "SELFTEST FAIL: player data not reported (got: '$got')" >&2; fail=1;; esac
  case "$got" in *logs/godot.log*) echo "SELFTEST FAIL: engine log counted as player data" >&2; fail=1;; *) ;; esac
  t2="$PWD/tmp/pdw_selftest2_$$"; rm -rf "$t2"; mkdir -p "$t2/autobattle"; : > "$t2/logs_placeholder"
  rm -f "$t2/logs_placeholder"
  [ -n "$(scan_ud "$t2")" ] && { echo "SELFTEST FAIL: an empty tree reported files" >&2; fail=1; }
  rm -rf "$t2"
  [ ! -d "/nonexistent_$$" ] && [ -n "$(scan_ud "/nonexistent_$$")" ] && { echo "SELFTEST FAIL: a missing root reported files" >&2; fail=1; }
  [ "$fail" -eq 0 ] && echo "selftest OK -- reports player data, ignores engine logs, empty is empty"
  exit $fail
fi

[ "$#" -ge 1 ] || { echo "usage: $0 <test-name> [...]  |  --all <substring>  |  --selftest" >&2; exit 2; }

# Selection. `--all <substring>` is the neutral form -- @cowir-battle asked for --all-autobattle
# and a per-lane flag list is the hand-listed corpus this whole exercise is about. The detector
# (scan_ud) is lane-agnostic already; only the REACH was autogrind-shaped.
NAMES=()
case "${1:-}" in
  --all-autogrind) set -- --all autogrind ;;   # kept: the original spelling, now an alias
esac
# ⛔ `--all <substring>` SELECTS BY FILENAME, WHICH IS THE CORPUS SHAPE THIS TOOL EXISTS TO
# REPLACE (@cowir-battle, 2026-09-17). `--all autobattle` would have missed FOUR of the seven
# writers fixed in that lane -- rule_composer_overlay (named for the composer),
# escape_always_backs_out (named for the KEY), job_profiles and job_system_regression (which
# name nothing and reach the autoload through Combatant). The misses are not random: the three
# it DOES select are the three that say "autobattle" somewhere obvious, and the four it misses
# are the four that defeated every name-based instrument. So the substring form says out loud
# what its corpus is, and bare `--all` is the only selector with no corpus decision in it.
if [ "${1:-}" = "--all" ]; then
  pat="${2:-}"
  for f in test/unit/test_*"$pat"*.gd; do
    [ -e "$f" ] || { echo "$0: no test file matches '*${pat}*'" >&2; exit 2; }
    n="${f##*/test_}"; NAMES+=("${n%.gd}")
  done
  total=$(ls test/unit/test_*.gd 2>/dev/null | wc -l)
  if [ -z "$pat" ]; then
    echo "--- $0: ALL ${#NAMES[@]} test file(s). No corpus decision. ---" >&2
  else
    echo "--- $0: ${#NAMES[@]} of $total file(s) whose FILENAME contains '$pat'." >&2
    echo "    ⛔ THIS IS A FILENAME CORPUS, NOT LANE COVERAGE. A test that reaches your writer" >&2
    echo "       without naming it is NOT in this set -- that is how today's hardest four hid." >&2
    echo "       For a claim about a lane, use bare --all and filter the output. ---" >&2
  fi
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

  files="$(scan_ud "$ud")"

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
    seen="$(scan_ud "$ud" | wc -l)"
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
