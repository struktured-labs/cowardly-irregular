extends GutTest

## GameLoop._derive_current_scene_music_key asks the live exploration scene which bed it wants, and every exit that
## re-derives the bed (an autogrind ending, the pause-menu fallback) uses the answer. WhisperingCave extends Node2D,
## not DragonCave, so it inherited no _get_music_area_id and the deriver answered "overworld": ending an autogrind in
## the first cave played the overworld field bed underground. test_dungeon_music_routing_regression exempted it as
## "inherits cave", which only a DragonCave subclass does. The cave now names its own key and _ready plays it.

const GameLoopScript := preload("res://src/GameLoop.gd")
const DUNGEON_DIR := "res://src/maps/dungeons/"
const CAVE_PATH := DUNGEON_DIR + "WhisperingCave.gd"


func _derive_for(scene: Node) -> String:
	var gl = autofree(GameLoopScript.new())
	gl._exploration_scene = scene
	return str(gl._derive_current_scene_music_key())


func _dungeon_maps() -> Array:
	## Every placed dungeon map, derived from the directory: a Node2D that is not a trigger volume (BossTrigger is an Area2D).
	var out: Array = []
	for f in DirAccess.get_files_at(DUNGEON_DIR):
		if not f.ends_with(".gd"):
			continue
		var inst: Object = load(DUNGEON_DIR + f).new()
		var is_map: bool = (inst is Node2D) and not (inst is Area2D)
		inst.free()
		if is_map:
			out.append(f)
	return out


func test_the_first_cave_answers_the_deriver_with_its_bed() -> void:
	var gl = autofree(GameLoopScript.new())
	assert_true(gl.has_method("_derive_current_scene_music_key"), "CONTROL: a bare GameLoop exposes the deriver")
	var cave: Node = autofree(load(CAVE_PATH).new())
	assert_eq(_derive_for(cave), "cave",
		"the first cave must tell GameLoop its own bed; \"overworld\" means an autogrind ending here plays the field theme underground")


func test_every_dungeon_map_can_say_which_bed() -> void:
	var maps: Array = _dungeon_maps()
	assert_gt(maps.size(), 10, "CONTROL: the walk found the dungeon maps (%d)" % maps.size())
	assert_true(maps.has("WhisperingCave.gd"), "CONTROL: the first cave is in the walked set")
	var offenders: Array = []
	for f in maps:
		var inst: Node = load(DUNGEON_DIR + f).new()
		var key: String = _derive_for(inst)
		inst.free()
		if key == "overworld" or key == "":
			offenders.append("%s is a dungeon map but the deriver gets \"%s\" for it, so re-deriving its bed plays the field theme" % [f, key])
	assert_eq(offenders, [], "\n".join(offenders))


func test_the_first_cave_plays_the_key_it_names() -> void:
	var src: String = FileAccess.get_file_as_string(CAVE_PATH)
	assert_gt(src.length(), 0, "CONTROL: the cave source reads")
	assert_true(src.contains("play_area_music(_get_music_area_id())"),
		"_ready must play the key it gives the deriver, so entering and re-deriving cannot name two beds")
	assert_false(src.contains("play_area_music(\"cave\")"), "and must not keep a second, literal copy of it")
