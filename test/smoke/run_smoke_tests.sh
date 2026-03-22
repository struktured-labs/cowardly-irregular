#!/bin/bash
# Runs the battle smoke test headlessly.
# Usage: bash test/smoke/run_smoke_tests.sh
# Exit code: 0 = all pass, 1 = any failure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$PROJECT_DIR"

echo "[SMOKE] Running battle smoke tests (headless)..."
godot --headless -s test/smoke/test_battle_smoke.gd 2>&1
RESULT=$?
exit $RESULT
