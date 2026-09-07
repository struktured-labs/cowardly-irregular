extends GutTest

## tick 311: GameLoop._set_current_map_id also re-derives _current_terrain
## so save-load + autogrind hand-off see fresh terrain instead of the
## stale default "plains".
##
## Pre-fix _current_terrain was set on battle-trigger and area-transition
## but NOT in the load path. Loading a save in fire_dragon_cave and
## immediately starting autogrind passed "plains" (the field's default
## initial value) into _autogrind_controller.start_grind, which rendered
## the wrong battle background until the first battle-trigger event
## re-derived. Same drift class as the tick 310 world sync.

const GAME_LOOP_PATH := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: setter derives terrain ──────────────────────────────

func test_setter_derives_terrain() -> void:
	var src := _read(GAME_LOOP_PATH)
	var fn_idx: int = src.find("func _set_current_map_id")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_current_terrain = _get_terrain_for_map(id)"),
		"_set_current_map_id must derive _current_terrain from the new map_id (closes load-then-autogrind stale-terrain gap)")


# ── Behavioral: setter mutates _current_terrain ─────────────────────

func test_setter_changes_current_terrain() -> void:
	var gl_script: GDScript = load(GAME_LOOP_PATH)
	var gl: Object = gl_script.new()
	add_child_autofree(gl)

	# Fresh instance starts with default "plains".
	assert_eq(gl._current_terrain, "plains",
		"GameLoop._current_terrain default must be plains (pre-condition for the bug)")

	# A dungeon set should change it to the dungeon's terrain.
	gl._set_current_map_id("fire_dragon_cave")
	assert_eq(gl._current_terrain, "lava_cave",
		"_set_current_map_id('fire_dragon_cave') must derive 'lava_cave' (was 'plains' default until first battle)")

	# Going back to overworld resets to plains.
	gl._set_current_map_id("overworld")
	assert_eq(gl._current_terrain, "plains",
		"_set_current_map_id('overworld') must derive 'plains'")


# ── Behavioral: each world's overworld picks the right terrain ──────

func test_per_world_overworld_terrain() -> void:
	var gl_script: GDScript = load(GAME_LOOP_PATH)
	var gl: Object = gl_script.new()
	add_child_autofree(gl)

	var pairs := [
		["overworld", "plains"],
		["suburban_overworld", "suburban"],
		["steampunk_overworld", "steampunk"],
		["industrial_overworld", "industrial"],
		["futuristic_overworld", "digital"],
		["abstract_overworld", "void"],
	]
	for pair in pairs:
		var map_id: String = pair[0]
		var expected_terrain: String = pair[1]
		gl._set_current_map_id(map_id)
		assert_eq(gl._current_terrain, expected_terrain,
			"map_id '%s' must derive terrain '%s'" % [map_id, expected_terrain])


# ── Dragon caves get their elemental terrain ────────────────────────

func test_dragon_caves_keep_elemental_terrain() -> void:
	var gl_script: GDScript = load(GAME_LOOP_PATH)
	var gl: Object = gl_script.new()
	add_child_autofree(gl)

	var pairs := [
		["fire_dragon_cave",      "lava_cave"],
		["ice_dragon_cave",       "ice_cave"],
		["lightning_dragon_cave", "storm_cave"],
		["shadow_dragon_cave",    "dark_cave"],
	]
	for pair in pairs:
		var map_id: String = pair[0]
		var expected: String = pair[1]
		gl._set_current_map_id(map_id)
		assert_eq(gl._current_terrain, expected,
			"dragon cave '%s' must derive terrain '%s'" % [map_id, expected])
