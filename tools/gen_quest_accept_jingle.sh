#!/usr/bin/env bash
# Quest-accept ditty (cowir-music): triangle chiptune, G major, same family as quest_complete.
# D5 G5 A5 B5 pickup (16ths) -> held G5+B5+D6 triad with soft echo. ~1.6 s, -16 LUFS, 44.1k stereo.
set -euo pipefail
out=${1:-assets/audio/sfx/quest_accept.ogg}
t=$(mktemp -d); trap 'rm -rf $t' EXIT
n(){ sox -n -r 44100 -c 1 "$t/$1.wav" synth "$2" triangle "$3" fade t 0.005 "$2" "$4" gain -3; }
n a 0.10 D5 0.03; n b 0.10 G5 0.03; n c 0.10 A5 0.03; n d 0.12 B5 0.04
for p in G5 B5 D6; do sox -n -r 44100 -c 1 "$t/e$p.wav" synth 0.9 triangle $p fade t 0.005 0.9 0.6 gain -8; done
sox -m "$t/eG5.wav" "$t/eB5.wav" "$t/eD6.wav" "$t/e.wav"
sox -n -r 44100 -c 1 "$t/bass.wav" synth 0.9 square G3 fade t 0.005 0.9 0.5 gain -16
sox -m "$t/e.wav" "$t/bass.wav" "$t/f.wav"
sox "$t/a.wav" "$t/b.wav" "$t/c.wav" "$t/d.wav" "$t/f.wav" "$t/mono.wav" echo 0.8 0.6 120 0.25 pad 0 0.25 reverse silence 1 0.01 -60d reverse
sox "$t/mono.wav" -c 2 "$t/st.wav" remix 1 1 fade 0 -0 0.08
ffmpeg -hide_banner -loglevel error -y -i "$t/st.wav" -af loudnorm=I=-16:TP=-3:LRA=7,aresample=44100 -ar 44100 -ac 2 -c:a libvorbis -q:a 6 "$out"
