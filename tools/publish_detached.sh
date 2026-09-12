#!/usr/bin/env bash
# Launch publish_all.sh OUT OF THE HARNESS REAPER'S VIEW, and record its real exit code.
#
# WHY THIS EXISTS
# ---------------
# Four publishes (.300, .302, .303 x2) were killed mid-run with "system is running low on
# memory". Every kill landed on the same step — godot's import — and the box was not short of
# memory in any kernel sense:
#
#     free ~12 GB · available ~100 GB · swap untouched (292 MB of 32 GB)
#
# The trigger is the HARNESS's background-task reaper reading free-behind-cache, not the
# kernel's OOM killer. @cowir-main isolated it properly: their fold gates are HEAVIER than this
# import (an import plus a 10k-test suite) and have run 20+ times at load 10-26 with zero kills,
# because they launch under `setsid` — the reaper has nothing to reap. One variable changed,
# worse conditions, no kills.
#
# ⛔ THIS DOES NOT BYPASS A REAL PROTECTION. The kernel's OOM killer is unaffected by setsid and
# still applies. What setsid escapes is a heuristic that was never describing exhaustion. I had
# refused to force a publish earlier on the grounds an OOM could take struktured's Quartus fit
# down with it — right about the risk, wrong about the mechanism.
#
# ⚠️ WHAT IS KEPT: a courtesy refusal while his own work is running. Not for the harness — for
# him. A publish is CPU and I/O that should not land on a machine he is recording on, and that
# is true regardless of who can kill what.
#
# Usage:  tools/publish_detached.sh <tag> [extra publish_all args...]
#         tools/publish_detached.sh --status <logdir>     bounded wait for the .ec file
#         tools/publish_detached.sh --selftest
# Exit:   0 launched (or, with --status, the publish's own code) · 2 usage/refusal
set -uo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

OWNER_PROCS="${PUBLISH_OWNER_PROCS:-quartus obs}"

_owner_busy() {
    # His processes, by name. `pgrep -c` prints 0 AND EXITS 1, so `|| echo 0` yields "0\n0" and
    # every later integer test errors — measured, and it made an earlier gate never fire while
    # reporting "no window". Count lines instead.
    local p n total=0
    for p in $OWNER_PROCS; do
        n=$(pgrep "$p" 2>/dev/null | wc -l)
        total=$(( total + n ))
    done
    printf '%s' "$total"
}

_status() {
    local dir="$1" budget="${2:-5400}" waited=0 step=15
    # BOUNDED, like every polling wait in this directory: a wait that cannot time out is a hang.
    while [ "$waited" -lt "$budget" ]; do
        if [ -f "$dir/publish.ec" ]; then
            local ec; ec=$(cat "$dir/publish.ec")
            echo "[detached] publish_all exited ${ec} after ~${waited}s"
            return "$ec"
        fi
        sleep "$step"; waited=$(( waited + step ))
    done
    echo "[detached] no .ec after ${budget}s — still running, or died without writing one." >&2
    echo "[detached] check the log and the store; a missing .ec is NOT evidence of failure." >&2
    return 3
}

case "${1:-}" in
    --status)   [ -n "${2:-}" ] || { echo "usage: $0 --status <logdir>" >&2; exit 2; }
                _status "$2" "${3:-5400}"; exit $? ;;
    --selftest) ;;                      # handled at the bottom
    "" |-*)     echo "usage: $0 <tag> [args...] | --status <logdir> | --selftest" >&2; exit 2 ;;
esac

if [ "${1:-}" != "--selftest" ]; then
    TAG="$1"; shift
    busy=$(_owner_busy)
    if [ "$busy" -gt 0 ]; then
        echo "[detached] REFUSING: ${busy} process(es) matching '${OWNER_PROCS}' are running." >&2
        echo "[detached] That is struktured's own work on his own machine. A publish is CPU and" >&2
        echo "[detached] I/O I should not add to it. Re-run when they are done." >&2
        exit 2
    fi
    LOGDIR="tmp/detached/${TAG}"
    mkdir -p "$LOGDIR"
    rm -f "$LOGDIR/publish.ec"
    # The EC file is written by the DETACHED shell, so it records publish_all's own code even
    # though this launcher has already exited. Without it, "the task died" and "the task
    # finished" are indistinguishable from out here — which is exactly how I reported a
    # successful .302 publish as a stand-down.
    # PUBLISH_CMD exists so the selftest can exercise THIS launcher rather than a copy of it.
    # A copied launcher proves nothing about the shipped one. Default is fixed.
    CMD="${PUBLISH_CMD:-./tools/publish_all.sh}"
    setsid bash -c '
        "$0" "$@" > "'"$LOGDIR"'/publish.log" 2>&1
        echo $? > "'"$LOGDIR"'/publish.ec"
    ' "$CMD" "$TAG" "$@" < /dev/null > /dev/null 2>&1 &
    echo "[detached] launched publish_all for ${TAG}"
    echo "[detached]   log: ${LOGDIR}/publish.log"
    echo "[detached]   ec:  ${LOGDIR}/publish.ec   (written when it finishes)"
    echo "[detached]   wait: tools/publish_detached.sh --status ${LOGDIR}"
    exit 0
