extends GutTest

## Feature 2026-07-05: TreasureChest opened-state persists via a per-chest story
## flag ("chest_" + chest_id). Two chests with distinct ids must have INDEPENDENT
## opened flags — a shared or default chest_id would make opening one close the
## others (they'd read the same flag). Added a _ready guard that push_warnings
## when chest_id is still the "chest_001" default (a forgotten assignment, which
## nothing in the game legitimately uses).

const CHEST := preload("res://src/exploration/TreasureChest.gd")

var _saved_flags: Dictionary = {}


func before_each() -> void:
	_saved_flags = GameState.story_flags.duplicate(true)


func after_each() -> void:
	GameState.story_flags = _saved_flags


func _chest(id: String):
	var c = CHEST.new()
	autofree(c)
	c.chest_id = id
	return c


func test_opened_state_is_per_chest_id() -> void:
	var a = _chest("test_chest_alpha")
	var b = _chest("test_chest_beta")
	GameState.set_story_flag("chest_test_chest_alpha")  # open A only
	a._check_if_opened()
	b._check_if_opened()
	assert_true(a._is_opened, "chest A's flag marks it opened")
	assert_false(b._is_opened, "chest B (different id) stays closed — opened flags are independent")


func test_default_chest_id_is_guarded_in_source() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/exploration/TreasureChest.gd")
	var idx: int = src.find("func _ready")
	assert_gt(idx, -1, "_ready must exist")
	assert_string_contains(src.substr(idx, 400), "chest_001",
		"_ready must warn on the unassigned default chest_id (opened-flag collision guard)")
