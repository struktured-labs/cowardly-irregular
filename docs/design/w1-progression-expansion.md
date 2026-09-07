# W1 Progression Expansion — Design Doc

*Author: cowir-main, 2026-07-13. Handoff-ready for codex or a fresh lane.*

## Why this doc exists

Playtest of v3.33.147 surfaced two design gaps in W1:

1. **Castle Harmonia is a single 20×16 throne room.** Mordaine — *"the architect of World 1, first mask of the Calibrant, sorceress-usurper of Castle Harmonia"* — is reached by walking 8 tiles from spawn. The climactic W1 encounter has no ceremony.
2. **W1 outside Harmonia is scaffold-only.** Sandrift, Eldertree, Grimhollow, Ironhaven, Frosthold each contain shops + inn + walkable tiles — and zero quests, zero named encounters, zero reason to visit.

Data audit:

| Element | Present | Wired |
|---|---|---|
| 4 W1 Masterites (Warden/Arbiter/Tempo/Curator "medieval") | ✅ monster data, bestiary, sprites | ❌ orphaned in `enemy_pools.masterite_medieval` — not placed in any dungeon |
| 4 elemental dragons | ✅ everything | ✅ 4 dragon caves |
| Cave Rat King | ✅ | ✅ Whispering Cave |
| Chancellor Mordaine | ✅ (L20, HP1500) | ✅ Castle Harmonia (single room) |
| Non-Harmonia W1 quests | ❌ | ❌ (0/5 villages) |

Struktured picked **full W1 expansion** (Option C) in msg during v3.33.147 playtest.

## Design principles

- **Progression curve**: Rat King (L10) → 2 Masterites (L7-8, out-of-order OK, they're mid-arc encounters) → 4 dragons (L14-18) → 2 Masterites → Mordaine (L20). Level 7-8 Masterites work as "learn your kit" encounters before dragons demand it.
- **Each village has a reason to exist**: 1-2 authored quests + 1 Masterite-adjacent story beat OR 1 environmental discovery. Not filler.
- **Voice consistency**: cowir-story's economy-of-words register (Theron post-chapter1). No fantasy cliché. "The second thing tells the story" (their msg 2526 signature).
- **No Calibrant reveal in W1**. Mordaine is just the usurper. Masterites are just archetypes with jobs.
- **Framework-safe**: any new AreaTransition must pass `test_overworld_reachability_framework` (nearest-hit routing, no eclipsed transitions).

## Work already shipped

- **`feature/story-castle-harmonia`** (cowir-story msg 2526): Castle content pack — 11 examine_texts, 5 corrupt-guard/servant dialogue trees (hollowing escalates by floor), sealed-gate puzzle strings, `world1_throne_room_approach.json` cutscene. Decoupled from layout. Merge-ready.
- **`_NAMED_BOSS_OVERRIDES`** in `reference_library.py` (cowir-sprites v3.33.146): sprite-drift backstop. Any future Masterite art regen inherits per-boss overrides.
- **cowir-sprites Tier B pre-authored**: Tempo of the Rush Hour / Shift / Clock Cycle / Sequence — ready to fire on W2-W6 playtest signal (not needed for W1).

## Task lanes

### Lane A — `cowir-overworld`: Castle Harmonia multi-floor layout
- File: `src/maps/dungeons/CastleHarmonia.gd`
- Currently: `total_floors = 1`, single 20×16 grid.
- Target: **3 floors** matching cowir-story's narrative structure (foyer / council / apartments) + Mordaine sanctum:
  - **F1 Foyer**: entry, 2 corrupt guards (`castle_guard_young`, `castle_guard_captain`), examine tiles (petrified courtier, overpainted tapestry). Stair up to F2.
  - **F2 Council**: petrified courtiers, `castle_guard_bureaucrat` encounter, sealed gate puzzle (Warden-taught cave ability opens; see `castle_harmonia_broken_seal` examine hint). Stair up to F3.
  - **F3 Apartments+Approach**: `castle_guard_husk` guarding the approach + `castle_servant_witness` (non-hostile NPC, floor 3 dialogue). Trigger `world1_throne_room_approach` cutscene on the door tile → chains into `world1_mordaine_intro` → Mordaine battle.
- Use DragonCave's `_parse_layout` letter markers (`U`/`D`/`B`/`M`/`.`/`T`) for stair transitions.
- Merge cowir-story's `feature/story-castle-harmonia` into the layout PR when it lands.
- Ensure new AreaTransitions pass the reachability framework.

### Lane B — `cowir-overworld` (or `cowir-battle`): place 4 W1 Masterites
Suggested placement (one per village pair, tuned for level curve):

| Masterite | Level | Village / Dungeon | Story hook |
|---|---|---|---|
| `masterite_warden_medieval` (Old Guard) | L7 | **Sandrift** — desert village guarding the trade road | Warden refuses to let anyone pass without proof of "legitimate business." Rat King defeat = the proof. Encounter fires on first entry post-rat-king. |
| `masterite_tempo_medieval` (of the Hunt) | L7 | **Eldertree** — forest village that lost its rangers | Tempo hunts intruders through the woods; encounter on entering the treehouse interior OR the outskirts. |
| `masterite_arbiter_medieval` (of Steel) | L8 | **Grimhollow** — mining village, corrupted foreman | Arbiter judges the party at the mine entrance. Wins → gains passage to a dragon cave downstream. |
| `masterite_curator_medieval` (of the Flame) | L8 | **Ironhaven** — coastal village near the fire dragon cave | Curator tends a warped flame at the temple; encounter is a duel of belief. |
| (Frosthold left un-Masterited)| — | **Frosthold** | Gets a quest-only presence — see Lane C. |

- Each encounter fires ONCE per save. Uses existing spotlight-duel-adjacent shape? Or one-off `BossTrigger`? Decision to lane owner — recommend `BossTrigger` for consistency with the dragon caves.
- Reward drops → boss-defeat flag (`w1_warden_defeated` etc.) → potentially gates a follow-up quest.

### Lane C — `cowir-story`: 5 village quests
- 1-2 quests per village. Filename convention `w1_<village>_<slug>.json` under `data/quests/`.
- Each quest gives a REASON to visit that village. Suggestions per village:

| Village | Quest hook |
|---|---|
| Sandrift | *"Water on the Road"* — trade caravan blocked; Warden encounter unblocks. |
| Eldertree | *"The Rangers' Empty House"* — find out what happened to Eldertree's rangers (they're being hunted by the Tempo). |
| Grimhollow | *"Foreman's Ledger"* — the foreman writes weird things now. Ties to the Arbiter. |
| Ironhaven | *"The Flame That Speaks Wrong"* — temple flame no longer burns straight. Ties to the Curator. |
| Frosthold | *"Meltwater Clock, Broken Again"* — quest-only, ties Frosthold to Mordaine's magic reach (frost failing in her presence). Hint that Mordaine's usurpation touches EVERYTHING in W1. |

