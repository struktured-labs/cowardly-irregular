#!/usr/bin/env bash
# Parse-check GDScript files in a sandboxed user://.
#
# WHY THIS EXISTS
# ---------------
# `godot --headless --check-only -s <file>` READS AS STATIC AND IS NOT. It does not execute
# the script -- it boots the engine to parse it, and the engine opens user://logs/ before
# anything else. Measured 2026-09-18 under a fake HOME:
#     HOME=<fake> godot --headless --check-only -s <file>   EC=0, writes logs/godot.log
# That ring holds FIVE files. I ran this command bare after every .gd edit for a whole
# session and rotated away struktured's own play logs while believing I was touching nothing.
# @cowir-adhoc measured the same for a bare `--quit`, which creates saves/ and logs/ too --
# so it is not this flag, it is any invocation that opens the project.
#
# ⛔ AN EMPTY XDG_DATA_HOME IS THE FAIL-OPEN ONE, NOT AN INVALID ONE (@cowir-adhoc, and I
# published it backwards first):
#     XDG_DATA_HOME=/nonexistent   godot ABORTS EC=134, creates NOTHING   FAIL-CLOSED
#     XDG_DATA_HOME=""             treated as UNSET -> the REAL profile, EC=0, silent
# Empty is what `${VAR:-}` or a failed `mktemp` yields, so the path here is derived from
# $PWD and the directory is created before use -- never accepted from the caller.
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$#" -gt 0 ] || { echo "usage: tools/gd_check.sh <file.gd> [more.gd ...]" >&2; exit 2; }
_XDG="$PWD/tmp/gd_check_xdg"
mkdir -p "$_XDG" || { echo "[gd-check] cannot create the sandbox at $_XDG" >&2; exit 2; }
_FAIL=0
for _f in "$@"; do
    if [ ! -f "$_f" ]; then
        echo "[gd-check] $_f: no such file" >&2; _FAIL=1; continue
    fi
    _OUT=$(XDG_DATA_HOME="$_XDG" timeout 180 godot --headless --check-only -s "$_f" 2>&1) || true
    if printf '%s\n' "$_OUT" | command grep -aqE 'SCRIPT ERROR|Parse Error'; then
        printf '  %-44s PARSE ERROR\n' "$_f"
        printf '%s\n' "$_OUT" | command grep -aE 'SCRIPT ERROR|Parse Error' | head -3 | sed 's/^/      /'
        _FAIL=1
    else
        printf '  %-44s ok\n' "$_f"
    fi
done
# PROVE THE REDIRECT FIRED rather than inferring it from an unchanged live directory -- an
# unchanged live dir is also what you get when godot never ran (@cowir-battle's tell).
if [ ! -e "$_XDG/godot" ]; then
    echo "[gd-check] BLOCKED: the sandbox at $_XDG is empty, so the redirect did not fire." >&2
    echo "        Refusing to report a clean parse from a run that may have written elsewhere." >&2
    exit 4
fi
exit "$_FAIL"
