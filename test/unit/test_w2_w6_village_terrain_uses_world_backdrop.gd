extends GutTest

## tick 88 regression: W2-W6 village map_ids must resolve to their
## WORLD's terrain string, not generic "village". Pre-fix, a battle
## triggered inside Maple Heights / Brasston / Rivet Row / Node
## Prime / Vertex got the medieval village backdrop because the
## _get_terrain_for_map match arm returned "village" for all of them
## — breaking the W2-W6 world identity for any battle triggered
## inside the village (e.g. story-cutscene battles, debug spawns).

const GAME_LOOP := "res://src/GameLoop.gd"


## Per-village expected terrain string. Each must match a
## BattleBackground.set_terrain_from_string match arm and the
## corresponding world's _on_battle_triggered terrain emit.
const W2_W6_VILLAGE_TERRAIN: Array[Array] = [
	["maple_heights_village",  "suburban"],
	["brasston_village",       "steampunk"],
	["rivet_row_village",      "industrial"],
	["node_prime_village",     "digital"],
	["vertex_village",         "void"],
]


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _terrain_for_map_body() -> String:
	var src := _read(GAME_LOOP)
	var idx: int = src.find("func _get_terrain_for_map")
	assert_gt(idx, -1, "_get_terrain_for_map must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_each_w2_w6_village_maps_to_world_terrain() -> void:
	var body := _terrain_for_map_body()
	for entry in W2_W6_VILLAGE_TERRAIN:
		var map_id: String = entry[0]
		var expected_terrain: String = entry[1]
		# Pin both the match arm key AND the return value.
		# Anchored pattern: "<map_id>":\n\t\t\treturn "<terrain>"
		var arm_pattern: String = "\"" + map_id + "\":\n\t\t\treturn \"" + expected_terrain + "\""
		assert_true(body.contains(arm_pattern),
			"_get_terrain_for_map must have arm '%s' → '%s' — otherwise a battle in this village shows generic medieval village backdrop instead of the world's art" % [map_id, expected_terrain])


func test_no_w2_w6_village_returns_generic_village_terrain() -> void:
	# Negative pin: catch the regression class of "someone reverted
	# to 'village'" by checking each W2-W6 village specifically.
	var body := _terrain_for_map_body()
	for entry in W2_W6_VILLAGE_TERRAIN:
		var map_id: String = entry[0]
		var bad_pattern: String = "\"" + map_id + "\":\n\t\t\treturn \"village\""
		assert_false(body.contains(bad_pattern),
			"%s must NOT return 'village' terrain — that's the medieval backdrop, wrong for this world" % map_id)


func test_w1_harmonia_still_uses_village_terrain() -> void:
	# Don't regress: W1 Harmonia village must still map to "village"
	# terrain. It IS the medieval village.
	var body := _terrain_for_map_body()
	assert_true(body.contains("\"harmonia_village\", \"tavern_interior\", \"harmonia_chapel\", \"harmonia_library\", \"harmonia_cartographer\":"),
		"W1 Harmonia + its interiors must keep the village-arm grouping")
	# Pin that the W1 arm returns "village".
	var idx: int = body.find("\"harmonia_village\", \"tavern_interior\"")
	assert_gt(idx, -1, "W1 Harmonia arm must exist")
	var next_line_end: int = body.find("\n", body.find("\n", idx) + 1)
	var arm_chunk: String = body.substr(idx, next_line_end - idx) if next_line_end > -1 else body.substr(idx)
	assert_true(arm_chunk.contains("return \"village\""),
		"W1 Harmonia arm must still return 'village' — the only world that should")


func test_every_expected_terrain_string_resolves_in_battle_background() -> void:
	# Cross-check with BattleBackground.set_terrain_from_string so a
	# typo here doesn't fall through to PLAINS default silently.
	var src := _read("res://src/battle/BattleBackground.gd")
	var idx: int = src.find("func set_terrain_from_string")
	assert_gt(idx, -1, "set_terrain_from_string must exist in BattleBackground")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	for entry in W2_W6_VILLAGE_TERRAIN:
		var expected_terrain: String = entry[1]
		var quoted: String = "\"" + expected_terrain + "\""
		assert_true(body.contains(quoted),
			"BattleBackground.set_terrain_from_string must have a case for '%s' — otherwise the village terrain string falls through to PLAINS" % expected_terrain)
