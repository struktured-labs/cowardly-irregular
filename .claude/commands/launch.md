Launch the game for human play.

CRITICAL RULES — violating these makes the window invisible on Wayland/KDE:
1. MUST run from the project directory (where project.godot lives)
2. MUST use bare `godot &` — NO pipes, NO redirects, NO setsid, NO --path flag
3. Kill existing godot first with `pkill -f godot 2>/dev/null || true` then `sleep 2`
4. Verify with `pgrep -f godot`

Steps:
1. Run: `pkill -f godot 2>/dev/null || true`
2. Wait: `sleep 2`
3. Launch: `godot &`
4. Verify: `sleep 1 && pgrep -f godot`
5. Report PID to user

Alternatively, run `./launch.sh` from the project root which does all of the above.
