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
#         tools/publish_detached.sh --check               would a publish start now, and if not why
#         tools/publish_detached.sh --status <logdir>     bounded wait for the .ec file
#         tools/publish_detached.sh --selftest
# Exit:   0 launched (or, with --status, the publish's own code) · 2 usage/refusal
set -uo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"

# Processes whose mere PRESENCE means his machine is busy. `obs` used to be here, and that was
# the wrong question: OBS being OPEN is not OBS being LIVE. On 2026-09-14 OBS stayed open
# playing an internet-radio source after an 11h38m recording ended at 18:48, and this gate held
# v3.33.349-alpha off the store for hours more -- until it was launched by hand with the gate
# narrowed. `obs-ffmpeg-mux` is the recording muxer: it exists only while a file is written.
OWNER_PROCS="${PUBLISH_OWNER_PROCS:-quartus obs-ffmpeg-mux}"
MUX_PROC="${PUBLISH_MUX_PROC:-obs-ffmpeg-mux}"

# Is OBS LIVE? Recording, streaming and the replay buffer all run an encoder, and only the first
# has a process of its own -- a stream is an in-process socket, a replay buffer is RAM. OBS
# states all three in its own log, so read the state from the thing that has it:
#
#     07:04:54 ==== Recording Start ====        <- the muxer's file is 20260914_070454_*.mkv
#     07:05:19 ==== Replay Buffer Start ====    <- invisible to any process-name check
#     18:48:28 ==== Replay Buffer Stop ====
#     18:48:28 ==== Recording Stop ====         <- at 19:43 the muxer was gone
#     21:05:19 ==== Recording Start ====        <- and back when this was written
#
# Measured against independent evidence at every transition that day. FAILS CLOSED: if OBS is
# running and its state cannot be read, that is a refusal, never a launch.
OBS_PROC="${PUBLISH_OBS_PROC:-obs}"
OBS_LOG_DIR="${PUBLISH_OBS_LOG_DIR:-$HOME/.config/obs-studio/logs}"

# Outputs whose LAST marker in the log is a Start. Prints e.g. "Recording, Replay Buffer".
_obs_live_outputs() {
    awk '
        /==== Recording Start/     { s["Recording"] = 1 }  /==== Recording Stop/     { s["Recording"] = 0 }
        /==== Streaming Start/     { s["Streaming"] = 1 }  /==== Streaming Stop/     { s["Streaming"] = 0 }
        /==== Replay Buffer Start/ { s["Replay Buffer"] = 1 } /==== Replay Buffer Stop/ { s["Replay Buffer"] = 0 }
        END { n = 0; for (k in s) if (s[k]) printf "%s%s", (n++ ? ", " : ""), k }' "$1"
}

# Prints one reason per line; empty output means OBS is not a reason to wait.
# Is the capture actually being WRITTEN? The markers say what OBS last declared; this says what
# the muxer is doing right now. Prints "growing", "static", or "" when there is nothing to watch.
#
# WHY THIS IS CORROBORATION AND NEVER AN OVERRIDE
# -----------------------------------------------
# The residual gap in this gate: OBS alive, log says Start with no Stop, encoder actually hung.
# The markers then say live forever and the store waits on a hold that is false. cowir-main
# proposed a CPU sample; I declined it, because the only thing a low sample can do is RELEASE a
# hold the markers justify, and a two-sample delta reads idle during a scene change. A false
# hold costs an hour; a false launch costs him the broadcast.
#
# File growth is the better signal — direct evidence about the thing that matters rather than a
# proxy for it — and it STILL must not release, for a reason measured 2026-09-17: this OBS logs
# no pause markers at all (only Recording/Streaming Start/Stop across the whole session). A
# PAUSED recording and a HUNG one are both a static file, and pausing is something he does on
# purpose. Nothing available here distinguishes them.
#
# So it reports. When the markers and the file DISAGREE, that is the anomaly worth printing —
# loudly, next to a hold that still holds.
_capture_growth() {
    # PUBLISH_CAPTURE_FILE is a seam for the selftest: discovery needs a live muxer, and an arm
    # that cannot produce the STATIC case would only ever test the half that already works.
    local f; f="${PUBLISH_CAPTURE_FILE:-$(pgrep -af "$MUX_PROC" 2>/dev/null | command grep -av 'pgrep' \
                  | command grep -aoE '/[^ ]+\.(mkv|mp4|flv|mov)' | head -1)}"
    [ -n "$f" ] && [ -r "$f" ] || return 0
    local a b; a="$(stat -c%s "$f" 2>/dev/null)" || return 0
    sleep "${CAPTURE_SAMPLE_SECS:-3}"
    b="$(stat -c%s "$f" 2>/dev/null)" || return 0
    if [ "${b:-0}" -gt "${a:-0}" ]; then printf 'growing %s' "$(( b - a ))"
    else printf 'static'; fi
}

