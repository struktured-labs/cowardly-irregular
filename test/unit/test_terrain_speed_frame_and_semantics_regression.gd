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
const TG := preload("res://src/exploration/TileGenerator.gd")

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


## The W1 values. Pinned as a TABLE, not as atlas indices -- the indices were the bug.
func test_world1_rough_terrain_table_is_pinned() -> void:
	var script = load("res://src/exploration/TileGenerator.gd")
	var gen = script.new()
	var table: Dictionary = gen._get_rough_terrain_speeds()
	gen.free()
	assert_eq(table.size(), 8, "W1 declares exactly eight rough tile types")
	assert_almost_eq(float(table.get(script.TileType.SWAMP, -1.0)), 0.45, 0.001, "swamp is the heaviest drag")
	assert_almost_eq(float(table.get(script.TileType.FOREST, -1.0)), 0.5, 0.001, "forest half speed")
	assert_almost_eq(float(table.get(script.TileType.SNOW_TREE, -1.0)), 0.5, 0.001, "snow trees match forest")
	assert_almost_eq(float(table.get(script.TileType.COAST, -1.0)), 0.7, 0.001, "coast is wading")
	assert_almost_eq(float(table.get(script.TileType.SAND, -1.0)), 0.8, 0.001, "sand is a mild drag")
	assert_almost_eq(float(table.get(script.TileType.ICE, -1.0)), 0.85, 0.001, "ice is careful footing, not a slide")
	assert_almost_eq(float(table.get(script.TileType.MOUNTAIN, -1.0)), 0.4, 0.001, "mountain very slow")
	assert_almost_eq(float(table.get(script.TileType.WATER, -1.0)), 0.5, 0.001, "water half speed (wading)")


## THE SUBJECT of the 2026-08-26 change: the table above is a declaration, this measures what a body standing on W1 actually feels.
func test_w1_walkable_ground_offers_more_than_one_speed() -> void:
	var built: Dictionary = await _build("medieval")
	var m = built["map"]
	var p = built["player"]
	var layer = m.get_node_or_null("TileMapCollision")
	if layer == null:
		layer = m.get_node_or_null("TileMap")
	assert_not_null(layer, "W1 built a tile layer")
	var space = built["viewport"].world_2d.direct_space_state
	var tiers := {}
	var standable := 0
	var seen := {}
	for cell in layer.get_used_cells():
		var ac: Vector2i = layer.get_cell_atlas_coords(cell)
		if seen.has(ac):
			continue
		seen[ac] = true
		var q := PhysicsShapeQueryParameters2D.new()
		var s := CircleShape2D.new()
		s.radius = 4.0
		q.shape = s
		q.collision_mask = 1
		var pos: Vector2 = layer.to_global(layer.map_to_local(cell))
		q.transform = Transform2D(0.0, pos)
		if not space.intersect_shape(q, 1).is_empty():
			continue
		standable += 1
		p.global_position = pos
		tiers[snappedf(p._get_terrain_speed_modifier(), 0.01)] = true
	# CONTROL: a dead walk samples nothing and would satisfy the tier assert vacuously.
	assert_gt(standable, 5, "only %d standable tile variants sampled -- the walk is not reading the map" % standable)
	assert_gt(tiers.size(), 2,
		"W1's walkable ground offers only %d distinct speeds %s -- terrain variety is cosmetic and the map is one surface in several colours" % [tiers.size(), str(tiers.keys())])


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


