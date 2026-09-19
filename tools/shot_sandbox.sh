# Sourced by every shot-tool wrapper. ONE owner for the redirect, because four copies of a
# sandbox is four chances to typo the one thing that protects struktured's profile.
#
# WHY THESE WRAPPERS EXIST
# ------------------------
# On 2026-09-18 a shot-tool selftest had no .sh, so it was invoked bare four times
# and godot wrote user://logs/ in struktured's REAL profile. That ring holds five files; his
# 2026-09-17 play session rotated out. @cowir-autogrind then enumerated the population: 12 of
# the 20 .gd tools have no invocation anywhere in the repo, so a bare `godot -s` is the only
# way to run them. Four of those twelve are store-shot tools on this lane.
#
# ⛔ A SCRIPT-LEVEL GUARD CANNOT SUBSTITUTE FOR THIS. Godot opens user://logs/godot.log at
# BOOT, before any script runs -- measured: a script that refuses with EC=2 still costs a log
# slot. The redirect has to be set before the engine starts, which is what a wrapper is for.
#
# ⛔ THE HAZARD IS AN *EMPTY* XDG_DATA_HOME, NOT AN INVALID ONE. I published the opposite
# and @cowir-adhoc falsified it; re-measured here under a fake HOME so nothing was at risk:
#     XDG_DATA_HOME=/nonexistent   -> godot ABORTS (EC=134), creates NOTHING. FAIL-CLOSED.
#     XDG_DATA_HOME=""             -> XDG treats empty as unset; godot writes the REAL
#                                     profile, EC=0, no warning. FAIL-OPEN and silent.
# So an unset-or-empty variable is the killer, which is what `${VAR:-}` or a failed command
# substitution produces. Hence the helper derives the path from $PWD and mkdir -p's it.
#
# ⛔ AND THE INVOCATION THAT ACTUALLY TOOK HIS LOG SLOTS WAS `--check-only`. Measured:
#     HOME=<fake> godot --headless --check-only -s <file>   EC=0, writes logs/godot.log
# A parse check reads as static and is not: it boots the engine, which opens user://logs/
# before anything else. Every bare --check-only I ran tonight cost a slot from a ring of five.
shot_sandbox_run() {
    local _gd="$1"; shift
    [ -f "$_gd" ] || { echo "[shot] no such tool: $_gd" >&2; return 2; }
    command -v xvfb-run >/dev/null || { echo "[shot] xvfb-run missing" >&2; return 3; }
    local _xdg="$PWD/tmp/shot_xdg"
    mkdir -p "$_xdg" || { echo "[shot] cannot create the sandbox at $_xdg" >&2; return 2; }
    local _ec=0
    XDG_DATA_HOME="$_xdg" xvfb-run -a godot --audio-driver Dummy --rendering-driver opengl3 \
        --resolution 1280x720 -s "$_gd" -- "$@" > "tmp/$(basename "$_gd" .gd).log" 2>&1 || _ec=$?
    command grep -aE 'SCREEN|shot-guard|REFUSED|ERROR' "tmp/$(basename "$_gd" .gd).log" || true
    # PROVE THE REDIRECT FIRED rather than inferring it from an unchanged live directory --
    # an unchanged live dir is also what you get when godot never ran (@cowir-battle's tell).
    if [ ! -e "$_xdg/godot" ]; then
        echo "[shot] BLOCKED: the sandbox at $_xdg is empty, so the redirect did not fire." >&2
        echo "       Refusing to report success about a run that may have written elsewhere." >&2
        return 4
    fi
    return "$_ec"
}
