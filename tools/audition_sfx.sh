#!/usr/bin/env bash
# Play the grounded SFX substitutes on a COPY of your own save, in a profile of its own.
#
#   tools/audition_sfx.sh            fresh start: re-copy your save, then launch
#   tools/audition_sfx.sh --keep     launch on whatever the audition profile already holds
#   tools/audition_sfx.sh --prepare  build the profile and stop (no window)
#
# WHAT IT DOES
#   1. Builds an audition profile under this checkout's tmp/audition_xdg. Your real profile is
#      only READ: nothing here writes to it, and the launch below cannot reach it, because godot
#      is given the audition profile as its whole user data root.
#   2. Copies your save_00 (full party, level 11-13, on the W1 overworld, Rat King not yet beaten)
#      into that profile with the party healed to full, so Continue drops you straight into play.
#   3. Copies your display, speed, volume and control settings, never the BYOK/LLM keys, and sets
#      the encounter rate to its maximum so battles come fast. The LLM is off in the audition.
#   4. Launches the game from this checkout, which holds the substitutes.
#
# WHAT TO LISTEN FOR, by group (tell cowir-sfx keep or revert per group)
#   A  Mage Fire / Blizzard / Thunder (and the -ra tiers), Cleric Pray, Mage Channel, Raise, an item cure
#   B  the Bard's songs and Riff
#   C  Advance presses 2 to 5, a refused press on a full queue, the full bank locking and unleashing
#   D  staff hits, a lightning or dark weapon strike, the piano scythe crit, a party member falling
#   Menus are untouched.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
X="$ROOT/tmp/audition_xdg"
APP_REL="godot/app_userdata/Cowardly Irregular"
REAL="$HOME/.local/share/$APP_REL"
MODE="${1:-fresh}"

_die() { echo "[audition] REFUSED: $*" >&2; exit 2; }

## The profile path must be absolute, non-empty, under a tmp/ folder, and not the real profile:
## an EMPTY XDG_DATA_HOME makes godot fall back to the real profile, so every check runs before launch.
case "$X" in
    /*/tmp/audition_xdg) : ;;
    *) _die "audition profile path is not ROOT/tmp/audition_xdg" ;;
esac
mkdir -p "$X"
[ -n "$X" ] && [ -d "$X" ] || _die "audition profile directory missing"
APP="$X/$APP_REL"
mkdir -p "$APP/saves"
[ "$(cd "$APP" && pwd -P)" != "$(cd "$REAL" 2>/dev/null && pwd -P || echo none)" ] || _die "audition profile resolves to the real profile"

if [ "$MODE" != "--keep" ]; then
    [ -f "$REAL/saves/save_00.json" ] || _die "no save_00 in the real profile to copy"
    python3 - "$REAL" "$APP" <<'PY'
import json, sys, shutil
from pathlib import Path
real, app = Path(sys.argv[1]), Path(sys.argv[2])
save = json.loads((real / "saves" / "save_00.json").read_text())
for pc in save.get("party", []):
    pc["current_hp"] = pc.get("max_hp", pc.get("current_hp", 1))
    pc["current_mp"] = pc.get("max_mp", pc.get("current_mp", 0))
    pc["is_alive"] = True
    pc["status_effects"] = []
    pc["status_durations"] = {}
    pc["permanent_injuries"] = pc.get("permanent_injuries", [])
for old in (app / "saves").glob("*.json"):
    old.unlink()
(app / "saves" / "save_00.json").write_text(json.dumps(save, indent=1))
KEEP = ["advance_commits_at_limit", "battle_fx_flags", "battle_speed_index", "color_blind_mode", "dash_always_on",
        "default_battle_speed", "left_right_confirm", "master_volume", "music_volume", "reduce_flashes",
        "screen_shake_enabled", "sfx_volume", "show_controller_overlay", "speed_scale_v2", "speed_scale_v3",
        "speed_scale_v4", "text_size_scale", "text_speed", "version"]
settings = {}
src = real / "settings.json"
if src.exists():
    mine = json.loads(src.read_text())
    settings = {k: mine[k] for k in KEEP if k in mine}
settings.update({"encounter_rate_multiplier": 2.0, "llm_enabled": False, "party_llm_dialogue_enabled": False,
                 "boss_llm_strategy_enabled": False, "llm_rebalance_enabled": False, "llm_custom_backend_enabled": False})
(app / "settings.json").write_text(json.dumps(settings, indent=1))
if (real / "input").is_dir():
    shutil.rmtree(app / "input", ignore_errors=True)
    shutil.copytree(real / "input", app / "input")
print("[audition] profile ready: save_00 healed, %d settings copied, encounter rate 2.0, LLM off" % len(settings))
PY
fi

cd "$ROOT"
if [ ! -f .godot/global_script_class_cache.cfg ]; then
    echo "[audition] first run in this checkout: importing assets (a few minutes, once)"
    XDG_DATA_HOME="$X" godot --headless --import --quit > tmp/audition_import.log 2>&1 || true
fi

[ "$MODE" = "--prepare" ] && { echo "[audition] prepared, not launched"; exit 0; }

## Launch for a human: plain godot in the background, no pipes or redirects (Wayland window rules).
XDG_DATA_HOME="$X" godot &
PID=$!
disown "$PID" 2>/dev/null || true
echo "[audition] launched pid $PID with the audition profile. Pick Continue on the title screen."
