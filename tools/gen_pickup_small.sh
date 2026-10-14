#!/usr/bin/env bash
## pickup_small — a small key or blast charge taken off a dungeon floor
## (DungeonMechanics._on_pickup_entered). That site played `chest_open`: 1.48s of "metal latch
## clicking open on a wooden box, brief pause, slow wood creak as heavy lid lifts". There is no box,
## no lid and no latch when you walk over a key — and it took a second and a half to say so.
##
## ⛔ ONE CUE, NOT TWO. The site knows the resource (key vs blast charge) and the TOAST already names
## it ("Found a small key." / "Found a blast charge."). The cue's job is "you have it"; the text
## carries which. Same reasoning as recommending one menu_error for the autogrind refusals rather
## than a bespoke "busy" timbre — do not spend a vocabulary item on a distinction the words carry.
##
## SEPARATION: 250Hz-1k is crowded by the whole reward family (item_obtain 61% · secret_found 78% ·
## save_crystal_activate 60% · chest_open 40%), so this sits higher. LENGTH is the clean separator
## from chest_open (1.48s) and from mirror_turn, the other bright cue (0.60s).
## ⚠️ THIS SCRIPT DOES NOT BYTE-REPRODUCE THE SHIPPED ASSET, AND THAT IS NOT FIXABLE HERE. Its
## noise layers are `sox ... whitenoise`, which sox seeds per run, and it predates the `sox -R`
## fix (see tools/gen_freight_lift.sh, which IS reproducible). So it is the RECIPE -- every layer,
## frequency and gain, which is the provenance the manifest prompt cites -- and the .ogg on disk is
## the authority. Adding `-R` now would make this script emit DIFFERENT audio from the approved cue,
## which is the one thing it must not do.
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
D=tmp/ps
R=44100

# 1. the object leaving the ground — a short dry metallic scrape, no ring
sox -n -r $R -c 1 "$D/lift.wav" synth 0.035 whitenoise sinc 2200-6000 \
    fade t 0.0004 0.035 0.033 vol 0.55

# 2. the jingle: two DETUNED partials. 2640/2960 is ratio 1.121 — inharmonic, so a key reads as a
#    small metal object and not as a two-note chime. Same rule as mirror_turn and block_seat.
sox -n -r $R -c 1 "$D/j1.wav" synth 0.12 sine 2640 fade t 0.0006 0.12 0.115 vol 0.60
sox -n -r $R -c 1 "$D/j2.wav" synth 0.12 sine 2960 fade t 0.0006 0.12 0.115 vol 0.44
sox -m "$D/j1.wav" "$D/j2.wav" "$D/jingle.wav"
sox "$D/jingle.wav" "$D/jingle_p.wav" pad 0.02

# 3. a second, quieter tick — two pieces of metal touching as it is taken, not a melody
sox -n -r $R -c 1 "$D/tick.wav" synth 0.05 sine 1880 fade t 0.0004 0.05 0.047 vol 0.26
sox "$D/tick.wav" "$D/tick_p.wav" pad 0.085

# 4. the heft a blast charge has and a key does not — brief, low, under everything, so ONE cue
#    serves both resources without claiming to be either
sox -n -r $R -c 1 "$D/heft.wav" synth 0.09 sine 170:130 fade t 0.001 0.09 0.086 vol 0.22
sox "$D/heft.wav" "$D/heft_p.wav" pad 0.015

sox -m "$D/lift.wav" "$D/jingle_p.wav" "$D/tick_p.wav" "$D/heft_p.wav" "$D/mix.wav"
sox "$D/mix.wav" "$D/norm.wav" gain -n -5.0
rm -f "$D/pickup_small.ogg"
ffmpeg -v error -y -i "$D/norm.wav" -c:a libvorbis -b:a 80k -ac 1 -ar $R "$D/pickup_small.ogg"
[ -s "$D/pickup_small.ogg" ] || { echo "REFUSING: no output"; exit 9; }
echo "built $D/pickup_small.ogg"
