#!/usr/bin/env bash
# sync-and-test.sh - Pull latest from git and optionally launch Godot
# Run on moonshot to sync source and test from source (no CI export needed)
#
# Usage:
#   ./scripts/sync-and-test.sh                  # pull and report
#   ./scripts/sync-and-test.sh --run             # pull and launch godot
#   ./scripts/sync-and-test.sh --watch           # poll for new commits, pull automatically

set -euo pipefail

BRANCH="${BRANCH:-perf-improvements}"
POLL_INTERVAL=30
LAST_SHA_FILE=".last_synced_sha"

sync_latest() {
    local remote_sha local_sha

    git fetch origin "$BRANCH" --quiet
    remote_sha=$(git rev-parse "origin/$BRANCH" 2>/dev/null)
    local_sha=$(git rev-parse HEAD 2>/dev/null)

    if [ "$remote_sha" = "$local_sha" ]; then
        return 2  # Already up to date
    fi

    echo "[sync] New commits found on $BRANCH"
    echo "[sync] Local:  $(git log --oneline -1)"
    git pull --ff-only origin "$BRANCH"
    echo "[sync] Updated to: $(git log --oneline -1)"

    # Show what changed
    echo "[sync] Changes:"
    git log --oneline "${local_sha}..${remote_sha}" | head -10

    echo "$remote_sha" > "$LAST_SHA_FILE"
    return 0
}

run_game() {
    echo "[test] Launching Godot..."
    godot &
    local pid=$!
    echo "[test] Godot PID: $pid"
    echo "[test] Close the game window when done testing"
    wait "$pid" 2>/dev/null || true
}

watch_and_sync() {
    echo "[watch] Watching $BRANCH every ${POLL_INTERVAL}s..."
    while true; do
        if sync_latest; then
            echo "[watch] === NEW CODE AVAILABLE ==="
        fi
        sleep "$POLL_INTERVAL"
    done
}

case "${1:-}" in
    --watch)
        watch_and_sync
        ;;
    --run)
        sync_latest || true
        run_game
        ;;
    *)
        sync_latest
        exit_code=$?
        if [ $exit_code -eq 2 ]; then
            echo "[sync] Already up to date: $(git log --oneline -1)"
        fi
        ;;
esac
