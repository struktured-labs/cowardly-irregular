#!/usr/bin/env bash
# Recipe pip tick (cowir-sfx): one short square blip per pip the reveal lights, rising a step per pip.
# A-lydian steps (A5 B5 C#6 D#6 E6 F#6 G#6 A6 B6 C#7) so ten in a row climb into recipe_learned's chord.
# Usage: tools/gen_recipe_pip_tick.sh [out_dir]   -> recipe_pip_01.ogg .. recipe_pip_10.ogg, ~70 ms, peak -9 dBFS each (too short for LUFS).
set -euo pipefail
out=${1:-assets/audio/sfx}
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
mkdir -p "$root/tmp" "$out"
t=$(mktemp -d -p "$root/tmp"); trap 'rm -rf "$t"' EXIT
i=0
for p in A5 B5 C#6 D#6 E6 F#6 G#6 A6 B6 C#7; do
  i=$((i+1)); n=$(printf %02d $i)
  sox -n -r 44100 -c 1 "$t/a.wav" synth 0.05 square "$p" fade t 0.002 0.05 0.035 gain -12
  sox -n -r 44100 -c 1 "$t/b.wav" synth 0.05 triangle "$p" fade t 0.002 0.05 0.04 gain -6
  sox -m -v 1 "$t/a.wav" -v 1 "$t/b.wav" "$t/m.wav" pad 0 0.02
  sox "$t/m.wav" -c 2 "$t/s.wav" remix 1 1 gain -n -9
  ffmpeg -hide_banner -loglevel error -y -i "$t/s.wav" -ar 44100 -ac 2 -c:a libvorbis -q:a 6 "$out/recipe_pip_$n.ogg"
done
