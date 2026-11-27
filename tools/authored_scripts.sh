#!/usr/bin/env bash
# authored_scripts.sh [dir] — the number of SCRIPTS GUT will report in Totals for test/unit:
# every test_*.gd under the dir, plus every inner `class Test* extends GutTest` in them,
# which GUT runs and counts as its own script. The one source for Scripts == authored.
set -u
dir="${1:-test/unit}"
# RECURSIVE on purpose: GUT's -gdir is not, so a test file in a subdirectory is counted and never run, and Scripts != authored names it.
files="$(find "$dir" -name 'test_*.gd' -type f | wc -l)"
inner="$({ /usr/bin/grep -rhcE --include='test_*.gd' '^class Test[A-Za-z0-9_]* extends (GutTest|"res://addons/gut/test.gd")' "$dir" || true; } | awk '{s+=$1} END {print s+0}')"
case "${2:-}" in
  --explain) echo "$((files + inner)) = $files files + $inner inner Test classes" ;;
  *) echo "$((files + inner))" ;;
esac
