# Reference voices

These clips are the cast's voices for the free local TTS engine (Chatterbox, cloned zero-shot).
Most are derived from **LibriTTS-R** (Koizumi et al., 2023), licensed **CC BY 4.0**:
https://www.openslr.org/141/ — itself derived from LibriSpeech / LibriVox public-domain audiobooks.
The British voices are derived from **CSTR VCTK Corpus 0.92** (Yamagishi, Veaux & MacDonald, University
of Edinburgh, 2019), licensed **CC BY 4.0**: https://doi.org/10.7488/ds/2645

| file | character | source speaker(s) | processing |
|---|---|---|---|
| rogue.wav | Rogue | 8224 | pitch +1.5 st, formants shifted (rubberband) |
| rogue_alt_F.wav | Rogue (runner-up) | 8224 (9 s) + 8463 (3 s) | concatenated blend |
| bard.wav | Bard | 3575 (+2.5 st) + 4507 | concatenated blend |
| bard_alt_I.wav | Bard (runner-up) | 3575 | pitch +2.5 st, formants shifted |
| bard_alt_K.wav | Bard (runner-up) | 3575 (+2.5 st) + 1580 | concatenated blend |
| mage.wav | Mage | VCTK p254 (Surrey) | 3 sentences concatenated, 24 kHz mono, loudness -20 LUFS |
| cleric.wav | Cleric | VCTK p240 (Southern England) | 4 sentences concatenated, 24 kHz mono, loudness -20 LUFS |

No ElevenLabs output is used as a reference anywhere: its Prohibited Use Policy bars using Output
"as input for any machine learning". The ElevenLabs-rendered clips are kept as audio only.
