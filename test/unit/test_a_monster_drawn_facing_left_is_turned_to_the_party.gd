extends GutTest

## Eleven battle monsters stood with their BACKS to the party for the whole fight, the fire and ice dragons among
## them. The party stands at screen right, so a monster must face right. BattleScene flips a sheet only when the
## manifest declares "flip_h" or the frame is 128px or smaller; a 256px sheet is taken to be drawn facing right, and
## these eleven legacy sheets were drawn facing LEFT. Nothing failed: a monster facing the wrong way is a legal sprite.
## Found 2026-10-12 by rendering every monster's idle frame as the game shows it and looking, then zooming each.
## No pixel measure separates them (head-mass lean was tried on 24 sheets and overlaps completely), so this is a
## reviewed list: each id was judged by eye and now declares flip_h. RE-REVIEW an entry when its art is redrawn.

const Loader := preload("res://src/battle/sprites/HybridSpriteLoader.gd")
const DRAWN_FACING_LEFT := [
	"assembly_line_automaton", "blood_wolf_alpha", "conveyor_gremlin", "cranky_lady", "cursed_armor", "fire_dragon",
	"ice_dragon", "ironback_beetle", "rust_elemental", "troll", "viper",
]
## Drawn facing left too, but a WORLD VARIANT: battle asks the base id, so a flip declared on its row is read by
## nothing (test_a_world_variant_cannot_declare_a_facing_the_engine_never_reads). Still backwards until that lookup learns.
const STILL_BACKWARDS := ["masterite_curator_futuristic"]
## Zoomed in the same pass and found facing the party already: declaring a flip on these would turn them away.
const DRAWN_FACING_RIGHT := ["cave_rat", "shadow_dragon", "lightning_dragon", "steam_rat", "unassuming_dog", "rat_guard"]


func _sheets() -> Dictionary:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	return manifest["monster_sheets"]


func test_a_monster_drawn_facing_left_is_flipped_in_battle() -> void:
	var sheets := _sheets()
	var backwards: Array = []
	for id in DRAWN_FACING_LEFT:
		assert_true(sheets.has(id), "CONTROL: %s is a monster sheet" % id)
		assert_gt(int((sheets[id] as Dictionary).get("frame_height", 0)), 128, "CONTROL: %s is a full-size sheet, so no size rule flips it" % id)
		# The battle's own question, with the full-size convention (no flip) as its fallback
		if not Loader.monster_faces_party(id, false):
			backwards.append(id)
	assert_eq(backwards, [], "monsters drawn facing left that battle does not turn round: %s" % str(backwards))


func test_a_monster_drawn_facing_right_is_left_alone() -> void:
	for id in DRAWN_FACING_RIGHT:
		assert_true(_sheets().has(id), "CONTROL: %s is a monster sheet" % id)
		assert_false(Loader.monster_faces_party(id, false), "%s already faces the party; a flip would turn it away" % id)


func test_the_variant_left_backwards_is_still_named() -> void:
	for id in STILL_BACKWARDS:
		assert_true(_sheets().has(id), "CONTROL: %s is a monster sheet" % id)
		assert_false((_sheets()[id] as Dictionary).has("flip_h"), "%s declares a flip now: if battle reads it, move it to DRAWN_FACING_LEFT" % id)


func test_the_flip_is_declared_on_the_sheet_not_inferred() -> void:
	## The declaration is what survives a resize: it must be a real boolean on the entry.
	var sheets := _sheets()
	for id in DRAWN_FACING_LEFT:
		assert_true((sheets[id] as Dictionary).get("flip_h", null) == true, "%s declares flip_h: true" % id)
