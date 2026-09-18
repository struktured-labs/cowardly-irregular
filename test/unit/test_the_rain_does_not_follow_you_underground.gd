extends GutTest

## Weather plays on the overworld through the shared ambient player. Leave the overworld for a
## DUNGEON and the rain kept playing underground, for the whole cave.
##
##     BaseVillage._exit_tree    stops the ambient   "so it does not leak into the next scene"
##     BaseInterior._exit_tree   stops the ambient   "so it doesn't leak into the next scene"
##     OverworldScene._exit_tree cleaned up mode7 and nothing else
##
## Dungeons are the reachable victim because they never touch the layer at all — zero
## play_ambient/stop_ambient/_get_ambient_key references in src/maps/dungeons/. A village or an
## interior masks it by setting its own bed on entry; a cave has none to set.

const OVERWORLD := preload("res://src/exploration/OverworldScene.gd")
const WEATHER_BED := "weather_rain"


func before_each() -> void:
	SoundManager.stop_ambient()


func after_each() -> void:
	SoundManager.stop_ambient()


func test_leaving_the_overworld_stops_the_outdoor_loop() -> void:
	SoundManager.play_ambient(WEATHER_BED)
	assert_eq(SoundManager._current_ambient_key, WEATHER_BED,
		"CONTROL: the weather bed must be playing before the scene is freed")

	var ow = OVERWORLD.new()
	add_child(ow)
	await get_tree().process_frame
	ow.free()
	await get_tree().process_frame

	assert_eq(SoundManager._current_ambient_key, "",
		"the overworld's ambient survived the scene — a dungeon sets no bed of its own, so '%s' plays underground for the whole cave" % SoundManager._current_ambient_key)
	assert_false(SoundManager._ambient_player.playing,
		"and the player must actually be stopped, not merely renamed")


func test_the_siblings_still_do_the_same_thing() -> void:
	## ⛔ WITHOUT THIS THE ARM ABOVE IS ABOUT ONE FILE. The fix exists because two sibling scenes
	## already had it; if they lose it, the overworld is no longer the odd one out and this guard
	## stops describing a rule.
	for path in ["res://src/maps/villages/BaseVillage.gd", "res://src/maps/interiors/BaseInterior.gd"]:
		var body: String = _body_of(FileAccess.get_file_as_string(path), "func _exit_tree")
		assert_ne(body, "", "CONTROL: %s must declare _exit_tree" % path)
		assert_true(body.contains("stop_ambient()"),
			"%s no longer stops its ambient on exit — the overworld fix was modelled on it" % path)


func test_dungeons_still_set_no_bed_of_their_own() -> void:
	## The other half of why this was reachable. If a dungeon ever plays its own ambient, the leak
	## is masked there and this guard's stated victim is wrong.
	var dir := DirAccess.open("res://src/maps/dungeons")
	assert_not_null(dir, "CONTROL: the dungeon directory must be readable")
	var touchers: Array[String] = []
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		var src: String = FileAccess.get_file_as_string("res://src/maps/dungeons/" + f)
		if src.contains("play_ambient(") or src.contains("_get_ambient_key"):
			touchers.append(f)
	assert_eq(touchers, [] as Array[String],
		"a dungeon now sets its own ambient (%s) — re-read this guard, the leak it describes is masked there now" % [touchers])


func _body_of(src: String, header: String) -> String:
	var i: int = src.find(header)
	if i < 0:
		return ""
	var j: int = src.find("\nfunc ", i + 1)
	return src.substr(i, (j - i) if j > i else -1)


func test_entering_the_overworld_establishes_its_own_bed() -> void:
	## ⛔ THE OTHER HALF OF THE EXIT FIX. _update_encounter_zone fires only on a zone CHANGE, and
	## _current_zone starts at "central" — so a spawn resolving to central never reached the router.
	## That was invisible while the previous scene's bed kept playing; stopping on exit turns it
	## into silence. Entry must establish the bed regardless of which zone the spawn lands in.
	SoundManager.stop_ambient()
	assert_eq(SoundManager._current_ambient_key, "", "CONTROL: the layer starts silent")

	var ow = OVERWORLD.new()
	add_child(ow)
	await get_tree().process_frame

	assert_ne(SoundManager._current_ambient_key, "",
		"entering the overworld left the ambient layer SILENT — _exit_tree now stops it, so nothing re-establishes the zone bed")
	ow.free()
	await get_tree().process_frame


func test_entry_does_not_depend_on_the_spawn_zone_differing() -> void:
	## The precise mechanism, so a future refactor cannot reintroduce it: the establishment must not
	## be a zone CHANGE. Pin that _ready reaches the helper, and that the helper sets the zone from
	## the player's own tile rather than comparing against the initial value.
	var src: String = FileAccess.get_file_as_string("res://src/exploration/OverworldScene.gd")
	var ready_body: String = _body_of(src, "func _ready")
	assert_ne(ready_body, "", "CONTROL: OverworldScene must declare _ready")
	assert_true(ready_body.contains("_establish_zone_ambient()"),
		"_ready must CALL _establish_zone_ambient() — without it entry depends on the spawn zone differing from 'central'")
	var helper: String = _body_of(src, "func _establish_zone_ambient")
	assert_ne(helper, "", "CONTROL: the helper must exist")
	assert_true(helper.contains("_update_zone_ambient("),
		"the helper must reach the zone router, or it establishes nothing")
