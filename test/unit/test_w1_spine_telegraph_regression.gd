extends GutTest
## The post-Rat-King NPC line promised an open castle; the spine gate made that false.

var _scene = null
var _gs: Node = null
var _saved: Dictionary = {}


func before_each() -> void:
	_scene = load("res://src/exploration/OverworldScene.gd").new()
	_gs = get_node_or_null("/root/GameState")
	if _gs != null:
		_saved = (_gs.game_constants.get("dungeon_flags", {}) as Dictionary).duplicate(true)
		_gs.game_constants["dungeon_flags"] = {}
		_gs.story_flags.erase("world1_mordaine_defeated")


func after_each() -> void:
	if _gs != null:
		_gs.game_constants["dungeon_flags"] = _saved
	if _scene != null:
		_scene.free()


func _flag(flag: String) -> void:
	_gs.game_constants["dungeon_flags"][flag] = true


func test_the_probe_is_real() -> void:
	assert_not_null(_scene, "OverworldScene must instantiate or every assert here is vacuous")
	assert_not_null(_gs, "GameState autoload missing")
	assert_true(_scene.has_method("_spine_telegraph_text"), "telegraph helper must exist")
	assert_false(_gs.is_story_flag_set("rat_king_defeated"), "dungeon_flags must start cleared")


## Derived, not transcribed: a sixth spine boss with no seal name would leak a raw flag id.
func test_every_non_tutorial_spine_flag_has_a_seal_name() -> void:
	var names: Dictionary = _scene.SPINE_SEAL_NAMES
	var uncovered: Array = []
	for flag in _scene.W1_SPINE_FLAGS:
		if flag != "rat_king_defeated" and not names.has(flag):
			uncovered.append(flag)
	assert_eq(uncovered, [], "spine flags with no player-facing seal name: " + str(uncovered))
	assert_gt(names.size(), 0, "seal-name table is empty -- the telegraph would name nothing")


func test_rat_king_alone_names_all_four_remaining_seals() -> void:
	_flag("rat_king_defeated")
	var text: String = _scene._spine_telegraph_text(_gs)
	for flag in _scene.SPINE_SEAL_NAMES:
		assert_true(text.contains(str(_scene.SPINE_SEAL_NAMES[flag])),
			"seal still standing but not named to the player: " + str(_scene.SPINE_SEAL_NAMES[flag]))
	assert_false(text.contains("stands open"),
		"the castle is NOT open with four seals left -- this is the line the gate falsified")


func test_a_defeated_dragon_drops_out_of_the_telegraph() -> void:
	_flag("rat_king_defeated")
	_flag("fire_dragon_defeated")
	var text: String = _scene._spine_telegraph_text(_gs)
	assert_false(text.contains("the Infernal Grotto"),
		"a cleared seal must stop being listed; got: " + text)
	assert_true(text.contains("the Glacial Sanctum"), "uncleared seals must still be named")


func test_the_full_spine_reports_the_castle_open() -> void:
	for flag in _scene.W1_SPINE_FLAGS:
		_flag(flag)
	var text: String = _scene._spine_telegraph_text(_gs)
	assert_true(text.contains("stands open"), "with every seal broken the line must say so; got: " + text)
	for flag in _scene.SPINE_SEAL_NAMES:
		assert_false(text.contains(str(_scene.SPINE_SEAL_NAMES[flag])),
			"a cleared seal is still being listed: " + str(_scene.SPINE_SEAL_NAMES[flag]))


func test_only_the_rat_king_entry_is_rewritten() -> void:
	_flag("rat_king_defeated")
	var hints: Array = [
		{"flag": "", "text": "base"},
		{"flag": "rat_king_defeated", "text": "ORIGINAL CASTLE LINE"},
		{"flag": "world1_mordaine_defeated", "text": "portal"},
	]
	var out: Array = _scene._with_spine_telegraph(hints, _gs)
	assert_eq(out.size(), hints.size(), "the rewrite must not add or drop hint entries")
	assert_eq(str(out[0]["text"]), "base", "non-matching entries must pass through untouched")
	assert_eq(str(out[2]["text"]), "portal", "the later entry must keep its slot and text")
	assert_ne(str(out[1]["text"]), "ORIGINAL CASTLE LINE", "the rat-king line must be rewritten")
	assert_eq(str(hints[1]["text"]), "ORIGINAL CASTLE LINE", "the source array must not be mutated")


## A null GameState must never produce the PERMISSIVE line -- failure value != success value.
func test_a_missing_game_state_does_not_claim_the_castle_is_open() -> void:
	var text: String = _scene._spine_telegraph_text(null)
	assert_false(text.contains("stands open"),
		"with no GameState the line must not promise an open castle; got: " + text)
	assert_ne(text, "", "the null path must still say something to the player")
