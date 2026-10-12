#!/usr/bin/env bash
# pre_ready_guards.sh — run every guard whose corpus is the TEST TREE. Run it before READY whenever
# your branch ADDS a test file: a new file has no symbol, so a symbol-derived corpus cannot contain
# the guards that judge it (the first .654 gate red on exactly that, 2026-10-12).
# The set is DERIVED, never listed: four lanes hand-curated four different lists in one hour.
# Exit codes are run_tests.sh's own, plus 2 when the derivation finds implausibly few guards.
set -uo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
MIN_GUARDS=10

mapfile -t FILES < <(grep -rlE 'res://test/unit"|res://test/unit/"|res://test"|dir_contents|get_files\(\)' \
  test/unit --include='test_*.gd' | xargs -r grep -lE '"res://test' | sort)

if [ "${#FILES[@]}" -lt "$MIN_GUARDS" ]; then
  echo "pre_ready_guards: derived ${#FILES[@]} guard file(s), expected at least $MIN_GUARDS — the scan matched too little, refusing to call that a pass" >&2
  exit 2
fi

echo "pre_ready_guards: ${#FILES[@]} test-tree guards"
exec tools/run_tests.sh "${FILES[@]/#/res://}"
