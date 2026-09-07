extends GutTest

## Regression (web-smoke probe 2026-07-11): on title-screen Continue, the
## Mode 7 overworld was built TWICE — once by the legacy MapSystem.load_map
## call inside SaveSystem._apply_save_data, once by GameLoop's canonical
## _start_exploration. Two stacked overlays; the zombie scene's frozen
## shader uniforms painted a fog wall with a floor sliver over the live
## game, AND the zombie was retained forever in MapSystem.loaded_maps.
## State restore must hand off (current_map_id + pending position) and
## NEVER build scenes.


func test_apply_save_data_does_not_build_scenes() -> void:
	var src := FileAccess.get_file_as_string("res://src/save/SaveSystem.gd")
	var fn_start := src.find("func _apply_save_data")
	assert_gt(fn_start, -1)
	var fn_end := src.find("\nfunc ", fn_start + 1)
	var body := src.substr(fn_start, fn_end - fn_start)
	var calls := 0
	for line in body.split("\n"):
		var code := line.strip_edges()
		if code.begins_with("MapSystem.load_map(") or code.begins_with("load_map("):
			calls += 1
	assert_eq(calls, 0,
		"_apply_save_data must NOT call MapSystem.load_map — GameLoop owns scene builds; the legacy call double-built the overworld on Continue")
	assert_true("current_map_id = saved_map_id" in body,
		"the current_map_id hand-off (tick 308) must survive the legacy-call removal")


func test_map_id_handoff_without_scene_build() -> void:
	var prev_id = MapSystem.current_map_id
	var prev_map = MapSystem.current_map
	SaveSystem._apply_save_data({
		"map": {"current_map_id": "overworld"},
		"party": [], "inventory": {}, "story_flags": {},
	})
	assert_eq(str(MapSystem.current_map_id), "overworld",
		"map id must be handed off for GameLoop's rebuild")
	assert_eq(MapSystem.current_map, prev_map,
		"no scene may be instantiated by state restore (was the double-build)")
	MapSystem.current_map_id = prev_id
