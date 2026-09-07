extends GutTest
## Castle Harmonia must require the whole W1 boss spine, not just the tutorial boss.

const SPINE := ["rat_king_defeated", "fire_dragon_defeated", "ice_dragon_defeated",
	"lightning_dragon_defeated", "shadow_dragon_defeated"]

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
	assert_not_null(_scene, "OverworldScene script must instantiate or every assert is vacuous")
	assert_not_null(_gs, "GameState autoload missing")
	assert_true(_scene.has_method("_castle_is_earned"), "the gate predicate must exist")
	assert_true(_gs.is_story_flag_set("rat_king_defeated") == false, "dungeon_flags must start cleared")


func test_the_tutorial_boss_alone_does_not_open_the_castle() -> void:
	_flag("rat_king_defeated")
	assert_false(_scene._castle_is_earned(_gs), "Rat King alone must not reveal Castle Harmonia")


func test_three_of_four_dragons_is_still_not_enough() -> void:
	_flag("rat_king_defeated")
	_flag("fire_dragon_defeated")
	_flag("ice_dragon_defeated")
	_flag("lightning_dragon_defeated")
	assert_false(_scene._castle_is_earned(_gs), "one dragon left must still hold the castle shut")


func test_the_full_spine_opens_the_castle() -> void:
	for f in SPINE:
		_flag(f)
	assert_true(_scene._castle_is_earned(_gs), "all five bosses must open Castle Harmonia")


func test_a_player_who_already_beat_mordaine_keeps_access() -> void:
	_gs.story_flags["world1_mordaine_defeated"] = true
	assert_true(_scene._castle_is_earned(_gs), "an existing save past Mordaine must never be stranded")


func test_remaining_reports_what_is_left_in_order() -> void:
	_flag("rat_king_defeated")
	_flag("fire_dragon_defeated")
	var left: Array = _scene.w1_spine_remaining(_gs)
	assert_eq(left.size(), 3, "three bosses should remain")
	assert_eq(left[0], "ice_dragon_defeated", "order must follow the spine")
