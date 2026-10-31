# Cutscene backdrop shot list + fit audit (cowir-cutscenes, 2026-10-31, read on eb41c9954)

## 0. READ FIRST: a redrawn PNG under the same name changes NOTHING on screen
CutsceneDirector._try_load_backdrop_image tries assets/cutscene_videos/<key>.ogv BEFORE
assets/cutscene_backdrops/<key>.png. All 20 keys have an .ogv (6da865867, 2026-04-05), and the
export presets exclude *.mp4 only, so the .ogv ships on every channel.
=> For every redraw: regenerate the .ogv loop too, or delete it (then the PNG shows).
=> For a NEW key: no .ogv exists, so the PNG shows as soon as the JSON names it.
Also: the 7 `presentation:"staged"` scenes never show a backdrop (they play on the live map).
Their `background` field is dead, so 4 of the 11 throne_room and 3 of the 17 prologue_village
uses need no art.

## 1. Harmonia: 4 new keys, 640x360, W1 medieval
| key | shows | scenes |
|---|---|---|
| harmonia_square | Town square mid-morning: stone well in the centre, Sleepy Slime Inn frontage with a notice nailed to the door, timber houses, castle on the ridge behind | world1_prologue, world1_harmonia_npcs, world1_spotlight_cleric_ch1 (old woman on the well), world1_orrery (Phil at the well), world1_guidance_capital/_cave/_forest (Theron stands outdoors in the square) |
| harmonia_square_portal | Same composition at dusk, with a humming brass device in the square and a portal showing parking lots and picket fences | world1_epilogue (now throne_room: WRONG, the text says "In Harmonia Village"), world1_transition |
| harmonia_inn | Sleepy Slime Inn interior, "the good table by the window" | world1_spotlight_bard_ch7 |
| harmonia_shop | Shop interior: an unnamed sword shop rack plus a shelf of wrapped, labelled spells (one image covers both) | world1_bram_shield, event_chat_first_magic_shop |
throne_room stays for the castle scenes (chapter9, curator_*, mordaine_defeat, throne_room_approach).

## 2. Fit audit: borrowed or wrong backdrops in the other keys (text-read, first lines)
HIGH: wrong world or wrong place, visible to the player
- prologue_forest -> 7 LATER-WORLD scenes on a W1 forest: world2_pc_association/_maintenance/_zoning
  (-> suburban_neighborhood), world3_pc_calibration (-> brasston_square), world4_pc_shift_change
  (-> rivet_row_factory), world5_pc_login (-> node_prime), world6_pc_negative_space (-> vertex_village)
- prologue_forest -> world1_tempo_intro: "dropped from a rooftop into the street… You made it to the
  city" (-> a W1 city street; none exists, see NEW below)
- prologue_village -> world1_chapter7 / world1_chapter8: Scriptura bookshop + Guild back room, not a
  village (-> NEW scriptura_guild, or one scriptura_interior)
- steampunk_workshop -> world3_brasston_npcs, world3_chat_teatime_brasston, world3_prologue (clock
  tower chimes on arrival): all town scenes (-> brasston_square, which exists)
- steampunk_workshop -> world3_grand_schedule_intro/_defeat: "the gear-train room" (-> mechanism_interior)
- steampunk_airship -> world3_chapter2: "third street past the market" (-> brasston_square). Its
  only use, so the airship art is then unused
- suburban_park -> world2_chapter2 (cul-de-sac), world2_tempo_intro (end of the street),
  world2_warden_routine (crosswalk): street scenes (-> maple_heights_street). No scene is in a park
- suburban_neighborhood -> world2_maple_heights_npcs (-> maple_heights_street, which exists and has 1 use)
- suburban_school -> world2_oak_street_npcs: "Oak Street smelled of hot concrete" (-> maple_heights_street)
- industrial_factory -> world4_prologue "Welcome to Rivet Row", world4_rivet_row_npcs (housing
  blocks and streets) (-> rivet_row_factory, or NEW rivet_row_street)
- industrial_factory -> world3_arbiter_intro: "the foreman's office" (-> director_office)
MEDIUM: generic but not wrong
- cave_entrance carries all 4 dragon intros (pyrroth/glacius/voltharion/umbraxis): fire, ice,
  lightning and shadow caves share one cave mouth. Candidates: 4 NEW elemental cave keys
- vertex_village -> world6_null_chamber_boss ("the chamber had no inventory"): a room, not a village
- event_chat_level_10 on prologue_village: a field scene ("between the tenth slime and the eleventh")
  (-> prologue_forest)
- no background at all (capture/gradient fallback): world6_orrery (-> vertex_village),
  world3_transition (fallback is arguably right for a transform), npc_showcase_personas (dev)
DATA (fixed): event_chat_dragon_cave was tagged world 3 in both its JSON and PartyChatSystem.REGISTRY.
  It fires from W1's dragon caves (DragonCave.gd), and the registry world only sorts the Party Chat list.
  Both are now 1.

## 2b. DONE on lane/a-scene-shows-where-it-happens (JSON only, existing keys)
21 re-points: the 7 pc_* scenes -> their own world's key; Brasston town scenes + world3_chapter2 ->
brasston_square; grand_schedule intro/defeat -> mechanism_interior; the W2 street scenes ->
maple_heights_street (Oak Street -> suburban_neighborhood); Rivet Row prologue/npcs -> rivet_row_factory;
event_chat_level_10 -> prologue_forest. Guard: test_a_backdrop_belongs_to_one_world (cross-world half only).
Left for art: world1_tempo_intro, Scriptura chapter7/8, the 4 dragon intros, world6_null_chamber_boss,
world3_arbiter_intro, world6_orrery (no background key at all).
steampunk_airship now has 0 scenes. Its art is still on disk, unused.

## 2c. Four PNG stills are bare gradients
maple_heights_street, brasston_square, rivet_row_factory and director_office: each PNG is a sky gradient
over a ground band. Their .ogv loops carry real scenery, and the video wins, so players see the scenery.
The still is only what a missing or undecodable video falls back to. Worth redrawing in the same pass.

## 3. Ask of cowir-sprites, in priority order
1. harmonia_square, harmonia_square_portal, harmonia_inn, harmonia_shop  (NEW: no .ogv needed)
2. Redraws of an existing key: also replace or delete its .ogv (section 0)
3. Optional NEW: scriptura_guild, a W1 city street for the Tempo, 4 elemental dragon caves
Every re-point in section 2 to an EXISTING key is JSON-only: cutscenes will do those, no art needed.

## 4. Filed for after the backdrop pilot: a redrawn PNG behind a stale video
Section 0's trap has no guard yet. A guard keyed on mtime cannot work, because git checkout does
not preserve mtime. The robust form is a source hash: the video generator (tools/gen_cutscene_video.py)
records the sha of the PNG it rendered from, and a test asserts the recorded sha equals the PNG on
disk whenever both files exist. That needs a generator change, so it belongs to whoever runs the pilot.
