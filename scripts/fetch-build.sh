#!/usr/bin/env bash
# fetch-build.sh - Download latest CI build artifact from GitHub Actions
# Run on moonshot (or any test machine) to get the latest exported build
#
# Usage:
#   ./scripts/fetch-build.sh                    # latest from perf-improvements
#   ./scripts/fetch-build.sh main               # latest from main
#   ./scripts/fetch-build.sh --watch             # poll every 60s for new builds

set -euo pipefail

REPO="struktured-labs/cowardly-irregular"
BRANCH="${1:-perf-improvements}"
BUILD_DIR="build/linux"
POLL_INTERVAL=60
LAST_RUN_FILE=".last_fetched_run"

fetch_latest() {
    local run_info
    run_info=$(gh run list -R "$REPO" -b "$BRANCH" -w "Build & Export" \
        --status success -L 1 --json databaseId,headSha,createdAt \
        -q '.[0]' 2>/dev/null)

    if [ -z "$run_info" ] || [ "$run_info" = "null" ]; then
        echo "[fetch] No successful builds found for branch: $BRANCH"
        return 1
    fi

    local run_id sha created_at
    run_id=$(echo "$run_info" | jq -r '.databaseId')
    sha=$(echo "$run_info" | jq -r '.headSha' | head -c 8)
    created_at=$(echo "$run_info" | jq -r '.createdAt')

    # Check if we already have this build
    if [ -f "$LAST_RUN_FILE" ] && [ "$(cat "$LAST_RUN_FILE")" = "$run_id" ]; then
        return 2  # Already fetched
    fi

    echo "[fetch] New build found: run=$run_id sha=$sha date=$created_at"
    echo "[fetch] Downloading artifact..."

    mkdir -p "$BUILD_DIR"
    # gh run download puts files into a subdirectory named after the artifact
    gh run download "$run_id" -R "$REPO" -n "linux-build-${sha}*" -D "$BUILD_DIR" 2>/dev/null \
        || gh run download "$run_id" -R "$REPO" -D "$BUILD_DIR" 2>/dev/null

    # Make executable
    chmod +x "$BUILD_DIR"/*.x86_64 2>/dev/null || true

    echo "$run_id" > "$LAST_RUN_FILE"
    echo "[fetch] Build ready at: $BUILD_DIR/"
    echo "[fetch] Run with: ./$BUILD_DIR/cowardly-irregular.x86_64"
    return 0
}

watch_builds() {
    echo "[watch] Polling $REPO ($BRANCH) every ${POLL_INTERVAL}s for new builds..."
    while true; do
        if fetch_latest; then
            echo "[watch] === NEW BUILD AVAILABLE ==="
        fi
        sleep "$POLL_INTERVAL"
    done
}

if [ "${1:-}" = "--watch" ]; then
    BRANCH="${2:-perf-improvements}"
    watch_builds
else
    fetch_latest
    exit_code=$?
    if [ $exit_code -eq 2 ]; then
        echo "[fetch] Already up to date."
    fi
fi