## THE COMPLAINT ITSELF, and the reason the test above is not enough on its own. That one
## asserts the sampler AGREES WITH the generator's declaration, so re-introducing the defect
## through the base class -- returning `{order[1]: 0.5, order[2]: 0.4, order[3]: 0.5}`, which
## is precisely what the old hardcoded match did -- keeps sampler and declaration in perfect
## agreement and passes it. Measured: that mutation scored 4/4 green. Consistency checks cannot
## catch a wrong declaration, so this pins the PROPERTY instead: rough terrain is a minority
## feature. A world whose common ground is "rough" has no ordinary walking speed at all.
## LIMIT, stated because the mutation only tripped it through W2: this catches rough-as-default,
## not a single wrong entry in one world. Which tiles are rough is an authoring call and no test
## can adjudicate it -- the three checks here cover sampler-ignores-declaration, foreign tile
## types, and rough-as-the-common-ground, and deliberately stop there.
func test_rough_terrain_is_a_minority_of_every_world_and_never_the_common_ground() -> void:
	var offenders: Array = []
	var worlds_measured := 0

	for world in OVERWORLDS.keys():
		var built: Dictionary = await _build(world)
		var m = built["map"]
		var p = built["player"]
		var gen = m.tile_generator
		var order: Array = gen._get_tile_order()
		var cols: int = int(gen._get_atlas_dimensions().x)
		var layer = m.get_node_or_null("TileMapCollision")
		if layer == null:
			layer = m.get_node_or_null("TileMap")
		if layer == null:
			continue

		# STANDABLE ONLY. "the default surface" is a claim about ground a body can
		# occupy, and MOUNTAIN/WATER sit in the rough table as inert entries the test
		# below pins by name. Counting them made this metric largely a measure of how
		# much OCEAN a world has -- W1 is 28% water, so the denominator was mostly sea
		# floor. It passed at 45% only while forest was tiny, and would have gone red on
		# any world that grew a woodland while staying entirely walkable.
		var impassable: Array = gen._get_impassable_types()
		var speed_of := {}
		var count := {}
		var standable := 0
		var cells: Array = layer.get_used_cells()
		for cell in cells:
			var ac: Vector2i = layer.get_cell_atlas_coords(cell)
			var aidx: int = ac.y * cols + ac.x
			var atype = order[aidx] if aidx >= 0 and aidx < order.size() else -1
			if atype in impassable:
				continue
			count[ac] = int(count.get(ac, 0)) + 1
			standable += 1
			if not speed_of.has(ac):
				p.global_position = layer.to_global(layer.map_to_local(cell))
				speed_of[ac] = p._get_terrain_speed_modifier()
		if standable == 0:
			continue
		worlds_measured += 1

		var slowed_cells := 0
		var commonest: Vector2i = Vector2i(-1, -1)
		for ac in count.keys():
			if float(speed_of[ac]) < 1.0:
				slowed_cells += int(count[ac])
			if commonest == Vector2i(-1, -1) or int(count[ac]) > int(count[commonest]):
				commonest = ac

		var frac := float(slowed_cells) / float(standable)
		if frac >= 0.5:
			offenders.append("%s: %.0f%% of STANDABLE tiles are slowed -- rough terrain is the default surface" % [world, frac * 100.0])
		if float(speed_of[commonest]) < 1.0:
			var idx: int = commonest.y * cols + commonest.x
			var tname = order[idx] if idx >= 0 and idx < order.size() else -1
			offenders.append("%s: its MOST COMMON tile (type %s, %d cells) is slowed to %.2fx" % [
				world, str(tname), int(count[commonest]), float(speed_of[commonest])])

	assert_eq(worlds_measured, OVERWORLDS.size(),
		"measured %d of %d worlds -- the rest placed no tiles" % [worlds_measured, OVERWORLDS.size()])
	assert_true(offenders.is_empty(), "\n  ".join(offenders))


