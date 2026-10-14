#!/usr/bin/env bash
## freight_lift — Rivet Row's HAZARD freight elevator hauling the player up to the dock tier
## (VillageElevator._ride, via RivetRowVillage.gd:203).
##
## AUTHORED because that site played `armor_clank`, whose own prompt is "Medieval plate armor
## clanking together, metal gauntlet striking breastplate in SALUTE, military honor gesture". Its
## only other consumer is data/cutscenes/world1_warden_intro.json step 8 — a WORLD 1 medieval
## warden. Rivet Row is World 4: "Workers' settlement on factory outskirts... smokestacks, graffiti
## wall", built by IndustrialTileGenerator. A plate-armour salute was playing for a pallet lift.
##
## ⛔ THE ARRIVAL ACCENT LANDS INSIDE THE RIDE. VillageElevator.RIDE_TIME is 0.35s and the cue is
## played at ride START with no arrival cue of its own, so an accent later than 0.35s fires after
## the player is already standing on the dock. The seat is at 0.300. This is the axis the other two
## elevator cues fail: steam_hiss is 1.0s (2.9x the ride) and portal_activate 2.0s (5.7x) — both are
## shared with cutscenes (4 and 9 of them), so neither can be shortened here. Declared, not fixed.
##
## ⚠️ MEASURING THIS CUE: a 10 ms RMS window covers 0.38 of a cycle of the 38 Hz chain tremolo and
## ALIASES, reporting a 10 dB null at 0.24s that does not exist. At 2 ms the deepest excursions below
## the body median are 2-4 ms long - periodic roughness, not a dropout. The tell is that the swing
## GROWS as the window shrinks (15.9 -> 18.7 -> 20.7 dB at 10/4/2 ms); a real hole's depth does not
## depend on the window. I nearly rebuilt a correct asset off the aliased reading.
##
## SEPARATION: the UI channel's world events crowd 40-250 (portal_activate, passage_grind, door_open,
## inn_rest, autobattle_off, defer) and 2k-8k (armor_clank, steam_hiss, chalk_tap,
## status_cannot_act). 250Hz-1k holds only plate_engage, which is a 0.55s single click at 523Hz
## against this cue's sustained motor — so the motor's voice goes there.
## ⛔ `-R` ON EVERY SYNTH CALL, AND IT IS LOAD-BEARING FOR PROVENANCE, NOT STYLE. Four layers here
## are `whitenoise`, which sox seeds per run — so without `-R` this script produces a DIFFERENT file
## every time and the prompt's measured figures describe one build nobody else can obtain. Measured:
## the first committed version rebuilt to a non-identical asset. With `-R` the rebuild is
## byte-identical, so "every layer and gain in this script" is checkable rather than asserted.
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)"
D=tmp/fl
R=44100

# 1. the contactor closing — a heavy relay, not a door. Low thunk + the relay's own click.
sox -R -n -r $R -c 1 "$D/thunk.wav" synth 0.055 sine 150:112 fade t 0.001 0.055 0.052 vol 0.34
sox -R -n -r $R -c 1 "$D/click.wav" synth 0.016 whitenoise sinc 700-1500 \
    fade t 0.0003 0.016 0.015 vol 0.28

# 2. the motor, which is the BODY and owns 250Hz-1k. Two detuned partials (330/337) beat at 7Hz,
#    which is what makes it read as a loaded motor instead of a tone; the saw adds the harmonic
#    grit a sine cannot. Rising slightly: the lift is taking up weight.
sox -R -n -r $R -c 1 "$D/m1.wav" synth 0.315 sine 318:348 fade t 0.012 0.315 0.055 vol 0.27
sox -R -n -r $R -c 1 "$D/m2.wav" synth 0.315 sine 325:355 fade t 0.012 0.315 0.055 vol 0.20
sox -R -n -r $R -c 1 "$D/m3.wav" synth 0.315 sawtooth 163:178 fade t 0.015 0.315 0.060 vol 0.13
sox -m "$D/m1.wav" "$D/m2.wav" "$D/m3.wav" "$D/motor.wav"
sox "$D/motor.wav" "$D/motor_p.wav" pad 0.018

# 3. chain rattle over the travel — sparse, high, low level. A freight lift is a chain hoist.
sox -R -n -r $R -c 1 "$D/chain.wav" synth 0.300 whitenoise sinc 1500-4200 \
    tremolo 38 72 fade t 0.02 0.300 0.08 vol 0.12
sox "$D/chain.wav" "$D/chain_p.wav" pad 0.025

# 4. the platform SEATING on the dock tier at 0.300 — inside RIDE_TIME (0.35), see the note above.
sox -R -n -r $R -c 1 "$D/seat.wav" synth 0.085 sine 210:148 fade t 0.0008 0.085 0.080 vol 0.62
sox -R -n -r $R -c 1 "$D/edge.wav" synth 0.030 whitenoise sinc 1100-2600 \
    fade t 0.0004 0.030 0.028 vol 0.40
sox -m "$D/seat.wav" "$D/edge.wav" "$D/seat_mix.wav"
sox "$D/seat_mix.wav" "$D/seat_p.wav" pad 0.300

sox -m "$D/thunk.wav" "$D/click.wav" "$D/motor_p.wav" "$D/chain_p.wav" "$D/seat_p.wav" "$D/mix.wav"
sox "$D/mix.wav" "$D/norm.wav" gain -n -3.2
rm -f "$D/freight_lift.ogg"
ffmpeg -v error -y -i "$D/norm.wav" -c:a libvorbis -b:a 80k -ac 1 -ar $R "$D/freight_lift.ogg"
[ -s "$D/freight_lift.ogg" ] || { echo "REFUSING: no output"; exit 9; }
echo "built $D/freight_lift.ogg"
