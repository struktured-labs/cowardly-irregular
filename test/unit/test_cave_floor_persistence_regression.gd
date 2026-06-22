extends GutTest

## Cave floor was lost on save/load — a player who quick-saved on
## Whispering Cave floor 5, exited the game, and continued would be
## dumped back on floor 1 and have to re-descend. GameLoop's
## _current_cave_floor handles in-session battle re-entry but doesn't
## survive a full quit.
##
## Fix: WhisperingCave._change_floor writes
## GameState.game_constants["whispering_cave_floor"] every transition;
## _ready restores from it on instantiation. Walking back to overworld
## clears the key so re-entering the cave fresh starts at floor 1.

const CAVE_PATH := "res://src/maps/dungeons/WhisperingCave.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _body_of(func_name: String) -> String:
	var src := _read(CAVE_PATH)
	var idx := src.find("func " + func_name)
	assert_gt(idx, -1, func_name + " must exist")
	var next_fn := src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_transition_to_floor_writes_to_game_constants() -> void:
	# Without the write, _ready has nothing to restore from.
	var body := _body_of("_transition_to_floor")
	assert_true(body.contains("game_constants[\"whispering_cave_floor\"] = current_floor"),
		"_transition_to_floor must persist current_floor so save/load can restore it")


func test_ready_restores_floor_from_game_constants() -> void:
	# Without the read, the write goes nowhere on load.
	var body := _body_of("_ready")
	assert_true(body.contains("game_constants.has(\"whispering_cave_floor\")"),
		"_ready must check for a saved floor before generating the map")
	assert_true(body.contains("current_floor = saved_floor"),
		"_ready must assign the saved floor")
	# Must be range-guarded so a malformed save doesn't crash on
	# _generate_map_for_floor with a junk value.
	assert_true(body.contains("saved_floor >= 1") and body.contains("saved_floor <= 6"),
		"saved floor must be clamped to [1, 6] so corrupt save data can't crash the cave")


func test_transition_to_overworld_clears_floor() -> void:
	# Without the clear, walking out then back in would pop the player
	# to whichever floor they previously left at.
	var body := _body_of("_on_transition_triggered")
	assert_true(body.contains("game_constants.erase(\"whispering_cave_floor\")"),
		"walking out of the cave must clear the saved floor so re-entry starts at floor 1")
	# The clear must be conditional — staying in the cave (e.g. a same-map
	# transition for some future feature) must NOT erase the floor.
	assert_true(body.contains("target_map != \"whispering_cave\""),
		"clear must skip same-map transitions (only erase on overworld exit)")
