# Store screenshot captions — Cowardly Irregular

Shot against **`v3.33.262-alpha`** (`3c96bcc2`) unless noted, sandboxed profile, debug overlay
and all 34 tutorial hints suppressed at runtime. Nothing here was persisted and no game file
was edited.

⚠️ **Mixed vintage, stated so nobody assumes otherwise.** The ten villages, interiors, cave and
battle were re-shot at `.262` on 2026-09-09. The Warren floors, Infernal Grotto, the two field
elites, `grimhollow_spiral` and `battle_storm` are still `.225`/`.239` captures — the scenes
themselves have not changed materially, but they are older frames and `battle_storm` in
particular carries the caveat below.

Order below is the recommended gallery order: itch shows the first image largest, so the
battle leads.

---

### `battle_storm.png` — **lead image**
Five-job party, live turn order, and a command menu that offers to hand the turn to your own
autobattle script. The party banters mid-fight ("My turn. Hand on the stick, not the
script."). The `~ STORM ~` tag in the corner is not decoration — weather drives real damage
and accuracy modifiers, and the game insists on telling you so rather than hiding it in a
tooltip.

⚠️ **Caveat for whoever picks the final set:** the storm reads only as that text tag. The
overlay tint and rain are both alpha 0.2 and the rain only covers the top ~150px, so over a
bright daytime background it is invisible. The shot is honest but the weather is doing more
mechanically than the frame shows.

### `battle.png`
The same five-job battle with the weather off and the command menu open on **`Auto >`**, tooltip
legible: *"Run this character's autobattle script, edit it, or delegate every turn."* Turn order
bottom-left, full party stats right, and the banter running underneath — Cleric on the ledger of
injuries, Fighter answering *"My turn. Hand on the stick, not the script."*

📌 **For whoever picks the final set: this may be the stronger LEAD.** `battle_storm` leads today
and carries my own caveat that its weather "reads only as that text tag" over a bright sky. This
frame has no such gap between what it shows and what it claims — the autobattle hook, the thing
that makes this combat system unusual, is spelled out in a tooltip a reader can actually read. I
have placed it second rather than reordering the lead unilaterally; swapping 01 and 02 is a
one-line change to this file and the gallery tool will follow.

### `infernal_grotto_f3.png` — **the one I would pick second**
Floor 3 of 5 in the Infernal Grotto, lit only by what you're carrying. A chest, a pressure
plate, and a line of flavour text that does more character work than any screenshot caption
could: *"Something ahead is guarding treasure. Something behind you is louder."* If only one
dungeon shot ships, this is it.

### `warren_lever_portals.png`
The Backwards Warren, floor 3 of 4 — the optional W1 dungeon built around going *down to go
up*. Visible: a lever, a pressure plate, portal markers, and the floor banner. The puzzle
layer is the point; portals pair across floors and one plate is a decoy.

### `warren_wrap_field.png`
Floor 2 of the same dungeon — the infinite wrap field, where walking off one edge returns you
to the other and a hidden switch is somewhere in it.

### `grimhollow_spiral.png`
Grimhollow, the sunken swamp hamlet. The village proper sits in a pit; the switchback ramps
on the right are the spiral descent down to it, and the mossy green cliff faces are derived
geometry, not hand-drawn tiles. Two shopfronts and an interact prompt are live in frame.

### `field_elite_medieval.png`
The World-1 field elite — a dark knight standing in Eldertree Forest with the purple tell
reading *"It is watching you."* This is the elite a new player actually meets, in the world
they start in. Walking into one opens a choice, Fight or Leave it, so the encounter is always
yours to decline.

Re-shot at `.293` on 2026-09-10, after `dark_knight` finally got its own overworld sheet
(`cd6e84b8`). The frame it replaces was taken while the sheet was newer and rougher; the
knight now reads as armour rather than as a dark smudge, and the tell is legible.

⚠️ **Honest note, and it is the same one the steampunk shot carries.** At overworld zoom the
elite is still small — perhaps 30px of dark armour against dark green. I tried a 2x camera
zoom to fix exactly this and it made the shot worse: the elite barely grew and the purple
tell left the frame entirely (measured, screen y = -68). Zoom magnifies about the camera
centre and the framing offset was tuned at 1x. **If this feature ever needs a flattering
screenshot rather than an accurate one, the shot is the Fight-or-Leave dialogue, not the
overworld sprite** — the dialogue is UI, drawn at readable size, and it is the part of the
feature a player actually interacts with.

### `field_elite_prompt_medieval.png`
**The shot that actually sells the mechanic.** Walking into a field elite opens the game's own
choice menu — *Fight* / *Leave it* — with the input hints spelled out for keyboard, gamepad and
mouse. The elite is unfairly strong on purpose, so the encounter being declinable is the whole
design, and this is the frame that shows it. The world dims behind it with the knight and the
purple tell still visible below.

Captured `.293`, 2026-09-10. **How it was produced, stated because it matters:**
`RoamingMonster._present_elite_prompt()` is called directly rather than by walking the player
into the collider. That is the same method contact reaches, building the same menu with the
same two options — the frame is one a player can produce, and nothing in the capture
constructs UI the game would not. It does not exercise the collision path.

⚠️ The panel sits at the top of the screen, which is the game's own layout, and the dim makes
the elite harder to see than in the overworld frame. The two shots are complements: one shows
the encounter in the world, this one shows what you can do about it.

### `field_elite_steampunk.png`
A field ELITE — a brass golem loose in the Clockwork Dominion, aura up, and the game telling
you in purple exactly what you think it is: *"It is watching you."* Walking into one opens a
choice, Fight or Leave it, so the encounter is always yours to decline.

⚠️ **Honest note:** at overworld zoom the elite reads as a small sprite and the purple tell
has weak contrast on tan ground. It is a correct capture of the feature, not a flattering
one. See "Not in this set" for the related sprite bug.

### Baseline set (shot 2026-08-30, still current)
`harmonia_village` · `ironhaven_village` · `frosthold_village` · `sandrift_village` ·
`eldertree_village` · `grimhollow_village` · `inn_interior` · `tavern_interior` ·
`shop_interior` · `whispering_cave` — villages and interiors across the first world.
`title_screen.png` is the source for the provisional cover.

`eldertree_village` is here because the masterite silhouette fix at `.267` restored it (see
below); it had a restoration but never a POSITION, which is how it shipped for a day without
one. `grimhollow_village` carries the Witch's Hut and the Lantern Debt Office door prompts —
good flavour naming — but it is the sparsest of the village frames, with large plain brick
areas and the player half-cut at the bottom edge. Last of the villages on purpose.

---

## Not in this set, and why

- **`infernal_grotto_f4` — DROPPED.** Setting `current_floor = 4` produced a frame still
  labelled "Floor 3 / 5" and pixel-identical to floor 3 to within 0.032% (animation flicker
  only, against 0.877% between genuinely different floors). `FireDragonCave` does not honour
  `current_floor` the way `ContrarianDepths` does. A mislabelled screenshot is worse than a
  missing one, so it is not here.
- **`eldertree_canopy` — DROPPED.** Does not show a canopy. Renders as flat tan brick with a
  rigid 4x4 grid of identical soldier sprites (the "training hollow" from the layout legend),
  which reads as a spawn bug rather than a village. The 2026-09-06 canopy elevation is not
  visible in a bare-instantiated capture. Needs shooting through real gameplay, or the
  elevation does not build outside GameLoop's map setup.
- **`brasston_lift` — DROPPED.** The village renders fine but the brass work-deck lift, the
  entire reason for the shot, is not in frame.
- **Elevator mid-ride — DROPPED, and now for a measured reason rather than an unmet one.**
  It was right that scene instantiation cannot produce it: the car only exists inside
  `interact()`. `tools/store_shot_elevator.gd` now drives a real ride and captures on measured
  progress (`distance(car, origin) / span`, window 0.30-0.70) rather than on a timer. It works
  — and it establishes that the shot cannot:

  ```
  [SHOT] rider: moved 0.0px of 64.0 (car has moved 19.9px)
  ```

  `interact()` tweens the CAR and calls `player.teleport(destination)` only AFTER the tween
  finishes, so **mid-ride the pad slides by itself while the rider stands at the bottom.** With
  a 64px (two-tile) span, a 32x32 procedurally-drawn pad and no shaft or motion cue, a still
  frame reads as a loose tile drifting, not as riding a lift. Nothing framing or zoom can fix;
  it would need an animation, or a rider who is on the car during the ride.

  Filed for whoever owns exploration: the rider not being on the car for those 0.35s is a
  polish detail, not a bug — the teleport lands correctly — but it is why this feature has no
  still image.

## ✅ RESOLVED (was: 🐞 `dark_knight` has no sprite)

**Fixed. Sheet landed `3caff5d6` (2026-09-07, v3.33.228-alpha) and was improved at `cd6e84b8`
(2026-09-09, shipped in `.291`). `field_elite_medieval.png` is now in this set, re-shot at
`.293` on 2026-09-10.** The text below is kept as the record of what was wrong.

The World-1 field elite rendered as a **solid magenta placeholder box**. Measured across the
whole roster, with controls in both directions:

```
dark_knight          *** NO SPRITE ***     per_world.medieval   <- the starting world
unassuming_dog       OK (2)                    suburban
brass_golem          OK (2)                    steampunk
rust_elemental       OK (2)                    industrial
data_wraith          OK (2)                    futuristic
optimization_itself  OK (2)                    abstract
controls: goblin OK(2)  skeleton OK(4)  bat OK(9)  zzz_no_such_monster -> none (expected)
```

Five of six were fine; the missing one was the only elite a new player can meet. The fix was
a single asset at overworld roamer scale. The W1 elite shot was blocked until then, which is
why `field_elite_steampunk.png` exists at all — it was the substitute.

## Provenance

Every frame above was reviewed individually, not accepted on a zero exit code. The capture
tooling prints each file's byte size because the failure that matters here is silent: a
dungeon that loads, captures and exits 0 while rendering an empty grey void — measured at
7.7 KB where a populated scene is 50–300 KB.


---

## 2026-09-09 refresh — what changed and what did not

Re-shot at `.262`: `harmonia_village` · `ironhaven_village` · `frosthold_village` ·
`sandrift_village` · `grimhollow_village` · `inn_interior` · `tavern_interior` ·
`shop_interior` · `whispering_cave` · `battle`. All 11 captures reviewed individually; none
was a void (50-183 KB, well clear of the 7.7 KB empty-scene tell).

**Honest result: the refresh is a currency fix, not a visible upgrade.** Grimhollow grew 23%
and Eldertree 44% in file size from the 2026-09-06 elevation pass, but neither reads
differently in a storefront frame. The reason to ship them anyway is that a screenshot from a
build two weeks behind misrepresents what a buyer downloads.

### `eldertree_village` — DROPPED AGAIN *(superseded — see the `.267` section below)*
> ⚠️ **This verdict was REVERSED.** The masterite silhouette fix at `v3.33.267-alpha` restored
> this shot to the set; the heading is kept as the record of what was wrong and why it took two
> drops to find. It ships, and it is positioned with the villages above.
Roughly twelve identical armed NPCs stand in a rigid 4x4 formation across the middle of the
frame, and the canopy tier the village is named for is not visible. I dropped the `.239`
capture for this and it is unchanged at `.262`.

Checked before calling it anything: `EldertreeVillage.gd` authors a *Training Hollow* building
with a keeper named Ranger Oak — not twelve soldiers — and `BaseVillage` has no guard-spawn
loop. A scene probe found **12 DialogueBox controls and 14 Sprite2Ds**, so these are real NPC
nodes, not an unsliced spritesheet (the guardian job sheets are 4x1 strips, which cannot
produce a 4x4 grid). Whether a training ground full of identical trainees is intended is
cowir-overworld's call; it is not a defect I can assert, only a frame I would not ship.


---

## 2026-09-09 later — masterite silhouette fix, re-shot at `v3.33.267-alpha`

`MasteriteEncounter._build_silhouette` assigned a 128x128 overworld walk sheet straight to a
Sprite2D with no region, so Godot drew all sixteen 32px frames at once — a block of identical
armed figures standing in the village. That is what I twice mistook for a crowd of NPCs and
twice dropped `eldertree_village` for. Found by cowir-overworld; fixed in `.267`
(`region_enabled` + `region_rect`).

**`eldertree_village` is BACK IN THE SET.** One correctly-framed figure now stands in the
clearing — Tempo of the Hunt as a landmark, which is what the encounter is meant to read as.

⚠️ **Only TWO of the four affected villages actually changed in frame, and I had claimed
three.** Measured after re-shooting:

```
eldertree    dropped -> 79,594 B    changed, grid gone
grimhollow    96,380 -> 91,655 B    changed
ironhaven     70,197 -> 70,197 B    BYTE-IDENTICAL
sandrift      75,787 -> 75,778 B    9 bytes, capture noise
```

Ironhaven's frame is pixel-identical before and after a fix that provably changed the code, so
its masterite was never inside the captured region — a bare-instantiated village shows one
screen, not the whole map. I had told cowir-overworld that Grimhollow, Ironhaven and Sandrift
were "shipping right now with a smeared mini-boss". Two of those three were not. The bug was
real and in all four scenes; it was only *visible* in two of these frames.


## 2026-09-11 — STALENESS AUDIT (no re-shoot; this is the work list for one)

Shots in this set were last re-taken at **`v3.33.267-alpha`**. The store now serves
**`v3.33.299-alpha`** — 32 tags later. Rather than re-shoot blind at a moment when the box was
under load average 20.9 with 19 gate processes, this is the measurement a re-shoot needs:
*which shots depict something that has actually changed.*

**Method.** For each shot, map to its scene file by exact basename (`frosthold_village` →
`FrostholdVillage.gd`), excluding `test/`, then ask whether that file changed in
`v3.33.267-alpha..v3.33.299-alpha`. 899 files changed in that range.

### ⛔ Depicts a scene file that CHANGED — re-shoot these first (9)

| shot | scene file |
|---|---|
| `eldertree_village` | `EldertreeVillage.gd` |
| `frosthold_village` | `FrostholdVillage.gd` |
| `grimhollow_village` | `GrimhollowVillage.gd` |
| `harmonia_village` | `HarmoniaVillage.gd` |
| `inn_interior` | `InnInterior.gd` |
| `ironhaven_village` | `IronhavenVillage.gd` |
| `sandrift_village` | `SandriftVillage.gd` |
| `shop_interior` | `ShopInterior.gd` |
| `tavern_interior` | `TavernInterior.gd` |

Two of these have named, announced content changes that a screenshot would show: Frosthold
gained its pines and Harmonia gained the hedge border and nook Elixir, both in the `.299` batch.
The other seven are "the file moved", which is a candidate, not proof the *frame* differs.

### ✅ Scene file unchanged since the shot (2)

`title_screen` (`TitleScreen.gd`) · `whispering_cave` (`WhisperingCave.gd`)

⚠️ Unchanged scene file does **not** mean the frame is current — a shot can go stale through a
sprite, a font, a HUD overlay or a caption rendered on top of it. `title_screen` in particular
renders a controls table that several lanes edited this session. **This column means "the scene
script did not move", nothing wider.**

### ? Not mapped — needs a hand check (9)

`battle` · `battle_storm` · `field_elite_medieval` · `field_elite_prompt_medieval` ·
`field_elite_steampunk` · `grimhollow_spiral` · `infernal_grotto_f3` · `warren_lever_portals` ·
`warren_wrap_field`

These are battle surfaces, overworld encounters and dungeon floors — **not single scene scripts**,
so the exact-name mapping does not reach them. `Infernal`, `Grotto`, `Warren` and `Elite` match
no `.gd`/`.tscn` basename at all; the dungeons are data-driven. Nobody should read their absence
from the first table as "these are current".

### The number is a FLOOR

**At least 9 of 20 shots depict changed scenes.** It cannot be a total: the 9 unmapped are
unexamined, and the 2 "unchanged" are unchanged only in the one dimension measured. Stated this
way deliberately — an exhaustive claim here would drift on the next fold, and a floor only ever
gets more true.

⚠️ **Two instruments were thrown away getting here, both reported rather than hidden.** The first
matched any file containing the shot's first word: `battle` "found" 165 sources and
`title_screen` resolved to a *test* file — over-broad, and its output looked like a result. The
second (used above) is exact-basename, which is too narrow: it leaves 9 unmapped. Neither is
wrong about the 9 it names; the first would have inflated the list and the second under-reports.
