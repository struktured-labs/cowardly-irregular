extends GutTest

## struktured, playing .808 (cowir-main 26373): a villager stood mid-river in Eldertree Forest, and roamers that cannot swim waded too.
## Two causes: the Merchant's and the Lost Pilgrim's patrol legs were straight lines across the river, and a roamer's step asked the map nothing.

const MAP := "res://src/exploration/OverworldScene.gd"
const RoamerScript := preload("res://src/exploration/RoamingMonster.gd")
const STEP_PX := 8.0

var _vp: SubViewport
var _map: Node


func before_all() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(64, 64)
	_vp.world_2d = World2D.new()
	add_child(_vp)
	_map = load(MAP).new()
	_vp.add_child(_map)
	await get_tree().physics_frame
	_map.monster_spawner.set_enabled(false)


func after_all() -> void:
	_vp.queue_free()


func _centre(tx: int, ty: int) -> Vector2:
	return Vector2((tx + 0.5) * _map.TILE_SIZE, (ty + 0.5) * _map.TILE_SIZE)


## The first point along a -> b where a walker cannot stand, or Vector2.INF when the whole leg is ground.
func _first_wet(a: Vector2, b: Vector2) -> Vector2:
	var n: int = maxi(1, int(ceil(a.distance_to(b) / STEP_PX)))
	for k in n + 1:
		var p: Vector2 = a.lerp(b, float(k) / n)
		if not _map.walker_can_stand(p):
			return p
	return Vector2.INF


## A bank: a ground tile whose west neighbour is water, found on the painted map rather than typed.
func _bank() -> Vector2i:
	for ty in range(40, 50):
		for tx in range(1, _map.MAP_WIDTH):
			if _map.biome_char_at(tx - 1, ty) == "~" and _map.biome_char_at(tx - 2, ty) == "~" and _map.biome_char_at(tx, ty) != "~" and _map.walker_can_stand(_centre(tx, ty)) and _map.walker_can_stand(_centre(tx + 1, ty)) and _map.walker_can_stand(_centre(tx + 2, ty)):
				return Vector2i(tx, ty)
	return Vector2i(-1, -1)


func _roamer(species: String, at: Vector2, checked: bool) -> Node:
	var m: Node = RoamerScript.new()
	m.monster_id = species
	m.monster_types = [species]
	m.global_position = at
	_map.add_child(m)
	m.set_process(false)
	m._spawn_origin = at
	m._state = 0
	m._dir = Vector2.LEFT
	if checked:
		m.ground_check = Callable(_map.monster_spawner, "can_roam")
	return m


func _walk_west(m: Node) -> Vector2:
	for _i in 8:
		m._move(0.1)
	var at: Vector2 = m.global_position
	m.queue_free()
	return at


func test_the_map_knows_water_from_ground() -> void:
	var bank := _bank()
	assert_ne(bank, Vector2i(-1, -1), "CONTROL: the W1 map has a west-facing river bank")
	assert_true(_map.walker_can_stand(_centre(bank.x, bank.y)), "the bank is ground")
	assert_false(_map.walker_can_stand(_centre(bank.x - 1, bank.y)), "the river beside it is not")
	assert_false(_map.walker_can_stand(Vector2(-40, -40)), "off the map is not ground either")


func test_no_wanderer_patrols_through_water() -> void:
	var judged: int = 0
	for n in _map.get_children():
		if not (n is WanderingNPC):
			continue
		var pts: Array = n.get_patrol()
		for i in pts.size():
			var wet := _first_wet(pts[i], pts[(i + 1) % pts.size()])
			assert_eq(wet, Vector2.INF, "%s: leg %d of the patrol leaves the ground at %s" % [n.npc_name, i, str(wet)])
			judged += 1
	assert_gt(judged, 8, "CONTROL: patrol legs were judged (%d)" % judged)
	## The shipped Merchant leg, (31,22) -> (20,23) in authored cells: the sampler must see the river it crossed.
	var s: float = _map.MAP_SCALE * _map.TILE_SIZE
	assert_ne(_first_wet(Vector2(31 * s + 16, 22 * s + 16), Vector2(20 * s + 16, 23 * s + 16)), Vector2.INF, "CONTROL: the old Merchant leg crosses the river under this sampler")


func test_a_roamer_that_cannot_swim_turns_back_at_the_bank() -> void:
	var bank := _bank()
	assert_ne(bank, Vector2i(-1, -1), "CONTROL: a bank to walk at")
	if bank.x < 0:
		return
	var start := _centre(bank.x, bank.y)
	assert_false(MonsterSpawner.crosses_water("goblin"), "CONTROL: a goblin is not a water crosser")
	var free_end: Vector2 = _walk_west(_roamer("goblin", start, false))
	assert_false(_map.walker_can_stand(free_end), "CONTROL: with no ground check the same goblin walks into the river (%s)" % str(free_end))
	var held_end: Vector2 = _walk_west(_roamer("goblin", start, true))
	assert_true(_map.walker_can_stand(held_end), "a goblin stops at the bank, it ended at %s" % str(held_end))


func test_a_flier_still_crosses() -> void:
	var bank := _bank()
	if bank.x < 0:
		fail_test("no bank")
		return
	assert_true(MonsterSpawner.crosses_water("bat"), "CONTROL: a bat is listed as a water crosser")
	var end: Vector2 = _walk_west(_roamer("bat", _centre(bank.x, bank.y), true))
	assert_false(_map.walker_can_stand(end), "a bat flies on over the river (%s)" % str(end))


func test_a_roamer_is_never_placed_in_water() -> void:
	var bank := _bank()
	var sp: Node = _map.monster_spawner
	assert_false(sp.can_roam(_centre(bank.x - 1, bank.y), "goblin"), "a goblin may not step onto the river")
	assert_true(sp.can_roam(_centre(bank.x, bank.y), "goblin"), "CONTROL: it may step along the bank")
	assert_true(sp.can_roam(_centre(bank.x - 1, bank.y), "bat"), "a bat may")
	assert_false(sp._host_ground(_centre(bank.x - 1, bank.y)), "a spawn point in the river is refused")


func test_every_listed_crosser_is_a_real_species() -> void:
	var listed: Array = (JSON.parse_string(FileAccess.get_file_as_string(MonsterSpawner.WATER_CROSSERS_PATH)) as Dictionary).get("species", [])
	var db: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	assert_gt(listed.size(), 0, "CONTROL: the list names species")
	for s in listed:
		assert_true(db.has(str(s)), "%s is listed as a water crosser and is not in monsters.json" % s)
