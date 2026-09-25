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

declare -A t0 v0 t1 v1 st1
# ⛔ /proc/<tid>/stat field 2 is `(comm)` and comm CAN CONTAIN SPACES AND PARENS -- obs ships
# threads named "v4l2: capture". Strip through the LAST ')': then index 0 is field 3 (state),
# utime=11, stime=12. voluntary_ctxt_switches = times the thread chose to sleep; matched by
# EXACT key, because /proc/<tid>/status also carries "nonvoluntary_ctxt_switches".
counters() {  # task dir -> "ticks vcs state", builtins only
    local line k val v=0 f
    read -r line < "$1/stat" 2>/dev/null || return 1
    read -r -a f <<< "${line##*) }"
    while read -r k val _; do [ "$k" = "voluntary_ctxt_switches:" ] && { v=$val; break; }; done < "$1/status"
    echo "$(( ${f[11]} + ${f[12]} )) $v ${f[0]}"
}
# ⛔ DIVIDE BY THE MEASURED WINDOW, AND MAKE BOTH WALKS COST THE SAME. Dividing by the nominal
# "$secs" is why wedge captures printed 102.2% and 104.4% for ONE thread -- impossible: each walk
# takes real time, so a thread read "over 3s" was read over ~3.3s. And if the second walk does
# more per thread than the first, threads LATE in the walk get a longer true window than the one
# measured -- the periodic workers sit at ranks 26-30 of 31 and read ~5% high that way while main,
# first in the walk, read true. So: two identical counter-only walks, formatting afterwards.
T0=$(date +%s%N)
for t in /proc/$pid/task/*; do
    c=$(counters "$t") || continue; set -- $c
    t0[${t##*/}]=$1; v0[${t##*/}]=$2
done
sleep "$secs"
T1=$(date +%s%N)
for t in /proc/$pid/task/*; do
    c=$(counters "$t") || continue; set -- $c
    t1[${t##*/}]=$1; v1[${t##*/}]=$2; st1[${t##*/}]=$3
done
el=$(awk -v a="$T0" -v b="$T1" 'BEGIN{printf "%.3f", (b-a)/1e9}')

rows=$(for tid in "${!t1[@]}"; do
    [ -n "${t0[$tid]:-}" ] || continue          # born mid-window: no baseline, no rate
    pct=$(awk -v d="$(( t1[$tid] - t0[$tid] ))" -v s="$el" -v hz="$hz" 'BEGIN{printf "%.1f", (d/hz)/s*100}')
    slp=$(awk -v d="$(( v1[$tid] - v0[$tid] ))" -v s="$el" 'BEGIN{printf "%.1f", d/s}')
    # STATE: R running · S sleeping · D uninterruptible. WCHAN names the kernel wait,
    # which is what distinguishes "blocked on a futex" from "spinning in userspace".
    name=$(cat "/proc/$pid/task/$tid/comm" 2>/dev/null)
    wchan=$(cat "/proc/$pid/task/$tid/wchan" 2>/dev/null || echo '?')
    [ -z "$wchan" ] && wchan='(userspace)'
    printf '%-9s %7s %7s  %-18s %-7s %s\n' "$tid" "$pct" "$slp" "$name" "${st1[$tid]}" "$wchan"
done)

echo "== measured window ${el}s (asked for ${secs}s)"
printf '%-9s %7s %7s  %-18s %-7s %s\n' TID "CPU%" "SLP/s" NAME STATE WCHAN
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

# ⛔ PERIODIC SLEEPERS ARE PRINTED IN FULL, BECAUSE THEY SIT AT 0.0% CPU AND THE TOP-14
# RANKING ABOVE DROPS THEM -- the same truncation that once deleted main's row.
# Every thread's name is "godot", so CADENCE (SLP/s) is the only identity /proc gives
# without ptrace. Measured 2026-09-24, godot 4.4.1, Dummy driver, our project, 31 threads:
# four periodic workers at 20.0 · 99.7 · 10.7 · 1.0 /s. The 10.7 one is the AUDIO MIX
# thread -- proven by varying audio/driver/mix_rate (11025 -> 2.7, 88200 -> 21.3; nothing
# else moved). --audio-output-latency moves NOTHING: Dummy uses a fixed 4096-frame buffer.
# A wedged spinner stops sleeping, so its cadence VANISHES while the others keep theirs:
# whichever of the four is missing below names the spinner. Re-measure after an engine bump.
# ⚠️ Listed if it slept AT ALL, not >= 1/s: the 1/s thread wakes only 2-4 times in 3s and a
# >= 1 cutoff dropped it from a HEALTHY run -- a false "missing". Use a window >= 5s (default).
echo
echo "== threads that slept at all in the window (periodic workers), ALL of them, by cadence:"
printf '%s\n' "$rows" | awk '$3 > 0' | sort -k3 -rn | sed 's/^/   /'
echo "== healthy fingerprint (4.4.1, Dummy, 44.1k): 20.0 · 99.7 · 10.7 (AUDIO MIX) · 1.0 /s"
