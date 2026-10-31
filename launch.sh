#!/usr/bin/env bash
# Launch Cowardly Irregular for human play
# Rules: no pipes, no redirects, no setsid — plain `godot &` from project dir
# Wayland/KDE requires this exact pattern or the window won't appear
#
# 2026-07-01 post-mortem hardening (gray-void new-game freeze):
# 1. `pkill -x godot` (exact name), NOT `pkill -f godot` — the -f form
#    matches ANY cmdline containing "godot", including the shell running
#    this very script, killing it mid-flight.
# 3. Kill BY VERIFIED CWD, never a bare `pkill -x godot` — that is SIGKILL to every
#    godot on a ~30-agent box, including other lanes' gate runs and struktured's live
#    session. Restarting his game unasked is a standing prohibition.
# 2. Stale-class-cache guard: new `class_name` scripts merged since the
#    last import make dependent scripts fail to parse at runtime → the
#    game boots into an empty gray viewport with live input. If any
#    class_name .gd file is newer than the import cache, run a headless
#    --import first.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Kill any existing Godot FROM THIS PROJECT DIR ONLY (post-mortem note 1 + note 3).
# `pkill -9 -x godot` is SIGKILL to every godot on the box: measured 2026-09-12, three
# processes, two of them other lanes' live test runs and one struktured's game.
KILLED=0
for p in $(pgrep -x godot 2>/dev/null); do
    [ "$(readlink /proc/$p/cwd 2>/dev/null)" = "$SCRIPT_DIR" ] || continue
    kill -9 "$p" 2>/dev/null && KILLED=$((KILLED+1))
done
[ "$KILLED" -gt 0 ] && sleep 2

# Stale-class-cache guard (post-mortem note 2)
# SANDBOXED PREWARM. `--import` is EDITOR-CLASS -- it carries the same E flag as --editor, and
# --headless means no window, NOT "not the editor" -- so it writes .recovery_mode_lock and a
# multi-MB editor shader cache into whichever profile is active. Unsandboxed that is HIS profile,
# seconds before his game starts. The import CACHE lives in res://.godot, inside the project, so
# relocating the data root costs the prewarm nothing: same reasoning, same idiom and same path as
# tools/deploy_desktop.sh:170 / deploy_web.sh / publish_all.sh, which were fixed 2026-09-16.
# PER-COMMAND PREFIX, NEVER `export`. The launch below must reach his REAL user:// -- that is the
# one documented case where sandboxing would itself be the bug, and an export here would send his
# saves to a gitignored temp dir.
CACHE=".godot/global_script_class_cache.cfg"
mkdir -p tmp/prewarm_xdg
if [ -f "$CACHE" ]; then
    NEWER=$(find src -name '*.gd' -newer "$CACHE" -exec grep -l '^class_name ' {} + 2>/dev/null | head -1)
    if [ -n "$NEWER" ]; then
        echo "class_name script(s) newer than import cache (e.g. $NEWER) — reimporting..."
        XDG_DATA_HOME="$PWD/tmp/prewarm_xdg" godot --headless --import > /dev/null 2>&1 || true
        sleep 1
    fi
else
    echo "No import cache found — running first import..."
    XDG_DATA_HOME="$PWD/tmp/prewarm_xdg" godot --headless --import > /dev/null 2>&1 || true
    sleep 1
fi

# Launch — MUST be bare `godot &` with no pipes/redirects
godot &

sleep 2
if pgrep -x godot > /dev/null 2>&1; then
    echo "Godot launched (PID: $(pgrep -x godot | head -1))"
else
    echo "ERROR: Godot failed to start"
    exit 1
fi
