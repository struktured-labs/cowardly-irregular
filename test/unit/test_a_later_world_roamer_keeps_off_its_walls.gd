extends GutTest

## The W1 roamer step asks the painted map since .809; the five later overworlds never answered, so their roamers
## could step onto any painted tile: house walls, fences, the steampunk fountain, the drainage channels, the void.

const RoamerScript := preload("res://src/exploration/RoamingMonster.gd")
const WORLDS := {
	"suburban": ["res://src/exploration/SuburbanOverworld.gd", "res://src/exploration/SuburbanTileGenerator.gd"],
	"steampunk": ["res://src/exploration/SteampunkOverworld.gd", "res://src/exploration/SteampunkTileGenerator.gd"],
	"industrial": ["res://src/exploration/IndustrialOverworld.gd", "res://src/exploration/IndustrialTileGenerator.gd"],
	"futuristic": ["res://src/exploration/FuturisticOverworld.gd", "res://src/exploration/FuturisticTileGenerator.gd"],
	"abstract": ["res://src/exploration/AbstractOverworld.gd", "res://src/exploration/AbstractTileGenerator.gd"],
}
const SPECIES := "slime"

var _vp: SubViewport


func after_each() -> void:
	if is_instance_valid(_vp):
		_vp.free()


func _build(path: String) -> Node:
	_vp = SubViewport.new()
	_vp.size = Vector2i(64, 64)
	_vp.world_2d = World2D.new()
	add_child(_vp)
	var map: Node = load(path).new()
	_vp.add_child(map)
	return map


## Painted chars whose tile this world's own generator calls impassable.
func _blocked_chars(map: Node, gen_path: String) -> Dictionary:
	var gen: Node = load(gen_path).new()
	var blocked: Array = gen._get_impassable_types()
	gen.free()
	var out := {}
	for row in map.map_rows:
		for ch in row:
			if blocked.has(map._char_to_tile_type(ch)):
				out[ch] = true
	return out


## An open cell whose west neighbour is blocked and whose two east neighbours are open, found on the painted rows.
func _wall_edge(map: Node, blocked: Dictionary) -> Vector2i:
	for ty in range(2, map.map_rows.size() - 2):
		var row: String = map.map_rows[ty]
		for tx in range(1, row.length() - 3):
			if blocked.has(row[tx - 1]) and not blocked.has(row[tx]) and not blocked.has(row[tx + 1]) and not blocked.has(row[tx + 2]):
				return Vector2i(tx, ty)
	return Vector2i(-1, -1)


func _centre(map: Node, c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * map.TILE_SIZE, (c.y + 0.5) * map.TILE_SIZE)


## Where a roamer started on `at` ends after walking west for 0.8 s.
func _walk_west(map: Node, at: Vector2, checked: bool) -> Vector2:
	var m: Node = RoamerScript.new()
	m.monster_id = SPECIES
	m.monster_types = [SPECIES]
	m.global_position = at
	map.add_child(m)
	m.set_process(false)
	m._spawn_origin = at
	m._state = 0
	m._dir = Vector2.LEFT
	if checked:
		m.ground_check = Callable(map.monster_spawner, "can_roam")
	for _i in 8:
		m._move(0.1)
	var end: Vector2 = m.global_position
	m.free()
	return end


func test_every_later_world_knows_its_walls_from_its_ground() -> void:
	for world in WORLDS:
		var map := _build(WORLDS[world][0])
		await get_tree().physics_frame
		map.monster_spawner.set_enabled(false)
		var blocked := _blocked_chars(map, WORLDS[world][1])
		assert_gt(blocked.size(), 0, "CONTROL %s: its painted map holds some tile its generator calls impassable" % world)
		var edge := _wall_edge(map, blocked)
		assert_ne(edge, Vector2i(-1, -1), "CONTROL %s: an open cell stands east of a blocked one" % world)
		assert_true(map.has_method("walker_can_stand"), "%s answers whether a roamer may stand somewhere" % world)
		if edge == Vector2i(-1, -1) or not map.has_method("walker_can_stand"):
			_vp.free()
			continue
		assert_true(map.walker_can_stand(_centre(map, edge)), "%s: the open cell is ground" % world)
		assert_false(map.walker_can_stand(_centre(map, edge + Vector2i.LEFT)), "%s: the blocked cell west of it is not" % world)
		assert_false(map.walker_can_stand(Vector2(-40, -40)), "%s: off the map is not ground" % world)
		_vp.free()


func test_a_later_world_roamer_stops_at_the_wall() -> void:
	for world in WORLDS:
		var map := _build(WORLDS[world][0])
		await get_tree().physics_frame
		map.monster_spawner.set_enabled(false)
		var edge := _wall_edge(map, _blocked_chars(map, WORLDS[world][1]))
		if edge == Vector2i(-1, -1):
			fail_test("CONTROL %s: no wall edge to walk at" % world)
			_vp.free()
			continue
		var wall_east := float((edge.x) * map.TILE_SIZE)
		var start := _centre(map, edge)
		var loose := _walk_west(map, start, false)
		assert_lt(loose.x, wall_east, "CONTROL %s: a roamer that asks nothing walks into the wall (ended x %.0f, wall face %.0f)" % [world, loose.x, wall_east])
		var held := _walk_west(map, start, true)
		assert_gte(held.x, wall_east, "%s: a roamer that asks the map stops at the wall face (ended x %.0f, wall face %.0f)" % [world, held.x, wall_east])
		_vp.free()
