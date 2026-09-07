# Village Sub-Area (Interior) Music — Spec

**Lane:** cowir-music · **Status:** DRAFT awaiting struktured approval · **Date:** 2026-07-11

## Current state (verified on main @ 62c684a7)

- 30 concrete interiors under `src/maps/interiors/`. **Zero have dedicated music** — every
  `_get_music_track()` override just re-asserts the parent village key so music doesn't drop
  on scene change. 7 rooms have ambient SFX loops (forge/chapel/library/scriptorium/office×2).
- The engine seam already exists end-to-end: `BaseInterior._get_music_track()` →
  `SoundManager.play_area_music(key)` → match arm → `_try_play_from_manifest(key)`.
  Adding interior music = new manifest tracks + per-room key returns + dispatch arms.
- Free win: manifest track `shop` ("The Merchant's Welcome", 47.5s loop) exists and
  **nothing plays it** — authored as a shop theme, never wired. Adopt it, don't regenerate.

### Routing bugs found while auditing (flag for cowir-main, not blocking)
- `MapleCommunityCenterInterior` + `EnrichmentAnnexInterior` return `"village"` →
  plays **Harmonia medieval** music inside W2 suburban civic rooms.
- `ScripturaGuildInterior` + `ScripturaBookshopInterior` return `"village"` →
  Harmonia's per-location track instead of `scriptura_village`.
  (Both become moot for rooms that get dedicated tracks below; one-line fixes for any that stay.)

## Proposed tracks — 9 new + 1 adopted

"Certain sub areas," not all: story/identity rooms get music; small flavor rooms
(ledgers, boards, huts, watchtowers, caches) keep inheriting village music + ambience.
Blacksmith stays inherit BY DESIGN — the anvil ambience IS its music.
VertexThreshold stays silent-inherit — the single-room austerity is the statement.

### Type-shared (classic JRPG identity, cross-world)
| key | rooms | palette |
|---|---|---|
| `interior_tavern` | TavernInterior, VillageBar | rowdy-cozy: lute, fiddle, hand drums, foot stomps |
| `interior_inn` | InnInterior, VillageInn | rest/safety: music-box lullaby over soft strings |
| `interior_chapel` | HarmoniaChapel (+future) | sparse organ + soft choir, sacred stillness |
| `interior_library` | HarmoniaLibrary, ScripturaBookshop | celesta + muted harp, quiet study |
| `interior_shop` | ShopInterior, VillageShop | **adopt existing `shop` track** — wire only |

### World-flavored one-offs (satire/identity beats)
| key | room (world) | palette |
|---|---|---|
| `interior_office` | MapleCommunityCenter + EnrichmentAnnex (W2) | EarthBound dept-store muzak, passive-aggressive hold-music cheer |
| `interior_arcade` | MapleHeightsArcade (W2) | chiptune-inside-chiptune attract-mode loop |
| `interior_scriptorium` | ScripturaGuild (W1) | scholarly harpsichord with subtle glitch artifacts (Scriptweaver nod) |
| `interior_union_hall` | RivetRowUnionHall (W4) | brass work-song, solidarity stomp |
| `interior_lounge` | NodePrimeDaemonLounge (W5) | lo-fi/vaporwave chill for off-duty daemons |

## Draft Suno prompts (approve/edit before generation)

1. **interior_tavern — "Ale and Alibis"**
   style: `16-bit SNES tavern theme, rowdy-cozy, lute and fiddle lead, hand drums, foot-stomp accents, major key with a sly modal turn, 104 BPM, loopable`
   prompt: `A medieval tavern where adventurers trade exaggerated stories. Lute and fiddle trade a call-and-response melody over hand drums and stomps. Warm, a little mischievous, one sly minor turn per phrase like a tall tale getting taller. Mugs clink between phrases. Instrumental, loops cleanly.`

2. **interior_inn — "Clean Sheets, Saved Games"**
   style: `16-bit SNES inn theme, gentle lullaby, music box lead, soft string pad, light harp, 72 BPM, warm and safe, loopable`
   prompt: `The safest room in the world: an inn bed you can afford. A music-box melody drifts over soft strings and harp — half lullaby, half save-point chime slowed to bedtime speed. Cozy, unhurried, quietly sentimental. Instrumental, loops cleanly.`

3. **interior_chapel — "Light Through Stained Glass"**
   style: `16-bit SNES chapel theme, sparse pipe organ, soft wordless choir, long reverb tails, D major hymnal, 60 BPM, sacred stillness, loopable`
   prompt: `A small village chapel at midday. Sparse organ chords hold under a soft wordless choir; colored light pools on stone. Reverent but gentle — a place of rest, not judgment. Long silences between phrases feel like held breath. Instrumental, loops cleanly.`