- Voice: cowir-story's Theron-register economy of words. Guards' hollowing pattern from castle content pack could echo in Curator/Warden dialogue.
- No Calibrant reveal. Reference "the chancellor" as vague, uneasy authority.

### Lane D — `cowir-cutscenes` (optional)
- If any Masterite encounter deserves a staged cutscene (Warden judgment ceremony? Arbiter courtroom scene?) — cowir-cutscenes ships the JSON.
- Otherwise Masterites use standard `BossTrigger` intro (console fallback if no `boss_cutscene_id`).

### Lane E — `cowir-battle`: Masterite kit balance
- Verify each Masterite's stats + kit read as intended difficulty (L7-8 mid-encounters, not spike bosses).
- Add `boss: true` flag if missing — currently the grep found them as `masterite_*_medieval` monsters WITHOUT the `boss` tag. Confirm intended.
- If any Masterite kit is missing a signature ability, author it.

## Deployment plan

Bundle-fold as v3.33.148:
- Castle layout (Lane A) + Castle content (already shipped `feature/story-castle-harmonia`)
- All 4 Masterites placed (Lane B)
- 5+ village quests (Lane C)
- Full suite gate → deploy → fold PR → relaunch.

Optional split if lanes finish at different rates:
- **v3.33.148**: Castle Harmonia multi-floor (A + already-shipped story pack)
- **v3.33.149**: Masterite placements (B + D + E)
- **v3.33.150**: Village quest content (C)

Each ships independently — no coupling between them.

## Regression tests to add

- `test_castle_harmonia_multi_floor_structure.gd` — pin `total_floors >= 3`, each floor has `entrance`/`stairs_up`/`stairs_down` spawn points.
- `test_w1_masterites_are_placed.gd` — assert each `masterite_*_medieval` is referenced in at least one village's/cave's encounter setup.
- `test_w1_villages_have_quests.gd` — assert each of Sandrift/Eldertree/Grimhollow/Ironhaven/Frosthold has ≥ 1 quest file with matching `location`.
- Extend `test_village_reachability_framework.gd` to cover Castle Harmonia's new floors.

## Handoff notes

- **cowir-story is DONE** for Castle. Their `feature/story-castle-harmonia` is merge-ready and content-complete for the castle portion. Village quests (Lane C) are new work.
- **cowir-overworld is not yet started** on Castle layout. Lane A is highest priority — user is blocked from finishing W1 until Castle is walkable-through.
- **Masterites (Lane B) don't block anything** — user can beat W1 without them. Ship whenever.
- **Village quests (Lane C) don't block anything** either — ship in parallel.
- **Framework regressions**: extending `test_overworld_reachability_framework.gd` to include Castle Harmonia's transitions catches any new eclipse bug during the redesign.

## Files under active refactor

- `src/maps/dungeons/CastleHarmonia.gd` — Lane A owner (currently untouched since scaffold)
- `data/examine_texts.json` — cowir-story shipped 11 entries (merge cleanly)
- `data/castle_harmonia_narrative.json` — NEW file from cowir-story (guards + witness + puzzle)
- `data/cutscenes/world1_throne_room_approach.json` — NEW cutscene from cowir-story
- `data/quests/w1_*.json` — Lane C new files
- `data/monsters.json` — Lane E may edit Masterite `boss` flag / kit
- `data/enemy_pools.json` — Lane B may add per-village encounter pool refs

## Success criteria

A fresh save can:
1. Beat Rat King in Whispering Cave (existing)
2. Enter Sandrift → get a quest → fight Warden → get story hook toward next area
3. Traverse 2+ non-Harmonia villages, each with authored purpose
4. Enter Castle Harmonia and traverse 3 floors, fighting corrupt guards, reading environmental storytelling, then face Mordaine
5. Beat Mordaine to unlock W2

The current build only does 1 + 5 (skipping 2/3/4 entirely).
