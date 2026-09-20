#!/usr/bin/env bash
# Is struktured capturing right now? DELEGATES to publish_detached.sh --check, which is the
# gate that actually holds a publish. This file answers the question; it no longer decides it.
#
# WHY THIS STOPPED HAVING ITS OWN LOGIC
# -------------------------------------
# It used to hand-roll three signals (mkv growth, OBS log markers, muxer process) and OR them.
# Nothing ever called it -- `grep -rn capture_is_live` across the repo finds zero callers -- so
# it was a SECOND, WEAKER implementation of a question publish_detached.sh already answers, and
# it misled this lane twice on 2026-09-19/20:
#
#   1. Its header promised "Never reports idle on a signal it could not read" and its verdict
#      was `[ "$live" = 1 ]` -- a pure OR with no notion of readability. With every signal
#      unreadable it printed `idle`, which is FAIL-OPEN onto a live capture. publish_detached's
#      _obs_busy fails CLOSED in exactly those cases ("its output state is unknown" -> HOLD),
#      so the correct behaviour already existed one file over.
#   2. Its mkv probe cannot tell "he is not recording" from "he records somewhere else", and
#      labels both `cannot read this signal`. After 833 GB moved off ~/Videos it printed that
#      on every run, which nearly had me report a working courtesy gate as broken.
#
# ⚠️ THE MEASUREMENTS THE OLD SIGNALS CARRIED, KEPT BECAUSE THEY WERE REAL AND ARE NOT
# RECOVERABLE FROM THE NEW CODE:
#   - OBS's max flush gap is 4.25s (gaps 4.00/4.25/4.25/4.00 sampled at 0.25s over 20s), so a
#     growth window must exceed it; a 3s window read 0 B on a LIVE capture in 1 of 5 samples.
#     publish_detached's _capture_growth owns this now.
#   - The mkv grows in ~382 KB quanta, so a short delta is a FLUSH COUNT, not a rate.
#   - `obs` alone is NOT evidence of recording; `obs-ffmpeg-mux` exists only while a file is
#     written. That narrowing is already in publish_detached's OWNER_PROCS.
#
# ⛔ AND THE SELF-MATCH HAZARD THAT COST AN HOUR: the old muxer probe excluded `$$` but not its
# ANCESTORS, so running it in a shell whose own command line contained the muxer's name made it
# report `mux alive` against a capture that had stopped hours earlier. Delegation removes the
# probe from this file entirely; publish_detached uses `pgrep -x`, which matches the process
# NAME and cannot match a wrapper's arguments.
#
# Usage:  tools/capture_is_live.sh              one line, plus the delegate's own reasons
#         tools/capture_is_live.sh --selftest
# Exit:   0 CAPTURING · 1 not capturing · 2 UNKNOWN -- the delegate could not be consulted.
#         2 is not "idle". A caller that treats it as idle reintroduces the fail-open above.
set -uo pipefail

PUBDET="${CAPTURE_PUBDET:-$(dirname "$0")/publish_detached.sh}"

