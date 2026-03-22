#!/usr/bin/env bash
# Launch Cowardly Irregular for human play
# Rules: no pipes, no redirects, no setsid — plain `godot &` from project dir
# Wayland/KDE requires this exact pattern or the window won't appear

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Kill any existing Godot
pkill -f godot 2>/dev/null || true
sleep 2

# Launch — MUST be bare `godot &` with no pipes/redirects
godot &

sleep 1
if pgrep -f godot > /dev/null 2>&1; then
    echo "Godot launched (PID: $(pgrep -f godot | head -1))"
else
    echo "ERROR: Godot failed to start"
    exit 1
fi
