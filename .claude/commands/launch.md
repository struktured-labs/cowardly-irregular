Launch the game for human play.

CRITICAL RULES — violating these makes the window invisible on Wayland/KDE:
1. MUST run from the project directory (where project.godot lives)
2. MUST use bare `godot &` — NO pipes, NO redirects, NO setsid, NO --path flag

🛑 NEVER `pkill -f godot` / `pgrep -f godot`. The `-f` form matches any command
line CONTAINING the string, not the godot process. Measured 2026-09-12 on this
box, `pgrep -f godot` returned 4 processes and only ONE was godot: another
lane's watcher shell, the shell running the check itself, and struktured's
live game. `launch.sh`'s own 2026-07-01 post-mortem says the same thing —
"including the shell running this very script, killing it mid-flight" — and
this file kept the banned form for two months after that landed.

`pgrep -f` also SELF-MATCHES, so it can never report failure: measured with
zero headless godot running, `pgrep -f "godot --headless"` still said RUNNING.
A verification step that cannot fail is worse than no verification.

Use `./launch.sh` from the project root. It is the maintained path and already
does all of the below correctly.

If you must do it by hand:
1. Find his running instance: `pgrep -x godot` (exact process NAME)
2. 🛑 Do NOT kill it without being asked. ~30 agents share this box, `-x`
   still matches EVERY godot on it — other lanes' gate runs and his live
   session alike. If a restart was actually requested, kill the ONE pid you
   verified: `readlink /proc/<pid>/cwd` and `readlink /proc/<pid>/exe` first.
3. Launch: `godot &`
4. Verify: `sleep 1 && pgrep -x godot`
5. Report the PID to the user
