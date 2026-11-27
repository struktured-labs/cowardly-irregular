# Parked: crossfade first step after a map build (cowir-sfx, 2026-11-27, on v3.33.842-alpha)

PARKED, never fold. cowir-main 28539: hold the capped-first-step helper until the web build
measures a >= 0.5 s transition frame, or struktured hears the music jump leaving a village.

Measured headless, Dummy audio, 3/3 runs, Harmonia -> W1 overworld:
- OverworldScene build+add in one frame: 141-144 ms; next frame delta 140-146 ms.
- fade-in (0.5 s, -40 -> -10) steps -39.6 -> -27 dB at once (~28% of it); outgoing bed -10.4 -> -23 dB.
- both then ramp on schedule; the fade loses its first ~140 ms as a ~12 dB step, not a hard cut.

To re-measure: copy `test_zz_probe_crossfade_first_step.gd.txt` to
`test/unit/test_zz_probe_crossfade_first_step.gd` and run `slot_xfade.sh.txt` (it copies from
tmp/probe/, so place the probe there) under a box seat. As a guard for the helper: assert the
first step after arming moves volume_db by no more than the clamp allows.