## TWO TABLES INTERACT AND NOTHING SURFACED IT. A tile can be declared rough AND declared
## impassable -- and then its rough speed can never fire, because the player cannot stand on
## it. Measured 2026-08-18 on W1: FOREST 225/225 cells standable, felt 0.50x; MOUNTAIN 213
## cells and WATER 1675 cells, both in _get_impassable_types(), both ZERO standable. So the
## comment this code carried for months -- "Forest/Mountain/Water = slower instead of blocked"
## -- was true of exactly one of the three, and a reader would reasonably believe water is
## wadeable at half speed.
##
## TWO assertions, because one of them alone was an overclaim I caught while mutating.
##   (a) RELATIONSHIP: a rough tile that blocks must have no standable cell, and one that
##       does not block must have some. Catches collision failing to apply, and a rough
##       entry that is unreachable for a reason other than its own impassability.
##   (b) INERT ROSTER: which rough entries can never fire, pinned by name. (a) alone does
##       NOT catch a new rough entry being swallowed -- adding `WALL: 0.5` yields
##       blocks=true, standable=0, which (a) reads as perfectly consistent. It is
##       consistent; it is also dead config, and only a roster pin sees it.
## The roster is deliberately small and a change to it is informative either way: making
## mountains walkable (the original intent) reds it and says so, which is the right amount
## of friction for a decision that silently activates a speed nobody has felt.
func test_a_rough_entry_is_live_exactly_when_its_tile_is_not_impassable() -> void:
	var built: Dictionary = await _build("medieval")
	var m = built["map"]
	var p = built["player"]
	var gen = m.tile_generator
	var table: Dictionary = gen._get_rough_terrain_speeds()
	var impassable: Array = gen._get_impassable_types()
	var order: Array = gen._get_tile_order()
	var cols: int = int(gen._get_atlas_dimensions().x)
	var layer = m.get_node_or_null("TileMapCollision")
	if layer == null:
		layer = m.get_node_or_null("TileMap")
	assert_not_null(layer, "W1 built a tile layer")
	var space = built["viewport"].world_2d.direct_space_state

	var live := 0
	var inert := 0
	var offenders: Array = []
	for t in table.keys():
		var placed := 0
		var standable := 0
		for cell in layer.get_used_cells():
			var ac: Vector2i = layer.get_cell_atlas_coords(cell)
			var idx: int = ac.y * cols + ac.x
			if idx < 0 or idx >= order.size() or order[idx] != t:
				continue
			placed += 1
			var q := PhysicsShapeQueryParameters2D.new()
			var s := CircleShape2D.new()
			s.radius = 4.0
			q.shape = s
			q.collision_mask = 1
			q.transform = Transform2D(0.0, layer.to_global(layer.map_to_local(cell)))
			if space.intersect_shape(q, 1).is_empty():
				standable += 1
		if placed == 0:
			continue
		var blocks: bool = t in impassable
		if blocks:
			inert += 1
		else:
			live += 1
		if blocks and standable > 0:
			offenders.append("tile %s is in _get_impassable_types() yet %d/%d cells are standable" % [str(t), standable, placed])
		if not blocks and standable == 0:
			offenders.append("tile %s is NOT impassable yet 0/%d cells are standable -- its rough speed %s can never fire" % [
				str(t), placed, str(table[t])])

	# Controls: the sweep must have found members on BOTH sides, or the check is vacuous.
	assert_gt(live, 0, "no rough tile type is reachable in W1 -- the rough-terrain feature is entirely dead")
	assert_gt(inert, 0, "no rough tile type is impassable -- this guard's whole subject is absent, so its silence means nothing")
	assert_true(offenders.is_empty(), "\n  ".join(offenders))

	# (b) the inert roster, by name. Measured: MOUNTAIN (213 cells) and WATER (1675) place
	# tiles and block every one of them, so their 0.4/0.5 have never been felt by a player.
	var inert_names: Array = []
	for t in table.keys():
		if t in impassable:
			inert_names.append(int(t))
	inert_names.sort()
	var expected: Array = [int(TG.TileType.MOUNTAIN), int(TG.TileType.WATER)]
	expected.sort()
	assert_eq(inert_names, expected,
		("W1's DEAD rough entries changed. Each tile here is declared rough AND impassable, " +
		"so its speed can never fire. Adding one is dead config; removing one activates a " +
		"speed no player has ever felt. Either may be intended -- update this list and say " +
		"which in the commit."))


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
