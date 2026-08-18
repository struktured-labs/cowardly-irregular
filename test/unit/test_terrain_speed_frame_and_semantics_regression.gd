extends GutTest

## `_get_terrain_speed_modifier` carried two independent defects, both measured 2026-08-18.
##
## FRAME. It sampled the AUTHORED TileMap. Under Mode 7 the authored layer is set
## `collision_enabled = false` and a hidden clone 140.6px south does the blocking, so the tile
## that SLOWED you and the tile that STOPPED you were 4.39 tiles apart. Measured with a
## three-arm probe on W1: at a solid WATER region's authored centre (48,48) there were 0
## colliders, at +140.6 south there was 1, at -140.6 north there were 0.
##
## SEMANTICS. It matched hardcoded atlas indices 1/2/3 with a hardcoded 5-column stride, both
## of which are W1's. The other five worlds use 4-column atlases and unrelated tile tables, so
## W1's "forest/mountain/water are rough" became, per world:
##   W2 ROAD·HOUSE_WALL·LAWN   W3 ASPHALT·BRICK_WALL·METAL_FLOOR   W4 IRON_GRATING·BRICK_WALL·
##   SMOKESTACK   W5 DATA_HIGHWAY·SERVER_TOWER·HOLOGRAM_DISPLAY   W6 VOID_GRAY·VOID_BLACK·GRID_LINE
## The player walked at half speed on the primary thoroughfare of every world after the first.
##
## The stride bug alone was BEHAVIOURALLY INERT and that is why it survived review: the only
## matched ids were 1..3, which live in row 0 where `y*5+x` and `y*4+x` both reduce to `x`. It
## would have become live the moment anyone added an arm for an index above 3.
##
## Villages and dungeons are unaffected in both respects -- they use W1's own TileGenerator and
## never call `apply_terrain_collision_alignment`, so they had the right table in the right frame.

const PLAYER := preload("res://src/exploration/OverworldPlayer.gd")

const OVERWORLDS := {
	"medieval": ["res://src/exploration/OverworldScene.gd", "res://src/exploration/TileGenerator.gd"],
	"suburban": ["res://src/exploration/SuburbanOverworld.gd", "res://src/exploration/SuburbanTileGenerator.gd"],
	"steampunk": ["res://src/exploration/SteampunkOverworld.gd", "res://src/exploration/SteampunkTileGenerator.gd"],
	"industrial": ["res://src/exploration/IndustrialOverworld.gd", "res://src/exploration/IndustrialTileGenerator.gd"],
	"futuristic": ["res://src/exploration/FuturisticOverworld.gd", "res://src/exploration/FuturisticTileGenerator.gd"],
	"abstract": ["res://src/exploration/AbstractOverworld.gd", "res://src/exploration/AbstractTileGenerator.gd"],
}

## W6 runs no Mode 7 by design (narrative device), so it has no displaced collider clone.
const NO_MODE7 := ["abstract"]


func _build(world: String) -> Dictionary:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	add_child_autofree(vp)
	var m = load(OVERWORLDS[world][0]).new()
	vp.add_child(m)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var p = PLAYER.new()
	m.add_child(p)
	await get_tree().physics_frame
	return {"map": m, "player": p, "viewport": vp}


func test_every_generators_rough_table_names_only_its_own_tile_types() -> void:
	var checked := 0
	var offenders: Array = []
	for world in OVERWORLDS.keys():
		var script = load(OVERWORLDS[world][1])
		var gen = script.new()
		var valid: Array = []
		for k in script.TileType.keys():
			valid.append(int(script.TileType[k]))
		var table: Dictionary = gen._get_rough_terrain_speeds()
		for t in table.keys():
			checked += 1
			if not (int(t) in valid):
				offenders.append("%s: rough table names %s, absent from its own TileType" % [world, str(t)])
			if float(table[t]) <= 0.0 or float(table[t]) > 1.0:
				offenders.append("%s: rough speed %s is not in (0, 1]" % [world, str(table[t])])
		gen.free()
	# Control: an empty sweep would pass this for free. W1 supplies entries.
	assert_gt(checked, 2, "only %d rough-terrain entries across 6 generators -- the tables did not load" % checked)
	assert_true(offenders.is_empty(), "\n  ".join(offenders))