_obs_busy() {
    local pid; pid=$(pgrep -x "$OBS_PROC" 2>/dev/null | head -1)
    [ -n "$pid" ] || return 0                               # not running: nothing to protect
    local log; log=$(ls -t "$OBS_LOG_DIR"/*.txt 2>/dev/null | head -1)
    if [ -z "$log" ]; then
        echo "OBS is running and has no log under ${OBS_LOG_DIR}, so its output state is unknown"
        return 0
    fi
    # The newest log must belong to THIS OBS. A log older than the process is a previous
    # instance's, and its last marker says nothing about what is running now.
    local started; started=$(( $(date +%s) - $(ps -o etimes= -p "$pid" | tr -d ' ') ))
    if [ "$(stat -c %Y "$log")" -lt "$started" ]; then
        echo "OBS is running but its newest log predates it ($(basename "$log")), so its output state is unknown"
        return 0
    fi
    local live; live=$(_obs_live_outputs "$log")
    [ -n "$live" ] && echo "OBS is live: ${live}"
    return 0
}

# Where the log and the .ec live. NOT under the publish worktree: `git worktree remove` is the
# step that FOLLOWS every publish, and it deleted the .ec for v3.33.304-alpha -- the one artifact
# whose whole purpose is to answer "did it finish?" after the fact. A publish worktree is
# <lane>/tmp/<name>, so the lane root is the path before /tmp/, the same derivation publish_all
# uses for its log archive. `here` is a parameter so the selftest can drive both branches.
_logdir() {
    local tag="$1" here="${2:-$(pwd -P)}"
    case "$here" in
        */tmp/*) printf '%s' "${here%%/tmp/*}/tmp/_detached/${tag}" ;;
        *)       printf '%s' "tmp/detached/${tag}" ;;
    esac
}

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
    # Poll granularity scales with the bound. A fixed 15s step does not just overshoot a small
    # budget — it also DELAYS DETECTION within one: with budget 6 and a .ec written at t=1, the
    # single 6s nap means the answer arrives at t=6 rather than t=1. Tenth of the budget,
    # clamped to [1,15], so the long real waits keep their cheap 15s cadence and short ones
    # answer promptly.
    [ "$(( budget / 10 ))" -lt "$step" ] && step=$(( budget / 10 ))
    [ "$step" -lt 1 ] && step=1
    # BOUNDED, like every polling wait in this directory: a wait that cannot time out is a hang.
    #
    # ⛔ AND THE BOUND WAS NOT HONOURED. `sleep "$step"` was unconditional, so the 15s poll
    # granularity dominated any budget below it: `--status <dir> 1` waited FIFTEEN seconds and
    # then reported "no .ec after 1s". Two defects in one line — the caller's bound ignored,
    # and a message stating a duration nobody measured. Measured on the selftest's own arm:
    # 15.01s for a budget of 1, which was 79% of a 19.03s selftest and the last cost exemption
    # in gate 0d.
    #
    # Nap the LESSER of the step and what is left, and report what was actually waited.
    while [ "$waited" -lt "$budget" ]; do
        if [ -f "$dir/publish.ec" ]; then
            local ec; ec=$(cat "$dir/publish.ec")
            echo "[detached] publish_all exited ${ec} after ~${waited}s"
            return "$ec"
        fi
        local remain=$(( budget - waited )) nap="$step"
        [ "$remain" -lt "$nap" ] && nap="$remain"
        sleep "$nap"; waited=$(( waited + nap ))
    done
    # One more look before declaring a timeout: a .ec written DURING the final nap was
    # previously reported as "still running", which is a false negative on the one artifact
    # whose whole purpose is to answer "did it finish?" after the fact.
    if [ -f "$dir/publish.ec" ]; then
        local ec; ec=$(cat "$dir/publish.ec")
        echo "[detached] publish_all exited ${ec} after ~${waited}s"
        return "$ec"
    fi
    echo "[detached] no .ec after ${waited}s — still running, or died without writing one." >&2
    echo "[detached] check the log and the store; a missing .ec is NOT evidence of failure." >&2
    return 3
}

case "${1:-}" in
    --status)   [ -n "${2:-}" ] || { echo "usage: $0 --status <logdir>" >&2; exit 2; }
                _status "$2" "${3:-5400}"; exit $? ;;
    --selftest) ;;                      # handled at the bottom
    # ⛔ THE HOLD USED TO BE UNASKABLE. The only way to learn whether a publish would be
    # refused, and why, was to ATTEMPT ONE — so the reason existed solely in the launcher's
    # stderr, at the moment somebody happened to try. tools/store_status.sh answers WHAT the
    # store owes ("BEHIND at v3.33.376-alpha: linux windows web") and nothing answered WHY it
    # had not shipped. Those are different states with different responses: a courtesy hold
    # waits, a RED gate stops, a crashed run needs relaunching, and "nobody ran it" needs
    # somebody to run it. All four look identical from the store side.
    #
    # On 2026-09-16 the store sat five tags behind for two hours on a correct courtesy hold,
    # and the only record of that anywhere was my own hourly intercom posts.
    #
    # --check answers it WITHOUT launching: same two gates, same reasons, no side effects, no
    # worktree, no butler traffic. Exit 0 = a publish would start now; 2 = it would refuse.
    --check)    _busy=$(_owner_busy)
                _obs=$(_obs_busy)
                if [ "$_busy" -gt 0 ] || [ -n "$_obs" ]; then
                    [ "$_busy" -gt 0 ] && echo "[check] HELD: ${_busy} process(es) matching '${OWNER_PROCS}' are running."
                    [ -n "$_obs" ] && printf '[check] HELD: %s\n' "$_obs"
                    # corroboration, never a verdict — see _capture_growth
                    _g="$(_capture_growth)"
                    case "$_g" in
                        growing*) printf '[check]   corroborated: the capture file is GROWING (+%s bytes in %ss)\n' \
                                         "${_g#growing }" "${CAPTURE_SAMPLE_SECS:-3}" ;;
                        static)   echo "[check]   ⚠ ANOMALY: OBS reports live output and the capture file is NOT growing." ;
                                  echo "[check]     A paused recording and a hung encoder look identical from here — this" ;
                                  echo "[check]     OBS logs no pause markers — so the hold STANDS and is not released on" ;
                                  echo "[check]     this signal. Worth a look if it persists." ;;
                    esac
                    echo "[check] A publish would REFUSE right now. That is struktured's own work on his"
                    echo "[check] own machine; re-run when it is done. Nothing here launches anything."
                    exit 2
                fi
                [ -n "$(pgrep -x "$OBS_PROC" 2>/dev/null)" ] && \
                    echo "[check] OBS is open but not recording, streaming or holding a replay buffer."
                echo "[check] CLEAR: a publish would start now. Nothing is holding it."
                exit 0 ;;
    "" |-*)     echo "usage: $0 <tag> [args...] | --check | --status <logdir> | --selftest" >&2; exit 2 ;;
esac

if [ "${1:-}" != "--selftest" ]; then
    TAG="$1"; shift
    busy=$(_owner_busy)
    obs=$(_obs_busy)
    if [ "$busy" -gt 0 ] || [ -n "$obs" ]; then
        [ "$busy" -gt 0 ] && echo "[detached] REFUSING: ${busy} process(es) matching '${OWNER_PROCS}' are running." >&2
        [ -n "$obs" ] && printf '[detached] REFUSING: %s\n' "$obs" >&2
        echo "[detached] That is struktured's own work on his own machine. A publish is CPU and" >&2
        echo "[detached] I/O I should not add to it. Re-run when they are done." >&2
        exit 2
    fi
    [ -n "$(pgrep -x "$OBS_PROC" 2>/dev/null)" ] && \
        echo "[detached] OBS is open but not recording, streaming or holding a replay buffer — not a reason to wait"
    LOGDIR="$(_logdir "$TAG")"
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
# The path comes from the launcher's OWN report. An expectation restated is one that can
# drift from the code; the archiving test measured a directory the code had stopped writing to.
_ec_path_from() { printf '%s' "$1" | sed -n 's/^\[detached\]   ec:  \([^ ]*\).*/\1/p'; }

for pair in "ok 0" "bad 7"; do
    set -- $pair
    out=$(PUBLISH_CMD="$T/$1.sh" PUBLISH_OWNER_PROCS="__absent__" PUBLISH_OBS_PROC="__absent__" ./tools/publish_detached.sh "ZZ-$1" 2>&1)
    ecf=$(_ec_path_from "$out")
    [ -n "$ecf" ] || { fail=$((fail+1)); printf '  FAIL  %-50s launcher printed no ec path\n' "EC path reported ($1.sh)"; }
    _wait_ec "$ecf"
    chk "EC recorded faithfully ($1.sh)" "$(cat "$ecf" 2>/dev/null)" "$2"
done

# 3 — DETACHED. If the child shares this shell's session the reaper still owns it and the
#     whole point is lost; this is the arm that tests the fix rather than the plumbing.
out=$(PUBLISH_CMD="$T/slow.sh" PUBLISH_OWNER_PROCS="__absent__" PUBLISH_OBS_PROC="__absent__" ./tools/publish_detached.sh ZZ-detach 2>&1)
slow_ec=$(_ec_path_from "$out")
sleep 1
kid=$(pgrep -f "$T/slow.sh" 2>/dev/null | head -1)
if [ -n "$kid" ]; then
    ks=$(ps -o sess= -p "$kid" 2>/dev/null | tr -d ' '); ms=$(ps -o sess= -p $$ 2>/dev/null | tr -d ' ')
    chk "child runs in its OWN session (setsid took effect)" "$([ "$ks" != "$ms" ] && echo yes || echo no)" "yes"
else
    fail=$((fail+1)); printf '  FAIL  %-50s child not found\n' "child runs in its OWN session"
fi
_wait_ec "$slow_ec"
chk "slow child wrote its EC after the launcher returned" "$(cat "$slow_ec" 2>/dev/null)" "3"

# 4/5 — the courtesy refusal, BOTH directions. An always-refusing guard passes arm 4 alone.
PUBLISH_OWNER_PROCS="bash" ./tools/publish_detached.sh ZZ-busy >/dev/null 2>&1
chk "refuses while an owner process runs" "$?" "2"
PUBLISH_CMD="$T/ok.sh" PUBLISH_OWNER_PROCS="__absent__" PUBLISH_OBS_PROC="__absent__" ./tools/publish_detached.sh ZZ-free >/dev/null 2>&1
chk "launches when none does (not a blanket refusal)" "$?" "0"

# 5b — OBS OPEN IS NOT OBS LIVE. Every arm drives the SHIPPED launcher with an injected log and
#      an OBS stand-in process (`bash`, which is always running here), both directions, so an
#      always-refuse or always-launch gate cannot pass. Markers are OBS's own, copied from a real
#      log. Expectations include the REASON, not just the exit code.
O="$T/obslogs"; mkdir -p "$O"
_obslog() { rm -f "$O"/*.txt; printf '%s\n' "$@" > "$O/2026-01-01 00-00-00.txt"; }
_try() {  # label want_ec want_text  (runs with bash standing in for obs)
    local out ec
    out=$(PUBLISH_CMD="$T/ok.sh" PUBLISH_OWNER_PROCS="__absent__" PUBLISH_OBS_PROC="bash" \
          PUBLISH_OBS_LOG_DIR="$O" ./tools/publish_detached.sh "ZZ-obs" 2>&1); ec=$?
    chk "$1" "$ec" "$2"
    case "$out" in *"$3"*) chk "  ...and says why" yes yes ;; *) chk "  ...and says why ($3)" "no" "yes" ;; esac
}
R_START='07:04:54.593: ==== Recording Start ==============================================='
R_STOP='18:48:28.667: ==== Recording Stop ================================================'
B_START='07:05:19.835: ==== Replay Buffer Start ==========================================='
B_STOP='18:48:28.176: ==== Replay Buffer Stop ============================================'
S_START='20:00:00.000: ==== Streaming Start ==============================================='
S_STOP='20:30:00.000: ==== Streaming Stop ================================================'

_obslog "$R_START";                               _try "obs recording -> refuse"                  2 "OBS is live: Recording"
_obslog "$R_START" "$B_START" "$B_STOP" "$R_STOP"; _try "obs open, everything stopped -> launch"   0 "not a reason to wait"
_obslog "$R_START" "$R_STOP" "$B_START";          _try "replay buffer alone -> refuse"            2 "Replay Buffer"
_obslog "$S_START";                               _try "streaming -> refuse"                      2 "Streaming"
_obslog "$S_START" "$S_STOP";                     _try "stream ended -> launch"                   0 "not a reason to wait"
rm -f "$O"/*.txt;                                 _try "obs running, NO log -> refuse (fail closed)" 2 "output state is unknown"
_obslog "$R_STOP"; touch -d '2000-01-01' "$O"/*.txt
                                                  _try "log older than obs -> refuse (fail closed)"  2 "predates it"
# ── --check answers the same question WITHOUT launching ──────────────────────────────────
# Both directions, and a third arm proving it has no side effects: the whole point is that a
# reader can ask the gate instead of attempting a publish to find out.
_chk_mode() {  # label want_ec want_text
    local out ec
    out=$(PUBLISH_OWNER_PROCS="__absent__" PUBLISH_OBS_PROC="bash" \
          PUBLISH_OBS_LOG_DIR="$O" ./tools/publish_detached.sh --check 2>&1); ec=$?
    chk "$1" "$ec" "$2"
    case "$out" in *"$3"*) chk "  ...and says why" yes yes ;; *) chk "  ...and says why ($3)" "no" "yes" ;; esac
}
# ── the capture-growth corroboration: reports, never decides ────────────────────────────
# Both directions, and the load-bearing pair is that the VERDICT is HELD either way — a signal
# that could release a hold is the one thing this must not become.
_grow="$T/cap.mkv"; : > "$_grow"
_chk_cap() {  # label want_ec want_text   (file prepared by the caller)
    local out ec
    out=$(PUBLISH_OWNER_PROCS="__absent__" PUBLISH_OBS_PROC="bash" PUBLISH_OBS_LOG_DIR="$O" \
          PUBLISH_CAPTURE_FILE="$_grow" CAPTURE_SAMPLE_SECS=1 \
          ./tools/publish_detached.sh --check 2>&1); ec=$?
    chk "$1" "$ec" "$2"
    case "$out" in *"$3"*) chk "  ...and says so" yes yes ;; *) chk "  ...and says so ($3)" "no" "yes" ;; esac
}
_obslog "$S_START"
( sleep 0.3; printf 'xxxxxxxxxxxxxxxx' >> "$_grow" ) &
_chk_cap "a GROWING capture corroborates the hold" 2 "capture file is GROWING"
wait
_chk_cap "a STATIC capture is an ANOMALY"          2 "ANOMALY"
_chk_cap "  ...and the hold STILL stands"          2 "hold STANDS"
rm -f "$_grow"
_chk_cap "no capture file at all -> no corroboration line" 2 "OBS is live: Streaming"

_obslog "$S_START";           _chk_mode "--check while streaming -> HELD"        2 "OBS is live: Streaming"
_obslog "$S_START" "$S_STOP"; _chk_mode "--check with nothing live -> CLEAR"     0 "CLEAR: a publish would start now"
# ⛔ AND IT MUST NOT HAVE LAUNCHED ANYTHING ON THE WAY TO THAT ANSWER — a check that publishes
# is worse than no check.
#
# ⚠️ The first version of this arm asserted that `_logdir ZZ-checkmode` was absent. --check
# takes no tag, so that path could never exist whether it launched or not: an absence assert
# over a sample that cannot occur, which passes identically on a broken --check. Replaced with
# a before/after of the detached ROOT, and floored by a real launch — without the floor,
# "unchanged" is equally satisfied by a root that never changes for anybody.
_detroot="$(dirname "$(_logdir ZZ-probe)")"
# A DIGEST, not the listing: this root holds one entry per release and printing it put a
# 1000-character line into every publish's selftest output. Count plus checksum moves on any
# add, remove or rename, which is the whole question.
_snap() { ls -1 "$_detroot" 2>/dev/null | sort | cksum | tr -s ' ' | cut -d' ' -f1,2; }
_before="$(_snap)"
PUBLISH_OWNER_PROCS="__absent__" PUBLISH_OBS_PROC="bash" PUBLISH_OBS_LOG_DIR="$O" \
  ./tools/publish_detached.sh --check >/dev/null 2>&1
chk "--check leaves the detached root untouched" "$(_snap)" "$_before"
# the floor: a REAL launch must move that same listing, or the arm above proves nothing
_obslog "$S_START" "$S_STOP"
PUBLISH_CMD="$T/ok.sh" PUBLISH_OWNER_PROCS="__absent__" PUBLISH_OBS_PROC="bash" \
  PUBLISH_OBS_LOG_DIR="$O" ./tools/publish_detached.sh ZZ-launchfloor >/dev/null 2>&1
chk "  ...and a real launch DOES move it" "$([ "$(_snap)" != "$_before" ] && echo moved || echo same)" "moved"

# the same live-looking log with OBS NOT running is not a reason to wait
_obslog "$R_START"
PUBLISH_CMD="$T/ok.sh" PUBLISH_OWNER_PROCS="__absent__" PUBLISH_OBS_PROC="__absent__" \
  PUBLISH_OBS_LOG_DIR="$O" ./tools/publish_detached.sh ZZ-obsgone >/dev/null 2>&1
chk "stale 'Recording Start' with obs NOT running -> launch" "$?" "0"

# 6/7 — --status is BOUNDED and reports the recorded code rather than hanging.
./tools/publish_detached.sh --status "$(_logdir ZZ-bad)" 30 >/dev/null 2>&1
chk "--status returns the recorded EC" "$?" "7"
./tools/publish_detached.sh --status "$T" 1 >/dev/null 2>&1
chk "--status on a missing .ec times out (bounded)" "$?" "3"

# 8/9/10 — THE BOUND IS HONOURED, THE MESSAGE IS MEASURED, AND A LATE .ec IS NOT A TIMEOUT.
# The old loop slept a fixed 15s regardless of the budget, so `--status <dir> 1` waited 15s
# and then printed "no .ec after 1s". Both halves are pinned here because both were wrong:
# an arm asserting only the exit code passed for the broken version too.
_t0=$(date +%s)
_out="$(./tools/publish_detached.sh --status "$T" 2 2>&1)"; _ec=$?
_elapsed=$(( $(date +%s) - _t0 ))
chk "--status budget 2 returns within 5s (not the 15s step)" "$([ "$_elapsed" -le 5 ] && echo yes || echo "no:${_elapsed}s")" "yes"
chk "--status reports the time it ACTUALLY waited"           "$(printf '%s' "$_out" | grep -c 'no \.ec after 2s')" "1"

# A .ec written during the final nap used to be reported as "still running" — a false negative
# on the one artifact whose purpose is to answer "did it finish?" after the fact.
( sleep 1; echo 4 > "$T/publish.ec" ) &
./tools/publish_detached.sh --status "$T" 6 >/dev/null 2>&1
chk "a .ec written DURING the wait returns its code, not 3" "$?" "4"
wait; rm -f "$T/publish.ec"

# 8/9 — the .ec must OUTLIVE the publish worktree. v3.33.304-alpha's did not: the logdir was
#       relative, so `git worktree remove` took the exit code with it. Drive both branches of
#       the derivation directly, because one of them cannot be reached from where this runs.
wt_dir=$(_logdir v9.9.9 /home/x/lane-wt/tmp/pub999)
chk "logdir escapes a <lane>/tmp/<wt> worktree" \
    "$(case "$wt_dir" in /home/x/lane-wt/tmp/_detached/v9.9.9) echo yes ;; *) echo "no:$wt_dir" ;; esac)" "yes"
plain_dir=$(_logdir v9.9.9 /home/x/plainrepo)
chk "logdir stays relative outside a worktree" "$plain_dir" "tmp/detached/v9.9.9"

rm -rf tmp/detached/ZZ-* "$(_logdir '' | sed 's:/*$::')"/ZZ-* 2>/dev/null
echo; echo "selftest: ${pass} passed, ${fail} failed"; [ "$fail" -eq 0 ]
