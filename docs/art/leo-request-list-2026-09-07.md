# Art Requests for Leo — 2026-09-07

Prioritized top-down: #1 is the stuff only you can do well. Everything further
down either has an AI placeholder already in the game or gets one this week —
your versions replace those whenever they land, at your pace. Same drop flow as
always: `.aseprite` into the usual Drive folders, tags on the animations, we
ingest by tag.

## Authoring notes (small, saves us both rework)

- **128×128 frames**, tags name the animations (your `Idle` / `Weak` / `Dead` /
  `ATK` convention is exactly what the pipeline reads — keep naming them
  whatever feels right, we map by tag).
- **Monsters face RIGHT, party characters face LEFT.** Your goblin faces right;
  the rat came in facing left and we mirrored it on ingest — fine either way,
  but as-drawn saves a step.
- Hide or delete backdrop layers before saving (the rogue drop had "Layer 1"
  visible — the exporter now catches it, but it cost a pass).
- The `Weak` / `Dead` split you did for the five heroes is now fully wired
  in-game: Weak plays below 25% HP, Dead is the collapse. It looks great.

## 1. Monster HIT and DEATH frames — highest value, AI cannot do these

AI generation fails on reaction poses every single time (bodies come back
rotated/sprawled). Right now these monsters visibly **neither flinch nor fall**
— they reuse an idle or wind-up frame:

- **Rat** (your 2026-08-20 drop): a hit reaction + a death
- **Goblin**: a hit reaction + a death
- Any other monster you own (bat, slime, spider, skeleton…) that you'd like to
  give real reactions — same two poses each, 1-3 frames apiece is plenty

For Mordaine specifically: story canon is she **dissolves** ("the way a thought
dissolves") rather than falls — if you'd rather sketch 2-3 dissolve keyframes
than a collapse, that's the better ask.

## 2. Cartographer Wraith — new boss, currently a generic specter

New optional W1 dungeon (The Backwards Warren, a map-logic maze) has a boss
called the **Cartographer Wraith** — a ghost that redraws the map around you.
Concept space: spectral surveyor, unrolled charts, compass/quill motifs.
Idle + attack tags minimum; Weak/Dead welcome. We're generating a placeholder
in the meantime, so no rush — but this one deserves your hand.

## 3. Three broken boss frames — repair, not redraw

These sheets are yours-adjacent in style but specific frames are corrupt
(multi-subject/garbled). Generation attempts made them worse, so they're a
surgical fix only you can do:

- `meta_knight` — frames 0, 3, 4
- `masterite_tempo_futuristic` — frame 4
- `masterite_arbiter_futuristic` — frame 6

We can put the current PNGs wherever convenient if you want to patch over them.

## 4. Remaining hero animations (the five starters)

You've delivered Idle / Weak / Dead / attack sets for all five. Still AI-filled
and worth replacing eventually, roughly in play-visibility order:

- **hit** (flinch) — most visible in battle after the ones you've done
- **victory** — end-of-battle pose, every fight
- **walk**, **defend**, **item** — lower priority

## 5. The nine advanced/meta job characters — fully AI today

Guardian, Ninja, Summoner, Speculator, Scriptweaver, Time Mage, Necromancer,
Bossbinder, Skiptrotter. Zero artist art on any of them. Even just an Idle +
ATK per character (your usual base-sprite format) would move them from "AI
mannequin" to "yours" — the rest can be gap-filled. Meta jobs also unlock
portraits downstream, so these ripple further than most sheets.

## 6. Village/tile props — 10 pieces

The medieval village tile seam takes named regions; these are wanted as small
tiles (32 or 64px): TREE, LAMP_POST, BARREL, CRATE, STALL, FENCE, WELL, BANNER,
CART, PLANTER. Whenever, no urgency.

## 7. Overworld walk cycles — optional, AI is passable here

Roaming monsters and NPCs walk the overworld at 32px. We derive/generate these
(they're tiny), so only grab any you personally care about — e.g. the slime or
goblin waddling. Format: 128×128 sheet, 4×4 grid, rows = down/left/right/up.

---
*Anything here can be reordered by whatever you're excited to draw — priority
is our read of impact, not a schedule. — Carmelo & the sprite pipeline*
