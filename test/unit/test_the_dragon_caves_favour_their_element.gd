extends GutTest

## GameLoop maps the four W1 dragon caves to lava_cave / ice_cave / storm_cave / dark_cave, and
## _get_terrain_modifiers had no arm for any of them, so the dragons' own lairs biased nothing while the
## tutorial's whispering_cave did. struktured 2026-10-06: wire it. Each favours its dragon's element
## (boost only, so the party's counter element is not also blunted).

const CAVES := {"fire_dragon_cave": "fire", "ice_dragon_cave": "ice", "lightning_dragon_cave": "lightning", "shadow_dragon_cave": "dark"}


func test_each_dragon_cave_boosts_its_element() -> void:
	var gl = load("res://src/GameLoop.gd").new()
	var bad: Array[String] = []
	for map_id in CAVES:
		var terrain: String = gl._get_terrain_for_map(map_id)
		var el: String = CAVES[map_id]
		var mod: float = BattleManager.get_terrain_damage_modifier(el, terrain)
		if mod <= 1.0:
			bad.append("%s (terrain %s) gives %s x%.2f" % [map_id, terrain, el, mod])
	gl.free()
	assert_eq(bad, [] as Array[String], "every dragon's lair must favour its dragon's element: %s" % str(bad))


func test_the_boost_matches_the_tutorial_caves() -> void:
	var tutorial: float = BattleManager.get_terrain_damage_modifier("ice", "cave")
	assert_gt(tutorial, 1.0, "CONTROL: the whispering cave boosts ice")
	assert_almost_eq(BattleManager.get_terrain_damage_modifier("fire", "lava_cave"), tutorial, 0.0001,
		"same strength as the existing cave boost, not a new number")


func test_no_dragon_cave_blunts_the_counter_element() -> void:
	for pair in [["lava_cave", "ice"], ["ice_cave", "fire"], ["storm_cave", "earth"], ["dark_cave", "holy"]]:
		assert_eq(BattleManager.get_terrain_damage_modifier(pair[1], pair[0]), 1.0,
			"%s must not reduce %s, the party's natural counter" % pair)
