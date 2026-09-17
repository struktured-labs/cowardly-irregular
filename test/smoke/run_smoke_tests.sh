#!/bin/bash
# Runs the battle smoke test headlessly.
# Usage: bash test/smoke/run_smoke_tests.sh
# Exit code: 0 = all pass, 1 = any failure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$PROJECT_DIR"

echo "[SMOKE] Running battle smoke tests (headless)..."
# ⛔ SANDBOXED. This ran `godot --headless` with no redirect, so every invocation wrote
# struktured's real user:// — logs, .recovery_mode_lock, and whatever the smoke script itself
# persists. It sat outside tools/check_user_data_sandboxed.py's corpus (a `tools/*.sh` glob),
# so the guard reported 16 of 16 sandboxed while this one was not; pointed at the file, its
# predicate flagged it immediately. Corpus, not detector.
#
# A throwaway data root costs nothing here: the smoke test reads res:// and asserts on battle
# state, so it has no legitimate reason to touch a real profile.
SMOKE_XDG="${SMOKE_XDG:-$PROJECT_DIR/tmp/smoke_xdg}"
mkdir -p "$SMOKE_XDG"
XDG_DATA_HOME="$SMOKE_XDG" godot --headless -s test/smoke/test_battle_smoke.gd 2>&1
RESULT=$?
exit $RESULT
