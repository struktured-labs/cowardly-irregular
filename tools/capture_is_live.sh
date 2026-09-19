#!/usr/bin/env bash
# Is struktured capturing right now? Three signals that FAIL DIFFERENTLY; any one says LIVE.
# EC=0 LIVE (do not load the box) · EC=1 idle. Never reports idle on a signal it could not read.
WINDOW="${1:-12}"          # MUST exceed OBS's max flush gap, MEASURED 4.25s (gaps 4.00/4.25/4.25/4.00
                           # sampled at 0.25s over 20s). 12s buys two flushes plus margin. A 3s window
                           # read 0 B on a LIVE capture in 1 of 5 consecutive samples -- and the false
                           # direction is the costly one: it releases the hold onto a live 1080p60 capture.
                           # The mkv grows in ~382 KB quanta, so a short delta is a FLUSH COUNT, not a rate.
live=0; reasons=()

f=$(command find "$HOME/Videos" -name '*.mkv' -newermt "-10 minutes" 2>/dev/null | head -1)
if [ -n "$f" ]; then
    s1=$(stat -c %s "$f"); sleep "$WINDOW"; s2=$(stat -c %s "$f")
    if [ "$s2" -gt "$s1" ]; then live=1; reasons+=("file +$((s2-s1))B/${WINDOW}s"); fi
else
    reasons+=("no recent mkv (cannot read this signal)")
fi

log=$(command find "$HOME/.config/obs-studio/logs" -name '*.txt' -newermt "-1 day" 2>/dev/null \
      | sort | tail -1)
if [ -n "$log" ]; then
    starts=$(command grep -ac 'Recording Start' "$log")
    stops=$(command grep -ac 'Recording Stop'  "$log")
    if [ "${starts:-0}" -gt "${stops:-0}" ]; then live=1; reasons+=("obs log ${starts} start/${stops} stop"); fi
else
    reasons+=("no obs log (cannot read this signal)")
fi

# process: own-cmdline self-match is why this reads /proc, not pgrep
mux=0
for p in /proc/[0-9]*; do
    [ "${p#/proc/}" = "$$" ] && continue
    c=$(tr '\0' ' ' < "$p/cmdline" 2>/dev/null) || continue
    case "$c" in *obs-ffmpeg-mux*) mux=1;; esac
done 2>/dev/null
[ "$mux" = 1 ] && { live=1; reasons+=("mux alive"); }

printf 'capture: %s  [%s]\n' "$([ $live = 1 ] && echo LIVE || echo idle)" "$(IFS=' · '; echo "${reasons[*]}")"
[ "$live" = 1 ]