_selftest() {
    local dir pass=0 fail=0
    dir="$(mktemp -d "${TMPDIR:-tmp}/capture_selftest.XXXXXX")" || return 2
    trap 'rm -rf "$dir"' RETURN
    run() {  # name, stub-body, stub-exit, want-exit, want-regex
        local name="$1" body="$2" sec="$3" want="$4" re="$5"
        printf '#!/usr/bin/env bash\n%s\nexit %s\n' "$body" "$sec" > "$dir/stub.sh"
        chmod +x "$dir/stub.sh"
        local out ec=0
        out=$(CAPTURE_PUBDET="$dir/stub.sh" bash "$SELF" 2>&1) || ec=$?
        local why=""
        [ "$ec" = "$want" ] || why="exit ${ec}, wanted ${want}"
        [ -z "$why" ] && { printf '%s' "$out" | command grep -qE -e "$re" || why="output lacks /${re}/"; }
        if [ -n "$why" ]; then fail=$((fail+1)); echo "  FAIL  ${name}: ${why}"; printf '%s\n' "$out" | sed 's/^/        | /'
        else pass=$((pass+1)); echo "  ok    ${name}"; fi
    }
    echo "[capture] selftest — the verdict comes from the delegate, both directions"
    run "OBS live -> CAPTURING"       'echo "[check] HELD: OBS is live: Recording"' 2 0 "CAPTURING"
    run "  ...and names what is live" 'echo "[check] HELD: OBS is live: Recording"' 2 0 "Recording"
    run "CLEAR -> not capturing"      'echo "[check] CLEAR: a publish would start now."' 0 1 "not capturing"
    run "OBS open, not recording"     'echo "[check] OBS is open but not recording, streaming or holding a replay buffer."
echo "[check] CLEAR: a publish would start now."' 0 1 "not capturing"
    # A HOLD THAT IS NOT A CAPTURE MUST NOT READ AS ONE -- quartus is his FPGA toolchain.
    run "held by a non-OBS process"   'echo "[check] HELD: 1 process(es) matching '"'"'quartus'"'"' are running."' 2 1 "not capturing, but a publish would be HELD"
    # THE DELEGATE HOLDS AND SAYS "unknown" -- OBS up, log missing or stale. Not "idle".
    run "an 'unknown output state' hold is UNKNOWN" 'echo "[check] HELD: OBS is running and has no log under /x, so its output state is unknown"' 2 2 "UNKNOWN"
    run "  ...and refuses to call it idle"          'echo "[check] HELD: OBS is running but its newest log predates it (a.txt), so its output state is unknown"' 2 2 "NOT idle"
    echo "[capture] selftest — it FAILS CLOSED when the delegate cannot be consulted"
    run "delegate exits 127"          'echo "boom" >&2' 127 2 "UNKNOWN"
    run "  ...and says why"           'echo "boom" >&2' 127 2 "could not be consulted"
    local out ec=0
    out=$(CAPTURE_PUBDET="$dir/nope.sh" bash "$SELF" 2>&1) || ec=$?
    if [ "$ec" = 2 ] && printf '%s' "$out" | command grep -q UNKNOWN; then
        pass=$((pass+1)); echo "  ok    a MISSING delegate is UNKNOWN, never idle"
    else fail=$((fail+1)); echo "  FAIL  a MISSING delegate is UNKNOWN, never idle (ec=${ec})"; fi
    echo "[capture] selftest: ${pass} passed, ${fail} failed"
    [ "$fail" -eq 0 ]
}
SELF="${BASH_SOURCE[0]}"
[ "${1:-}" = "--selftest" ] && { _selftest; exit $?; }

[ -x "$PUBDET" ] || {
    echo "capture: UNKNOWN — the delegate could not be consulted (${PUBDET} missing or not executable)." >&2
    echo "  This is NOT idle. Refusing to guess at a capture that may be live." >&2
    exit 2; }

_out="$("$PUBDET" --check 2>&1)"; _ec=$?
case "$_ec" in
    0|2) ;;
    *)  echo "capture: UNKNOWN — the delegate could not be consulted (exit ${_ec})." >&2
        printf '%s\n' "$_out" | tail -3 | sed 's/^/  | /' >&2
        echo "  This is NOT idle. Refusing to guess at a capture that may be live." >&2
        exit 2 ;;
esac

if printf '%s' "$_out" | command grep -q 'OBS is live:'; then
    printf 'capture: CAPTURING  [%s]\n' "$(printf '%s' "$_out" | command grep -o 'OBS is live:.*' | head -1)"
    printf '%s\n' "$_out" | command grep -E 'corroborated|ANOMALY' | sed 's/^/  /'
    exit 0
fi
if [ "$_ec" = 2 ]; then
    # ⛔ A HOLD WHOSE REASON SAYS "unknown" IS NOT A "not capturing" ANSWER. publish_detached
    # holds, and says so, when OBS is running but its log is missing or predates the process --
    # i.e. it CANNOT SEE the output state. Reporting that as "not capturing" is the same
    # over-claim this file was rewritten to remove, one layer further in: the delegate fails
    # closed correctly and the wrapper would have relabelled it open.
    if printf '%s' "$_out" | command grep -q 'unknown'; then
        echo "capture: UNKNOWN — OBS is running and the delegate cannot see its output state:"
        printf '%s\n' "$_out" | command grep 'HELD' | sed 's/^/  /'
        echo "  This is NOT idle. Treat it as possibly capturing."
        exit 2
    fi
    echo "capture: not capturing, but a publish would be HELD for another reason:"
    printf '%s\n' "$_out" | command grep 'HELD' | sed 's/^/  /'
    exit 1
fi
echo "capture: not capturing  [delegate: a publish would start now]"
exit 1
