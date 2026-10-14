#!/usr/bin/env bash
## passage_grind — a lever opens a stone passage (DungeonPuzzleLayer.activate_switch, "flip" effect).
## FIFTH of the door_open family, and the most reachable: 13 dungeons author a flip switch, including
## every W1 dragon cave, the Whispering Cave and Castle Harmonia. FireDragonCave floor 4 is a REQUIRED
## gate — the player MUST pull that lever to progress, and hears a wooden door creak for a stone slab.
##
## SEPARATION TARGET: LENGTH is the primary axis, because all four frequency bands are already taken
## by the family (wall_blast 40-250 · plate_engage 250Hz-1k · block_seat 1k-2k · mirror_turn 2k-8k ·
## door_open 40-250). At ~1.25s this is longer than every one of them (0.335 / 0.55 / 0.60 / 0.95 /
## 1.00), and its SHAPE differs from door_open's creak: a mechanical lever clack, then a SUSTAINED
## noise grind, where the door is a tonal creak that decays.
## ⚠️ THIS SCRIPT DOES NOT BYTE-REPRODUCE THE SHIPPED ASSET, AND THAT IS NOT FIXABLE HERE. Its
## noise layers are `sox ... whitenoise`, which sox seeds per run, and it predates the `sox -R`
## fix (see tools/gen_freight_lift.sh, which IS reproducible). So it is the RECIPE -- every layer,
## frequency and gain, which is the provenance the manifest prompt cites -- and the .ogg on disk is
## the authority. Adding `-R` now would make this script emit DIFFERENT audio from the approved cue,
## which is the one thing it must not do.
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
D=tmp/pg
R=44100

# 1. the lever itself — a dry mechanical clack, detuned so it is not a pitched figure
sox -n -r $R -c 1 "$D/clack_a.wav" synth 0.05 sine 1870 fade t 0.0004 0.05 0.047 vol 0.85
sox -n -r $R -c 1 "$D/clack_b.wav" synth 0.05 sine 2130 fade t 0.0004 0.05 0.047 vol 0.60
sox -m "$D/clack_a.wav" "$D/clack_b.wav" "$D/clack.wav"

# 2. a short mechanical release right after it — the catch letting go
sox -n -r $R -c 1 "$D/catch.wav" synth 0.04 whitenoise sinc 900-2600 fade t 0.0004 0.04 0.038 vol 0.45
sox "$D/catch.wav" "$D/catch_p.wav" pad 0.07

# 3. THE GRIND — stone sliding on stone. Sustained, the body of the cue, and what makes it not a door.
sox -n -r $R -c 1 "$D/grind.wav" synth 0.80 brownnoise sinc 260-1400 \
    fade t 0.09 0.80 0.42 vol 0.72
sox "$D/grind.wav" "$D/grind_p.wav" pad 0.16

# 4. the mass moving under it
sox -n -r $R -c 1 "$D/rumble.wav" synth 0.75 sine 78:58 fade t 0.07 0.75 0.60 vol 0.11
sox "$D/rumble.wav" "$D/rumble_p.wav" pad 0.18

# 5. grit riding the grind, so it reads as stone rather than as a tone
sox -n -r $R -c 1 "$D/grit.wav" synth 0.55 pinknoise sinc 1200-3000 \
    fade t 0.10 0.55 0.40 vol 0.34
sox "$D/grit.wav" "$D/grit_p.wav" pad 0.22

# 5b. scrape edge — the only 2-6k content. Without it the cue measured 0.0% above 2k and read as
#     a muffled rumble with no mechanism in it; the lever clack was inaudible under the grind.
sox -n -r $R -c 1 "$D/edge.wav" synth 0.45 pinknoise sinc 2400-6000 \
    fade t 0.12 0.45 0.32 vol 0.15
sox "$D/edge.wav" "$D/edge_p.wav" pad 0.24

# 6. it stops moving — a final seat, quieter than block_seat's since the slab is bigger and slower
sox -n -r $R -c 1 "$D/seat.wav" synth 0.12 sine 150:108 fade t 0.001 0.12 0.115 vol 0.34
sox "$D/seat.wav" "$D/seat_p.wav" pad 1.03

sox -m "$D/clack.wav" "$D/catch_p.wav" "$D/grind_p.wav" "$D/rumble_p.wav" "$D/grit_p.wav" \
    "$D/edge_p.wav" "$D/seat_p.wav" "$D/mix.wav"
sox "$D/mix.wav" "$D/norm.wav" gain -n -2.5
rm -f "$D/passage_grind.ogg"
ffmpeg -v error -y -i "$D/norm.wav" -c:a libvorbis -b:a 80k -ac 1 -ar $R "$D/passage_grind.ogg"
[ -s "$D/passage_grind.ogg" ] || { echo "REFUSING: no output"; exit 9; }
echo "built $D/passage_grind.ogg"
