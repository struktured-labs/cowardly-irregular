#!/usr/bin/env bash
# run.sh - Launch Cowardly Irregular
#
# Usage:
#   ./scripts/run.sh              # run from source (requires godot)
#   ./scripts/run.sh --export     # run the exported Linux binary
#   ./scripts/run.sh --fetch      # fetch latest CI build then run it
#   ./scripts/run.sh --sync       # git pull then run from source

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_BIN="$PROJECT_DIR/build/linux/cowardly-irregular.x86_64"

run_from_source() {
    echo "[run] Launching from source..."
    cd "$PROJECT_DIR"
    godot &
    local pid=$!
    echo "[run] Godot PID: $pid"
    wait "$pid" 2>/dev/null || true
}

run_export() {
    if [ ! -f "$BUILD_BIN" ]; then
        echo "[run] No export binary found at: $BUILD_BIN"
        echo "[run] Run './scripts/fetch-build.sh' first, or use '--fetch'"
        exit 1
    fi
    echo "[run] Launching exported binary..."
    "$BUILD_BIN" &
    local pid=$!
    echo "[run] PID: $pid"
    wait "$pid" 2>/dev/null || true
}

case "${1:-}" in
    --export)
        run_export
        ;;
    --fetch)
        "$SCRIPT_DIR/fetch-build.sh"
        run_export
        ;;
    --sync)
        "$SCRIPT_DIR/sync-and-test.sh"
        run_from_source
        ;;
    *)
        run_from_source
        ;;
esac
