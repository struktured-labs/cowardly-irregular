extends GutTest

## The atlas has carried 16 variant tiles since day one and get_tile_id collapsed every type to
## ONE of them. Variants are now chosen per cell: deterministic (same cell → same tile across
## rebuilds), spread (a field uses more than one), and always the right TYPE.

const TG := preload("res://src/exploration/TileGenerator.gd")


func test_variant_ids_are_all_the_requested_type() -> void:
	var gen := TG.new()
	autofree(gen)
	var order: Array = gen._get_tile_order()
	for type in TG.VARIANT_IDS:
		for id in TG.VARIANT_IDS[type]:
			assert_eq(int(order[id]), int(type), "atlas id %d is type %d" % [id, type])
	assert_false(TG.VARIANT_IDS.has(TG.TileType.WATER), "water frames are ANIMATION, not variants")


func test_variant_is_deterministic_and_spread() -> void:
	var seen := {}
	for x in range(12):
		for y in range(12):
			var salt := x * 73856093 ^ y * 19349663
			var a := TG.get_tile_id_variant(TG.TileType.VILLAGE_GRASS, salt)
			var b := TG.get_tile_id_variant(TG.TileType.VILLAGE_GRASS, salt)
			assert_eq(a, b, "same salt, same tile")
			seen[a] = true
	assert_gt(seen.size(), 1, "a 12x12 field uses more than one grass tile")
	for id in seen:
		assert_true(id in TG.VARIANT_IDS[TG.TileType.VILLAGE_GRASS], "only grass ids")


func test_types_without_variants_fall_back_to_get_tile_id() -> void:
	assert_eq(TG.get_tile_id_variant(TG.TileType.WALL, 12345), TG.get_tile_id(TG.TileType.WALL))
	assert_eq(TG.get_tile_id_variant(TG.TileType.WATER, 7), TG.get_tile_id(TG.TileType.WATER))


func test_base_village_atlas_for_is_stable_per_cell() -> void:
	var v := BaseVillage.new()
	add_child_autofree(v)
	var c := Vector2i(4, 9)
	assert_eq(v._atlas_for(TG.TileType.VILLAGE_PATH, c), v._atlas_for(TG.TileType.VILLAGE_PATH, c))
	var ac := v._atlas_for(TG.TileType.VILLAGE_PATH, c)
	var id := ac.y * 5 + ac.x
	assert_true(id in TG.VARIANT_IDS[TG.TileType.VILLAGE_PATH], "resolves to a path tile")
