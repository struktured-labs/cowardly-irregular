#!/usr/bin/env bash
# authored_scripts.sh [dir] — the number of SCRIPTS GUT will report in Totals for test/unit:
# every test_*.gd directly in the dir, plus every inner `class Test* extends GutTest` in them,
# which GUT runs and counts as its own script. The one source for Scripts == authored.
set -u
dir="${1:-test/unit}"
files="$(find "$dir" -maxdepth 1 -name 'test_*.gd' -type f | wc -l)"
inner="$({ /usr/bin/grep -hcE '^class Test[A-Za-z0-9_]* extends (GutTest|"res://addons/gut/test.gd")' "$dir"/test_*.gd || true; } | awk '{s+=$1} END {print s+0}')"
case "${2:-}" in
  --explain) echo "$((files + inner)) = $files files + $inner inner Test classes" ;;
  *) echo "$((files + inner))" ;;
esac
