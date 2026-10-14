#!/usr/bin/env bash
## block_seat — a pushed stone block seating into its socket (DungeonMechanics.mark_block_on_target).
## Fourth and last of the door_open sites. Reproducible: every layer and gain is here.
##
## SEPARATION TARGETS, set from the FFT table of the four existing cues:
##   length    0.35s   (0.55 plate / 0.60 mirror / 0.95 blast / 1.00 door — 0.20 clear of the nearest)
##   dominant  1k-2k   the one band none of the four occupies; also what stone-on-stone actually is
##   level     rms ~ -19.5, peak ~ -4   inside the family's measured -19.2..-20.5 / -2.5..-4.6
## ⚠️ THIS SCRIPT DOES NOT BYTE-REPRODUCE THE SHIPPED ASSET, AND THAT IS NOT FIXABLE HERE. Its
## noise layers are `sox ... whitenoise`, which sox seeds per run, and it predates the `sox -R`
## fix (see tools/gen_freight_lift.sh, which IS reproducible). So it is the RECIPE -- every layer,
## frequency and gain, which is the provenance the manifest prompt cites -- and the .ogg on disk is
## the authority. Adding `-R` now would make this script emit DIFFERENT audio from the approved cue,
## which is the one thing it must not do.
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
D=tmp/block
R=44100

# 1. the last of the slide: a short grind, already fading as the block arrives
sox -n -r $R -c 1 "$D/grind.wav" synth 0.15 brownnoise \
    sinc 500-1500 fade t 0.02 0.15 0.12 vol 0.30

# 2. THE SEAT — stone on stone, two close partials, hard attack. This is the dominant.
## DETUNED ON PURPOSE: 1500/1750 is ~a minor third and read as a pitched figure. 1480/1690 is
## ratio 1.142 — inharmonic, so the seat is a mechanism rather than a note. Same rule as mirror_turn.
sox -n -r $R -c 1 "$D/clack_a.wav" synth 0.07 sine 1480 fade t 0.0005 0.07 0.065 vol 0.95
sox -n -r $R -c 1 "$D/clack_b.wav" synth 0.07 sine 1690 fade t 0.0005 0.07 0.065 vol 0.72
sox -m "$D/clack_a.wav" "$D/clack_b.wav" "$D/clack.wav"
sox "$D/clack.wav" "$D/clack_p.wav" pad 0.12

# 3. the mass landing: a brief low thud under the seat
sox -n -r $R -c 1 "$D/thud.wav" synth 0.20 sine 95:72 \
    fade t 0.001 0.20 0.19 vol 0.24
sox "$D/thud.wav" "$D/thud_p.wav" pad 0.12

# 4. grit at the moment of contact — dry stone texture, not a ring
sox -n -r $R -c 1 "$D/grit.wav" synth 0.05 whitenoise \
    sinc 1200-2300 fade t 0.0005 0.05 0.048 vol 0.55
sox "$D/grit.wav" "$D/grit_p.wav" pad 0.12

# 5. the block settling the last millimetre — a small second contact
sox -n -r $R -c 1 "$D/settle.wav" synth 0.035 sine 1320 \
    fade t 0.0005 0.035 0.033 vol 0.30
sox "$D/settle.wav" "$D/settle_p.wav" pad 0.235

# 6. stone dust settling — gives the cue its full 0.35s with audio rather than silence
sox -n -r $R -c 1 "$D/dust.wav" synth 0.09 brownnoise \
    sinc 1100-2400 fade t 0.005 0.09 0.08 vol 0.12
sox "$D/dust.wav" "$D/dust_p.wav" pad 0.245

# 7. contact edge — a touch of 2.5-5k so the seat reads as stone rather than a tone. Kept small:
#    it must not take the dominant off 1k-2k, which is this cue's whole separation from the other four.
sox -n -r $R -c 1 "$D/edge.wav" synth 0.03 whitenoise \
    sinc 2500-5000 fade t 0.0003 0.03 0.029 vol 0.30
sox "$D/edge.wav" "$D/edge_p.wav" pad 0.12

sox -m "$D/grind.wav" "$D/clack_p.wav" "$D/thud_p.wav" "$D/grit_p.wav" "$D/settle_p.wav" \
    "$D/dust_p.wav" "$D/edge_p.wav" "$D/mix.wav"
## NO LEADING PAD. `pad 0.015 0` silently skipped the START pad (sox warned "pads not applied: 1"
## and I read that as the harmless zero-length one), so removing the stray `0` SHIFTED the audio
## 15ms later and the trim then clipped 15ms of dust tail — which moved rms 0.6 dB and the band
## shares with it, after I had already written the pre-edit numbers into the manifest prompt.
## The cue is its natural length; nothing is padded and nothing is trimmed.
sox "$D/mix.wav" "$D/norm.wav" gain -n -3.4
rm -f "$D/block_seat.ogg"
ffmpeg -v error -y -i "$D/norm.wav" -c:a libvorbis -b:a 80k -ac 1 -ar $R "$D/block_seat.ogg"
[ -s "$D/block_seat.ogg" ] || { echo "REFUSING: no output produced"; exit 9; }
echo "built $D/block_seat.ogg"
