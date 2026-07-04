extends GutTest

## cowir-sfx msg 2165 (2026-07-04): door_open/door_close authored in
## manifest but zero src callers — dungeon entrances and interior
## thresholds animated silently. Wired at the two threshold-crossing
## moments: cave_in plays door_close (stone doors slam behind you as
## you enter the cave); interior_in plays door_open (opening the shop/
## inn/tavern door). Village/overworld transitions stay open-air —
## no door SFX (they aren't doorways).


func test_cave_transition_in_plays_door_close() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var fn: int = src.find("func _area_cave_transition_in")
	assert_gt(fn, -1)
	var end_next: int = src.find("\nfunc ", fn + 1)
	var body: String = src.substr(fn, end_next - fn)
	assert_true(body.contains("SoundManager.play_ui(\"door_close\")"),
		"cave_in must slam a stone door — door_close cues the entrance moment")


func test_interior_transition_in_plays_door_open() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var fn: int = src.find("func _area_interior_transition_in")
	assert_gt(fn, -1)
	var end_next: int = src.find("\nfunc ", fn + 1)
	var body: String = src.substr(fn, end_next - fn)
	assert_true(body.contains("SoundManager.play_ui(\"door_open\")"),
		"interior_in must open the shop/inn/tavern door — door_open cues the threshold")


func test_village_and_overworld_transitions_stay_open_air() -> void:
	# Village entries and open-world transitions are NOT doorways;
	# no door SFX should have leaked into those paths.
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	for fn_name in ["_area_village_transition_in", "_area_overworld_transition_in"]:
		var fn: int = src.find("func " + fn_name)
		assert_gt(fn, -1, "handler %s must exist" % fn_name)
		var end_next: int = src.find("\nfunc ", fn + 1)
		var body: String = src.substr(fn, end_next - fn)
		assert_false(body.contains("door_open") or body.contains("door_close"),
			"%s must NOT play door SFX (open-air transition, no doorway)" % fn_name)


func test_door_keys_resolve_in_manifest() -> void:
	# Wiring is pointless if the assets go missing. This ratchet catches
	# an SFX-side rename before it breaks the runtime feedback.
	var m = JSON.parse_string(FileAccess.get_file_as_string("res://data/sfx_manifest.json"))
	assert_true(m["sfx"].has("door_open"), "door_open must be in manifest")
	assert_true(m["sfx"].has("door_close"), "door_close must be in manifest")
