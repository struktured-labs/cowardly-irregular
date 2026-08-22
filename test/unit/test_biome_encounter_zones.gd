extends GutTest

## Encounter zones must follow the PAINTED biome, not absolute tile rectangles:
## the old rects were tuned to 100x70 and distort at any other size.

const SceneScript = preload("res://src/exploration/OverworldScene.gd")


func _scene() -> Node:
	var s = SceneScript.new()
	add_child_autofree(s)
	await wait_frames(2)
	return s


func test_biome_char_at_returns_the_painted_character() -> void:
	var scene = await _scene()
	assert_gt(scene.map_rows.size(), 0, "map_rows must be populated -- otherwise every assert below is vacuous")
	assert_eq(scene.map_rows.size(), scene.MAP_HEIGHT, "one row per map row")
	assert_eq(scene.biome_char_at(0, 0).length(), 1, "a single painted character")
	assert_eq(scene.biome_char_at(-1, 0), "", "out of bounds west is empty")
	assert_eq(scene.biome_char_at(scene.MAP_WIDTH, 0), "", "out of bounds east is empty")
	assert_eq(scene.biome_char_at(0, scene.MAP_HEIGHT), "", "out of bounds south is empty")


func test_zone_follows_the_painted_char_not_the_coordinates() -> void:
	var scene = await _scene()
	var seen := {}
	for ty in range(scene.MAP_HEIGHT):
		for tx in range(scene.MAP_WIDTH):
			var c: String = scene.biome_char_at(tx, ty)
			if c == "":
				continue
			var z: String = scene._get_zone_for_tile(tx, ty)
			if seen.has(c):
				assert_eq(z, seen[c], "char %s gave zone %s here and %s elsewhere -- zone must follow the char alone" % [c, z, seen[c]])
			else:
				seen[c] = z
	assert_gt(seen.size(), 3, "only %d distinct chars sampled -- the map scan did not run" % seen.size())


func test_every_defined_overworld_pool_is_reachable_from_some_zone() -> void:
	var scene = await _scene()
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/enemy_pools.json"))
	assert_true(parsed is Dictionary, "enemy_pools.json must parse")
	var defined := []
	for k in (parsed as Dictionary).keys():
		if str(k).begins_with("overworld_"):
			defined.append(str(k))
	assert_gt(defined.size(), 4, "only %d overworld pools found -- the scan broke" % defined.size())
	var mapped: Array = scene._zone_pool_ids()
	for p in defined:
		assert_true(p in mapped, "pool %s is defined in data but no zone maps to it" % p)
	assert_false("overworld_zz_fabricated" in mapped, "a fabricated pool id is absent, so membership means something")
