#!/usr/bin/env bash
# Recipe-learned fanfare (cowir-sfx): a card snaps down, three quick "script runs" ticks, then an A-lydian chord.
# A major with a raised 4th (D#) so it cannot be mistaken for level-up (C major) or quest jingles (G major).
# ~1.5 s, -16 LUFS, 44.1k stereo. Usage: tools/gen_recipe_learned_jingle.sh [out.ogg]
set -euo pipefail
out=${1:-assets/audio/sfx/recipe_learned.ogg}
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
mkdir -p "$root/tmp"
t=$(mktemp -d -p "$root/tmp"); trap 'rm -rf "$t"' EXIT
R=44100
## 1. the card snap: a short bright noise slap with a body thump under it
sox -n -r $R -c 1 "$t/snap_hi.wav" synth 0.035 whitenoise gain -8 highpass 2500 fade t 0.001 0.035 0.03
sox -n -r $R -c 1 "$t/snap_lo.wav" synth 0.06 sine 180 fade t 0.001 0.06 0.05 gain -10
sox -m -v 1 "$t/snap_hi.wav" -v 1 "$t/snap_lo.wav" "$t/snap.wav" pad 0 0.05
## 2. three square-wave ticks rising, the script running
tick(){ sox -n -r $R -c 1 "$t/$1.wav" synth 0.045 square "$2" fade t 0.002 0.045 0.03 gain -14 pad 0 0.025; }
tick k1 A5; tick k2 C#6; tick k3 D#6
## 3. the reveal: triangle arpeggio into a held lydian chord with a soft square bass
n(){ sox -n -r $R -c 1 "$t/$1.wav" synth "$2" triangle "$3" fade t 0.004 "$2" "$4" gain -7; }
n a1 0.09 A4 0.03; n a2 0.09 C#5 0.03; n a3 0.09 E5 0.03
for p in A5 C#6 D#6 E6; do sox -n -r $R -c 1 "$t/c$p.wav" synth 1.0 triangle $p fade t 0.004 1.0 0.7 gain -14; done
sox -m -v 1 "$t/cA5.wav" -v 1 "$t/cC#6.wav" -v 1 "$t/cD#6.wav" -v 1 "$t/cE6.wav" "$t/chord.wav"
sox -n -r $R -c 1 "$t/bass.wav" synth 1.0 square A2 fade t 0.004 1.0 0.7 gain -20
sox -m -v 1 "$t/chord.wav" -v 1 "$t/bass.wav" "$t/tail.wav"
sox "$t/snap.wav" "$t/k1.wav" "$t/k2.wav" "$t/k3.wav" "$t/a1.wav" "$t/a2.wav" "$t/a3.wav" "$t/tail.wav" "$t/mono.wav" \
    echo 0.8 0.55 110 0.22 pad 0 0.2 reverse silence 1 0.01 -60d reverse
sox "$t/mono.wav" -c 2 "$t/st.wav" remix 1 1 fade 0 -0 0.08
ffmpeg -hide_banner -loglevel error -y -i "$t/st.wav" -af loudnorm=I=-16:TP=-3:LRA=7,aresample=$R -ar $R -ac 2 -c:a libvorbis -q:a 6 "$out"