4. **interior_library — "Margin Notes"**
   style: `16-bit SNES library theme, celesta lead, muted harp, soft clarinet, tiptoe staccato, 84 BPM, quiet curiosity, loopable`
   prompt: `A library where the cat is asleep and knowledge is filed slightly wrong. Celesta tiptoes a curious melody over muted harp; a soft clarinet answers like a librarian's raised eyebrow. Hushed, warm, a little conspiratorial. Instrumental, loops cleanly.`

5. **interior_shop** — no generation; wire existing "The Merchant's Welcome".

6. **interior_office — "Your Call Is Important To Us"**
   style: `EarthBound-style department store muzak, cheesy synth marimba, plastic bossa rhythm, elevator-jazz chords, relentlessly pleasant, 96 BPM, satirical, loopable`
   prompt: `Municipal hold music made flesh: a Community Enrichment Annex where the smiles are mandatory. Synth marimba and plastic bossa drums play relentlessly pleasant elevator jazz that never resolves quite right. Cheerful in a way that makes you check the exits. Instrumental, loops cleanly.`

7. **interior_arcade — "Insert Coin (Again)"**
   style: `chiptune arcade attract-mode loop, square-wave leads, fast arpeggios, driving noise-channel drums, bright major key, 140 BPM, nostalgic coin-op energy, loopable`
   prompt: `A suburban arcade running attract screens forever. Bright square-wave leads race over pumping chip drums and arpeggio sparkle — every cabinet begging for one more quarter at once. Pure coin-op nostalgia inside a 16-bit world. Instrumental, loops cleanly.`

8. **interior_scriptorium — "Errata"**
   style: `baroque harpsichord study with subtle glitch artifacts, quill-scratch percussion, occasional tape-stop hiccup, minor key, 92 BPM, scholarly and slightly wrong, loopable`
   prompt: `The Scriptweaver's Guild scriptorium: monks of the patch notes. A tidy harpsichord fugue keeps hiccuping — a note repeats like a stuck key, a bar skips like an edited manuscript. Quill scratches keep time. Scholarly, meticulous, and 2% haunted by revision history. Instrumental, loops cleanly.`

9. **interior_union_hall — "Shift Change"**
   style: `industrial brass work-song, low brass riff, hammered anvil accents on the backbeat, marching snare, work-chant rhythm, C minor, 100 BPM, solidarity and soot, loopable`
   prompt: `A union hall between shifts: brass section as work crew. A low brass riff swings like a shared load, anvil hits land on the backbeat, snare marches without hurry. Tired, proud, unbreakable. Instrumental, loops cleanly.`

10. **interior_lounge — "Uptime Off the Clock"**
    style: `lo-fi vaporwave lounge, warbly synth keys, vinyl crackle, slow chillhop drums, soft sine bass, 76 BPM, digital serenity, loopable`
    prompt: `A lounge where daemons go when their processes sleep. Warbly synth keys drift over vinyl crackle and slow chillhop drums; a sine bass hums like a healthy server room. Peaceful, wry, glowing softly at 3am forever. Instrumental, loops cleanly.`

## Engine wiring (cowir-main's merge surface — coordinate before building)

**Recommended: generic prefix arm with inherit-safe fallback.** In
`_start_area_music_deferred`, before the match:

```gdscript
if area_type.begins_with("interior_"):
    _start_interior_music(area_type)
    return
```

`_start_interior_music(key)`: if manifest has `key` (or `key + "_" + world_suffix`
per-world variant first, monster-sheet pattern) → play it; **if absent, keep current
village music playing** (no stop). The absent-key guard must run BEFORE
`play_area_music`'s `stop_music()` — either short-circuit in `play_area_music` for
`interior_` keys, or move the manifest check ahead of the stop. This makes W2-W6 rooms
whose tracks don't exist yet inherit seamlessly instead of dropping to silence.

Then each participating interior's `_get_music_track()` returns its `interior_*` key
(11 one-line room edits). Rooms not in the table keep their current returns.

**Layering:** music and ambient SFX are separate SoundManager channels — chapel runs
`interior_chapel` music + `ambient_chapel` loop together. No conflict.

**Tests:** extend the cutscene-music orphan audit's resolution set with the `interior_`
manifest keys; add a regression pinning `_start_interior_music`'s inherit-on-missing
behavior; per-room key returns pinned in an interiors test.

## Generation plan (after approval)

- 9 new tracks ≈ 90 credits, ONE browser session (multi `--track-id`, single captcha
  solve if challenged). Can ride the same session as the 5 parked spotlight duel tracks
  → 14 tracks total.
- Encode-drift fix (`-ac 1 -b:a 96k` in convert_to_ogg) lands FIRST so all outputs are
  web-standard 96k mono.
- Manifest entries loop=true; `.import` loop=true; full GUT gate (`--audio-driver Dummy`).
