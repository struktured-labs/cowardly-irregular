# Art Request for Leo: the Fighter's **Provoke** (2026-11-07)

struktured played it and called the current Provoke "jank". It is the one Fighter battle move without your hand on it,
so we'd love your version. It joins the standing asks beside the Bard's **Lullaby**, **Battle Hymn** and
**Inspiring Melody**.

## What Provoke does

A taunt: **"Force an enemy to target you for 2 turns."** The Fighter calls one enemy out and makes himself the target,
so it should read as a challenge: confident, a little cocky, aimed AT the enemy, not an attack.

## What's there now, and why it's jank

`fighter-provoke-current.png` (next to this file): 4 frames from an early composite in a *different stance* from your
IDLE (sword raised diagonally, a red glow). It never matched your Fighter, so it pops out of idle and back.

**In the meantime** the game plays a PROVISIONAL built only from your own frames, re-sequenced, no new pixels:
IDLE 0 → Celebration 2 (sword pointed at the foe) → Celebration 5 (flourish) → Celebration 2 → Celebration 1 (settle).
It's a stopgap; yours replaces it outright.

## Suggested beat (yours to change)

1. **Stance shift** out of IDLE: weight forward, feet planted.
2. **The taunt:** sword pointed straight at the enemy, then a "come at me" beckon with the off hand, or the flat of
   the blade banged on the pauldron.
3. **Hold** the challenge for a beat (this is the frame the player reads).
4. **Settle** back toward the IDLE pose, so the hand-off to IDLE doesn't pop.

## Specs

| | |
|---|---|
| Frame size | **128×128**, same as your other Fighter tags (we ingest 2× nearest-neighbour to 256) |
| Frames | **4-6** is plenty |
| Timing | per-frame timing is supported, so hold whatever should hold (the provisional runs 80/200/140/130/75 ms) |
| Facing | **LEFT**, like your IDLE: party characters face left, toward the enemies |
| Chaining | starts from and ends near **IDLE frame 0**; the game returns to IDLE right after |
| Palette | your Fighter palette as-is |

## Delivery

Add a tag named **`Provoke`** to `Main Fighter animations.aseprite` (we map by tag, so the name just needs to be
unique), hide any backdrop layers, and drop it in the usual Drive folder. We ingest by tag with nearest-neighbour
scaling only: no recolour, no resampling.

*(For us, on delivery: replace `assets/sprites/jobs/fighter/provoke.png` and `frame_durations_ms.provoke` in
`data/sprite_manifest.json`, re-pin with `tools/update_artist_ledger.py`, mark the source as artist, and delete
`test_the_provisional_provoke_is_the_artists_own_frames.gd`, which exists only to keep the stopgap honest.)*