## The playtested W1 values. Pinned as a TABLE, not as atlas indices -- the indices were the bug.
func test_world1_rough_terrain_is_unchanged_by_the_refactor() -> void:
	var script = load("res://src/exploration/TileGenerator.gd")
	var gen = script.new()
	var table: Dictionary = gen._get_rough_terrain_speeds()
	gen.free()
	assert_eq(table.size(), 3, "W1 declares exactly three rough tile types")
	assert_almost_eq(float(table.get(script.TileType.FOREST, -1.0)), 0.5, 0.001, "forest half speed")
	assert_almost_eq(float(table.get(script.TileType.MOUNTAIN, -1.0)), 0.4, 0.001, "mountain very slow")
	assert_almost_eq(float(table.get(script.TileType.WATER, -1.0)), 0.5, 0.001, "water half speed (wading)")


## THE SUBJECT. Whatever the sampler slows, that world must itself declare rough.
func test_no_world_is_slowed_by_another_worlds_tile_table() -> void:
	var offenders: Array = []
	var slowed_total := 0
	var sampled := 0

	for world in OVERWORLDS.keys():
		var built: Dictionary = await _build(world)
		var m = built["map"]
		var p = built["player"]
		var gen = m.tile_generator
		var table: Dictionary = gen._get_rough_terrain_speeds()
		var order: Array = gen._get_tile_order()
		var cols: int = int(gen._get_atlas_dimensions().x)

		var layer = m.get_node_or_null("TileMapCollision")
		if layer == null:
			layer = m.get_node_or_null("TileMap")
		assert_not_null(layer, "%s built a tile layer" % world)

		var seen := {}
		for cell in layer.get_used_cells():
			var ac: Vector2i = layer.get_cell_atlas_coords(cell)
			if seen.has(ac):
				continue
			seen[ac] = true
			p.global_position = layer.to_global(layer.map_to_local(cell))
			var speed: float = p._get_terrain_speed_modifier()
			sampled += 1
			if speed >= 1.0:
				continue
			slowed_total += 1
			var idx: int = ac.y * cols + ac.x
			var tile_type = order[idx] if idx >= 0 and idx < order.size() else -1
			if not table.has(tile_type):
				offenders.append("%s: tile %s slowed to %.2fx but %s declares no rough entry for it" % [
					world, str(tile_type), speed, world])

	# Controls. Without these an always-1.0 sampler would satisfy the subject for free.
	assert_gt(sampled, 50, "only %d distinct tiles sampled across 6 overworlds" % sampled)
	assert_gt(slowed_total, 0, "NOTHING was slowed anywhere -- the sampler is inert and the check above is vacuous")
	assert_true(offenders.is_empty(), "\n  ".join(offenders))


## The frame. Under Mode 7 the sampler must read the collider clone, not the authored layer.
func test_the_sampler_reads_the_layer_that_owns_collision() -> void:
	var built: Dictionary = await _build("medieval")
	var m = built["map"]
	var p = built["player"]

	var authored = m.get_node_or_null("TileMap")
	var collision = m.get_node_or_null("TileMapCollision")
	assert_not_null(collision, "W1 is a Mode 7 world -- the displaced collider clone must exist")
	assert_false(authored.collision_enabled, "the authored layer is pixels-only once the clone exists")
	assert_almost_eq(collision.position.y - authored.position.y,
		InteractGeometry.MODE7_GROUND_DISPLACEMENT_PX, 0.001,
		"the clone sits one ground displacement south of the authored layer")

	# Find a position where the two layers disagree AND the collision-layer tile is rough.
	# That is the only place the two readings are distinguishable, so it is where to look.
	var gen = m.tile_generator
	var table: Dictionary = gen._get_rough_terrain_speeds()
	var order: Array = gen._get_tile_order()
	var cols: int = int(gen._get_atlas_dimensions().x)
	var found := false
	for cell in collision.get_used_cells():
		var ac: Vector2i = collision.get_cell_atlas_coords(cell)
		var idx: int = ac.y * cols + ac.x
		if idx < 0 or idx >= order.size() or not table.has(order[idx]):
			continue
		var world_pos: Vector2 = collision.to_global(collision.map_to_local(cell))
		var authored_cell: Vector2i = authored.local_to_map(authored.to_local(world_pos))
		var a_ac: Vector2i = authored.get_cell_atlas_coords(authored_cell)
		var a_idx: int = a_ac.y * cols + a_ac.x
		var authored_type = order[a_idx] if a_idx >= 0 and a_idx < order.size() else -1
		if authored_type == order[idx] or table.has(authored_type):
			continue  # indistinguishable here; keep looking
		p.global_position = world_pos
		assert_almost_eq(p._get_terrain_speed_modifier(), float(table[order[idx]]), 0.001,
			"at %s the collision tile is %s (rough) and the authored tile is %s (not) -- the sampler must follow collision" % [
				str(world_pos), str(order[idx]), str(authored_type)])
		found = true
		break
	assert_true(found, "no position found where the two layers disagree -- the frame claim was never exercised")
