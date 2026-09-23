#!/usr/bin/env bash
# Which THREAD of a wedged process is burning CPU, and what is it doing?
#
# A godot gate wedged 1h57m on 2026-09-19 at 100% on one thread with the main thread
# blocked; the mechanism is still unconfirmed because a backtrace needs ptrace, which
# nobody wanted to take on his box mid-recording. Everything here is an ordinary read of
# /proc -- NO ptrace, NO SIGSTOP, nothing that perturbs the target.
#
# Usage: tools/wedge_probe.sh <pid> [sample_seconds]   default 5
set -uo pipefail
pid="${1:?usage: wedge_probe.sh <pid> [seconds]}"
secs="${2:-5}"
[ -d "/proc/$pid" ] || { echo "no such pid: $pid" >&2; exit 2; }

hz=$(getconf CLK_TCK)
echo "== pid $pid: $(tr '\0' ' ' < "/proc/$pid/cmdline" | cut -c1-90)"
echo "== sampling ${secs}s, CLK_TCK=$hz, threads=$(ls /proc/$pid/task 2>/dev/null | wc -l)"

declare -A t0
f=()
for t in /proc/$pid/task/*; do
    tid=${t##*/}
    # ⛔ /proc/<tid>/stat field 2 is `(comm)` and comm CAN CONTAIN SPACES AND PARENS --
    # obs ships threads named "v4l2: capture". Positional parsing shifts every later field,
    # so the CPU numbers come from the wrong offsets for exactly the threads worth reading.
    # Strip through the LAST ')': then index 0 is field 3 (state), utime=11, stime=12.
    line=$(cat "$t/stat" 2>/dev/null) || continue
    read -r -a f <<< "${line##*) }"
    t0[$tid]=$(( ${f[11]} + ${f[12]} ))      # utime + stime, in ticks
done
sleep "$secs"

rows=$(for t in /proc/$pid/task/*; do
    tid=${t##*/}
    line=$(cat "$t/stat" 2>/dev/null) || continue
    read -r -a f <<< "${line##*) }"
    now=$(( ${f[11]} + ${f[12]} ))
    prev=${t0[$tid]:-$now}
    pct=$(awk -v d="$((now-prev))" -v s="$secs" -v hz="$hz" 'BEGIN{printf "%.1f", (d/hz)/s*100}')
    # STATE: R running · S sleeping · D uninterruptible. WCHAN names the kernel wait,
    # which is what distinguishes "blocked on a futex" from "spinning in userspace".
    name=$(cat "$t/comm" 2>/dev/null)
    state=${f[0]}
    wchan=$(cat "$t/wchan" 2>/dev/null || echo '?')
    [ -z "$wchan" ] && wchan='(userspace)'
    printf '%-9s %7s  %-18s %-7s %s\n' "$tid" "$pct" "$name" "$state" "$wchan"
done)

printf '%-9s %7s  %-18s %-7s %s\n' TID "CPU%" NAME STATE WCHAN
printf '%s\n' "$rows" | sort -k2 -rn | head -14

# ⛔ MAIN IS PRINTED HERE, OUTSIDE THE RANKING, BECAUSE THE RANKING DELETED IT.
# On 2026-09-20 this script read a wedged gate: 31 threads, main at 0.0%, and
# `sort -k2 -rn | head -14` dropped main's row. Three published readings then
# carried "main was blocked" -- inferred from the ABSENCE, never measured, while
# the line below promised "both halves name the mechanism". The wchan was read
# out of /proc and thrown away by this script's own pipeline.
echo
main_row=$(printf '%s\n' "$rows" | awk -v p="$pid" '$1 == p')
if [ -z "$main_row" ]; then
    echo "== main thread $pid: NOT SAMPLED -- it exited during the window."
    echo "== (an absent line is a gap, not a clean bill; that is what went wrong here)"
else
    echo "== main thread, unconditionally:"
    printf '   %s\n' "$main_row"
    echo "== its STATE ALONE CANNOT SAY 'blocked': a healthy main is S + hrtimer_nanosleep"
    echo "== whenever it is idle. Only WCHAN separates that from S + futex_* (waiting on"
    echo "== the spinner). For the four-way verdict run the tool that owns it -- this one"
    echo "== deliberately does not carry a second copy of the table:"
    echo "==   tools/which_thread_is_spinning.py $pid $secs"
fi
