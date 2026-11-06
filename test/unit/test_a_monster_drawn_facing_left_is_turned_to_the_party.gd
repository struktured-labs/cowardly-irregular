extends GutTest

## Eleven battle monsters stood with their BACKS to the party for the whole fight, the fire and ice dragons among
## them. The party stands at screen right, so a monster must face right. BattleScene flips a sheet only when the
## manifest declares "flip_h" or the frame is 128px or smaller; a 256px sheet is taken to be drawn facing right, and
## these eleven legacy sheets were drawn facing LEFT. Nothing failed: a monster facing the wrong way is a legal sprite.
## Found 2026-10-12 by rendering every monster's idle frame as the game shows it and looking, then zooming each.
## No pixel measure separates them (head-mass lean was tried on 24 sheets and overlaps completely), so this is a
## reviewed list: each id was judged by eye and now declares flip_h. RE-REVIEW an entry when its art is redrawn.
## Re-reviewed 2026-11-01 (all 117 sheets, zoomed): meta_knight added. cursed_armor moved to the right-facing list on
## struktured's own A/B in play: its sheet is mixed-facing, and he read the flipped version as turned away.
## 2026-11-05: masterite_curator_futuristic added. It was parked as an unreadable world variant, but it is spawned
## under its own full id (NodePrimeVillage), so battle asks its own row and the flip is read.

const Loader := preload("res://src/battle/sprites/HybridSpriteLoader.gd")
const DRAWN_FACING_LEFT := [
	"assembly_line_automaton", "blood_wolf_alpha", "conveyor_gremlin", "cranky_lady", "fire_dragon",
	"ice_dragon", "ironback_beetle", "masterite_curator_futuristic", "meta_knight", "rust_elemental", "troll", "viper",
]
## Zoomed in the same pass and found facing the party already: declaring a flip on these would turn them away.
const DRAWN_FACING_RIGHT := [
	"cave_rat", "shadow_dragon", "lightning_dragon", "steam_rat", "unassuming_dog", "rat_guard", "cursed_armor",
]


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


func test_a_masterite_flip_is_read_because_it_spawns_by_its_full_id() -> void:
	## The id battle asks facing for is the enemy's monster_type, i.e. the monsters.json key. A masterite's key is its
	## full dressed id, so its own manifest row is the one consulted, with no base-id lookup in between.
	var monsters: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	assert_true(monsters is Dictionary and (monsters as Dictionary).has("masterite_curator_futuristic"),
		"CONTROL: the futuristic curator is a monster under its full id")
	var village := FileAccess.get_file_as_string("res://src/maps/villages/NodePrimeVillage.gd")
	assert_true(village.contains('monster_id = "masterite_curator_futuristic"'),
		"CONTROL: NodePrimeVillage spawns the curator by its full id")
	assert_true(Loader.monster_faces_party("masterite_curator_futuristic", false),
		"the futuristic curator is drawn facing left and must be turned to the party")


func test_the_flip_is_declared_on_the_sheet_not_inferred() -> void:
	## The declaration is what survives a resize: it must be a real boolean on the entry.
	var sheets := _sheets()
	for id in DRAWN_FACING_LEFT:
		assert_true((sheets[id] as Dictionary).get("flip_h", null) == true, "%s declares flip_h: true" % id)
