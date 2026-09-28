#!/usr/bin/env bash
# web_smoke_reason.sh <deploy_web_smoke.log> — ONE line naming why the web smoke failed, read from
# the smoke's own log, for deploy_web.sh's BLOCKED message.
#
# WHY: every web-smoke failure used to be reported as "web build failed to boot in chromium TWICE".
# On v3.33.488-alpha the build booted fine, rendered the menu, and failed at stage 4 (his 8BitDo was
# driving the gate's game: the Save walk landed in LENSES). The label sent diagnosis to boot first.
# The smoke already knows which stage failed (web_smoke.mjs prints "stageN: ..." fatals); this
# carries that into the line a reader actually sees.
#
#   did NOT BOOT: ...                  the engine banner never appeared
#   BOOTED, then failed at stageN: ... the build ran; a later stage refused
#   fatal console|pageerror error: ... a fatal JS/engine error (boot state not implied)
#   no verdict in the log ...          the smoke died before printing FAIL/PASS
#
# Usage: tools/web_smoke_reason.sh <log>     prints the line, always exits 0
#        tools/web_smoke_reason.sh --selftest
set -uo pipefail

reason() {
    local log="$1" first n more=""
    if [ ! -s "$log" ]; then
        echo "no smoke log at ${log} (missing or empty): the smoke never wrote one"; return 0
    fi
    # `command grep -a`: a log is text we did not write; never let a stray byte make grep go silent.
    if command grep -a -q 'engine banner never appeared' "$log"; then
        echo "did NOT BOOT: $(command grep -a -o 'engine banner never appeared.*' "$log" | head -1)"; return 0
    fi
    n=$(command grep -a -o 'FAIL — [0-9]* fatal' "$log" | head -1 | tr -dc '0-9')
    if [ -n "$n" ]; then
        first=$(command grep -a -A1 'FAIL — [0-9]* fatal' "$log" | sed -n '2p' | sed 's/^ *//')
        [ "$n" -gt 1 ] && more=" (+$((n - 1)) more fatal(s))"
        case "$first" in
            stage*)                echo "BOOTED, then failed at ${first%%:*}: ${first#*: }" ;;
            console:*|pageerror:*) echo "fatal ${first%%:*} error: ${first#*: }" ;;
            "")                    echo "FAIL with ${n} fatal(s) but no fatal line followed" ;;
            *)                     echo "$first" ;;
        esac | cut -c1-220 | sed "s|\$|${more}|"
        return 0
    fi
    if command grep -a -q 'WEB-SMOKE\] PASS' "$log"; then
        echo "the log says PASS: the failure came from outside the smoke's verdict"; return 0
    fi
    echo "no verdict in the log: the smoke died before printing FAIL or PASS"
}

if [ "${1:-}" != "--selftest" ]; then
    [ $# -eq 1 ] || { echo "usage: $0 <log> | --selftest" >&2; exit 2; }
    reason "$1"; exit 0
fi

# ── selftest: every class, both directions, with the exact lines web_smoke.mjs prints ──────────
_ROOT="$(cd "$(dirname "$0")/.." && pwd)"; mkdir -p "$_ROOT/tmp"
T=$(mktemp -d "$_ROOT/tmp/wsr.XXXXXX"); trap 'rm -rf "$T"' EXIT   # repo tmp/, never /tmp
pass=0; fail=0
chk() {  # label fixture-lines... ; expected substring is $EXPECT
    local label="$1"; shift
    printf '%s\n' "$@" > "$T/log"
    local got; got=$(reason "$T/log")
    case "$got" in
        *"$EXPECT"*) pass=$((pass + 1)); printf '  ok    %-44s %s\n' "$label" "$got" ;;
        *)           fail=$((fail + 1)); printf '  FAIL  %-44s got: %s / want: %s\n' "$label" "$got" "$EXPECT" ;;
    esac
}
EXPECT="BOOTED, then failed at stage4: no \"Game saved" \
chk "the .488 shape: stage 4 after a boot" \
    '[WEB-SMOKE] host pads: hidden (getGamepads -> [])' '[WEB-SMOKE] Save is row 17 (derived from OverworldMenu.gd)' \
    '[WEB-SMOKE] FAIL — 1 fatal(s):' '  stage4: no "Game saved to slot" console line after 17 ArrowDowns'
EXPECT="did NOT BOOT: engine banner never appeared within 45000ms" \
chk "a real boot failure still says boot" '[WEB-SMOKE] FAIL — engine banner never appeared within 45000ms'
EXPECT="fatal pageerror error: RuntimeError" \
chk "a fatal page error names itself" '[WEB-SMOKE] FAIL — 1 fatal(s):' '  pageerror: RuntimeError: unreachable'
EXPECT="(+2 more fatal(s))" \
chk "several fatals: the first, plus a count" '[WEB-SMOKE] FAIL — 3 fatal(s):' '  stage3: overworld menu never opened' '  stage4: x' '  stage4b: y'
EXPECT="no verdict in the log" \
chk "a smoke that died mid-run" '[WEB-SMOKE] Save is row 17 (derived from OverworldMenu.gd)'
EXPECT="the log says PASS" \
chk "a PASS log is not blamed" '[WEB-SMOKE] PASS — boot + gameplay'
rm -f "$T/log"; got=$(reason "$T/log")
case "$got" in *"never wrote one"*) pass=$((pass + 1)); echo "  ok    missing log                                  $got" ;;
               *) fail=$((fail + 1)); echo "  FAIL  missing log: $got" ;; esac
echo "web_smoke_reason selftest: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