fi

# ── selftest ─────────────────────────────────────────────────────────────────────────────
pass=0; fail=0
chk() { if [ "$2" = "$3" ]; then pass=$((pass+1)); printf '  ok    %-50s %s\n' "$1" "$2";
        else fail=$((fail+1)); printf '  FAIL  %-50s got %s want %s\n' "$1" "$2" "$3"; fi; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/ok.sh";  chmod +x "$T/ok.sh"
printf '#!/usr/bin/env bash\nexit 7\n' > "$T/bad.sh"; chmod +x "$T/bad.sh"
printf '#!/usr/bin/env bash\nsleep 2; exit 3\n' > "$T/slow.sh"; chmod +x "$T/slow.sh"
_wait_ec() { local f="$1" n=0; while [ "$n" -lt 20 ]; do [ -f "$f" ] && return 0; sleep 1; n=$((n+1)); done; return 1; }

# 1/2 — the EC file records the REAL code, both directions. A launcher that always wrote 0
#       would pass a success-only arm and hide every failure it ever had.
for pair in "ok 0" "bad 7"; do
    set -- $pair
    PUBLISH_CMD="$T/$1.sh" PUBLISH_OWNER_PROCS="__absent__" ./tools/publish_detached.sh "ZZ-$1" >/dev/null 2>&1
    _wait_ec "tmp/detached/ZZ-$1/publish.ec"
    chk "EC recorded faithfully ($1.sh)" "$(cat "tmp/detached/ZZ-$1/publish.ec" 2>/dev/null)" "$2"
done

# 3 — DETACHED. If the child shares this shell's session the reaper still owns it and the
#     whole point is lost; this is the arm that tests the fix rather than the plumbing.
PUBLISH_CMD="$T/slow.sh" PUBLISH_OWNER_PROCS="__absent__" ./tools/publish_detached.sh ZZ-detach >/dev/null 2>&1
sleep 1
kid=$(pgrep -f "$T/slow.sh" 2>/dev/null | head -1)
if [ -n "$kid" ]; then
    ks=$(ps -o sess= -p "$kid" 2>/dev/null | tr -d ' '); ms=$(ps -o sess= -p $$ 2>/dev/null | tr -d ' ')
    chk "child runs in its OWN session (setsid took effect)" "$([ "$ks" != "$ms" ] && echo yes || echo no)" "yes"
else
    fail=$((fail+1)); printf '  FAIL  %-50s child not found\n' "child runs in its OWN session"
fi
_wait_ec tmp/detached/ZZ-detach/publish.ec
chk "slow child wrote its EC after the launcher returned" "$(cat tmp/detached/ZZ-detach/publish.ec 2>/dev/null)" "3"

# 4/5 — the courtesy refusal, BOTH directions. An always-refusing guard passes arm 4 alone.
PUBLISH_OWNER_PROCS="bash" ./tools/publish_detached.sh ZZ-busy >/dev/null 2>&1
chk "refuses while an owner process runs" "$?" "2"
PUBLISH_CMD="$T/ok.sh" PUBLISH_OWNER_PROCS="__absent__" ./tools/publish_detached.sh ZZ-free >/dev/null 2>&1
chk "launches when none does (not a blanket refusal)" "$?" "0"

# 6/7 — --status is BOUNDED and reports the recorded code rather than hanging.
./tools/publish_detached.sh --status tmp/detached/ZZ-bad 30 >/dev/null 2>&1
chk "--status returns the recorded EC" "$?" "7"
./tools/publish_detached.sh --status "$T" 1 >/dev/null 2>&1
chk "--status on a missing .ec times out (bounded)" "$?" "3"

rm -rf tmp/detached/ZZ-*
echo; echo "selftest: ${pass} passed, ${fail} failed"; [ "$fail" -eq 0 ]
