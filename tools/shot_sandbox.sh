# Sourced by every shot-tool wrapper. ONE owner for the redirect, because four copies of a
# sandbox is four chances to typo the one thing that protects struktured's profile.
#
# WHY THESE WRAPPERS EXIST
# ------------------------
# On 2026-09-18 tools/shot_guard_selftest.gd had no .sh, so it was invoked bare four times
# and godot wrote user://logs/ in struktured's REAL profile. That ring holds five files; his
# 2026-09-17 play session rotated out. @cowir-autogrind then enumerated the population: 12 of
# the 20 .gd tools have no invocation anywhere in the repo, so a bare `godot -s` is the only
# way to run them. Four of those twelve are store-shot tools on this lane.
#
# ⛔ A SCRIPT-LEVEL GUARD CANNOT SUBSTITUTE FOR THIS. Godot opens user://logs/godot.log at
# BOOT, before any script runs -- measured: a script that refuses with EC=2 still costs a log
# slot. The redirect has to be set before the engine starts, which is what a wrapper is for.
#
# ⛔ AND AN INVALID PATH IS WORSE THAN NONE: `XDG_DATA_HOME=/nonexistent` makes godot ABORT
# (EC=134) and fall back to the DEFAULT user:// -- his profile -- while you believe you are
# sandboxed. Measured, at the cost of two more of his log slots. Hence mkdir -p, and a path
# derived from $PWD rather than typed.
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
