extends GutTest

## Regression: all four W1 dragon caves used to dispatch to "dragon_ice"
## music, so Pyrroth's commissioned ember theme never played and lightning/
## shadow caves silently fell back to the ice track. Now each cave maps to
## its element. Source-level check because the dispatch is inside a match
## inside a call_deferred — exercising it for real would need the audio bus.

const SOUND_MANAGER_PATH: String = "res://src/audio/SoundManager.gd"

const EXPECTED_ARM: Dictionary = {
	"fire_dragon_cave": "dragon_fire",
	"ice_dragon_cave": "dragon_ice",
	"lightning_dragon_cave": "dragon_lightning",
	"shadow_dragon_cave": "dragon_shadow",
}


func _load_source() -> String:
	var f: FileAccess = FileAccess.open(SOUND_MANAGER_PATH, FileAccess.READ)
	assert_not_null(f, "could not open SoundManager source")
	if f == null:
		return ""
	var s: String = f.get_as_text()
	f.close()
	return s


# Return only the body of _start_area_music_deferred — the function that does
# the actual music-play dispatch. _get_current_world_suffix also references the
# cave ids (and rightly returns "medieval" for all four W1 dragons), so a
# whole-file scan produces false positives.
func _isolate_dispatch_body(src: String) -> String:
	var marker: String = "func _start_area_music_deferred"
	var start: int = src.find(marker)
	if start < 0:
		return ""
	var next_func: int = src.find("\nfunc ", start + marker.length())
	if next_func < 0:
		return src.substr(start)
	return src.substr(start, next_func - start)


func test_each_dragon_cave_dispatches_to_its_own_element_track() -> void:
	var src: String = _isolate_dispatch_body(_load_source())
	assert_ne(src, "", "could not isolate _start_area_music_deferred body")
	for cave in EXPECTED_ARM.keys():
		var expected_track: String = EXPECTED_ARM[cave]
		# Find the match arm for this cave and assert the next line calls
		# _start_dungeon_music with the expected world tag.
		var cave_marker: String = "\"%s\":" % cave
		var idx: int = src.find(cave_marker)
		assert_gt(idx, -1, "SoundManager missing match arm for %s" % cave)
		if idx < 0:
			continue
		var slice: String = src.substr(idx, 200)
		var expected_call: String = "_start_dungeon_music(\"%s\")" % expected_track
		assert_true(slice.contains(expected_call),
			"%s should dispatch to %s, source slice was: %s" % [cave, expected_call, slice])


func test_no_dragon_cave_arm_collapses_back_to_dragon_ice_for_all_four() -> void:
	# The classic bug: a multi-key arm  "ice_dragon_cave", "shadow_dragon_cave",
	# "lightning_dragon_cave", "fire_dragon_cave":  -> _start_dungeon_music("dragon_ice")
	# Catch that exact shape if it ever reappears in the dispatch func.
	var src: String = _isolate_dispatch_body(_load_source())
	var combined_keys: int = 0
	for cave in EXPECTED_ARM.keys():
		if src.contains("\"%s\"," % cave):
			combined_keys += 1
	assert_lt(combined_keys, 4,
		"all four dragon caves are bundled into a single match arm — regression of the dragon_ice-for-all bug")
