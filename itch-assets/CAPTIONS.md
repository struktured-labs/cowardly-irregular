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

### `field_elite_steampunk.png`
A field ELITE — a brass golem loose in the Clockwork Dominion, aura up, and the game telling
you in purple exactly what you think it is: *"It is watching you."* Walking into one opens a
choice, Fight or Leave it, so the encounter is always yours to decline.

⚠️ **Honest note:** at overworld zoom the elite reads as a small sprite and the purple tell
has weak contrast on tan ground. It is a correct capture of the feature, not a flattering
one. See "Not in this set" for the related sprite bug.

### Baseline set (shot 2026-08-30, still current)
`harmonia_village` · `ironhaven_village` · `frosthold_village` · `sandrift_village` ·
`inn_interior` · `tavern_interior` · `shop_interior` · `whispering_cave` — villages and
interiors across the first world. `title_screen.png` is the source for the provisional cover.

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
- **Elevator mid-ride** — still owed. Needs `VillageElevator.interact()` driven through an
  actual ride; scene instantiation cannot produce it.

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

### `eldertree_village` — DROPPED AGAIN
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
