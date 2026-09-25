# Reference voices

These clips are the cast's voices for the free local TTS engine (Chatterbox, cloned zero-shot).
Each is derived from **LibriTTS-R** (Koizumi et al., 2023), licensed **CC BY 4.0**:
https://www.openslr.org/141/ — itself derived from LibriSpeech / LibriVox public-domain audiobooks.

| file | character | source speaker(s) | processing |
|---|---|---|---|
| rogue.wav | Rogue | 8224 | pitch +1.5 st, formants shifted (rubberband) |
| rogue_alt_F.wav | Rogue (runner-up) | 8224 (9 s) + 8463 (3 s) | concatenated blend |
| bard.wav | Bard | 3575 (+2.5 st) + 4507 | concatenated blend |
| bard_alt_I.wav | Bard (runner-up) | 3575 | pitch +2.5 st, formants shifted |
| bard_alt_K.wav | Bard (runner-up) | 3575 (+2.5 st) + 1580 | concatenated blend |

No ElevenLabs output is used as a reference anywhere: its Prohibited Use Policy bars using Output
"as input for any machine learning". The ElevenLabs-rendered clips are kept as audio only.
