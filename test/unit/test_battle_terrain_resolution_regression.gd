extends GutTest

## Battle terrain sets elemental modifiers AND the background. Dungeon
## floors carry a "_f<n>" suffix and the dragon caves / castle aren't in
## _get_terrain_for_map's exact match — they ALL resolve through the
## default-branch substring fallback ("cave" in map_id → "cave", etc.).
## That fallback is load-bearing: a regression that breaks it silently
## drops every cave/dragon/castle battle to "plains" — wrong elemental
## math and a grass background under Chancellor Mordaine (the exact bug
## the tick-360 castle keyword guard fixed). This pins the resolution.

const GL := preload("res://src/GameLoop.gd")


func _terrain(map_id: String) -> String:
	var gl = GL.new()
	autofree(gl)
	return gl._get_terrain_for_map(map_id)


func test_dragon_caves_keep_their_elemental_terrain() -> void:
	# These directly change elemental combat math — the whole point of a
	# fire dragon's lair being lava, not generic rock.
	assert_eq(_terrain("fire_dragon_cave"), "lava_cave")
	assert_eq(_terrain("ice_dragon_cave"), "ice_cave")
	assert_eq(_terrain("lightning_dragon_cave"), "storm_cave")
	assert_eq(_terrain("shadow_dragon_cave"), "dark_cave")


func test_generic_cave_and_floor_suffix_fall_back_to_cave() -> void:
	assert_eq(_terrain("whispering_cave"), "cave")
	# The substring fallback catches any cave-keyword id (incl. floor
	# suffixes) as a SAFE degrade — never plains.
	assert_eq(_terrain("whispering_cave_f3"), "cave",
		"a floor-suffixed cave id must resolve to cave, not plains")


func test_castle_resolves_to_village_not_plains() -> void:
	assert_eq(_terrain("castle_harmonia"), "village",
		"Mordaine's castle must use the medieval/village background, not plains (tick-360 fix)")


func test_overworld_is_plains() -> void:
	assert_eq(_terrain("overworld"), "plains")


func test_unmapped_area_falls_back_to_plains() -> void:
	assert_eq(_terrain("totally_unknown_area_xyz"), "plains",
		"a genuinely unmapped id defaults to plains — the safe fallback")
