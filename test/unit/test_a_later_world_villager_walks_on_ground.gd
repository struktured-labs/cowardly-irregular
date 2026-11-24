extends GutTest

## The W1 patrol legs were checked against the painted river in .809; the five later overworlds' villagers never were.
## A patrol is a fixed loop of straight legs, so a leg that crosses a wall or the void walks the villager through it every lap.

const STEP_PX := 8.0
const WORLDS := [
	"res://src/exploration/SuburbanOverworld.gd",
	"res://src/exploration/SteampunkOverworld.gd",
	"res://src/exploration/IndustrialOverworld.gd",
	"res://src/exploration/FuturisticOverworld.gd",
	"res://src/exploration/AbstractOverworld.gd",
]

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


## The first point along a -> b where a walker cannot stand, or Vector2.INF when the whole leg is ground.
func _first_blocked(map: Node, a: Vector2, b: Vector2) -> Vector2:
	var n: int = maxi(1, int(ceil(a.distance_to(b) / STEP_PX)))
	for k in n + 1:
		var p: Vector2 = a.lerp(b, float(k) / n)
		if not map.walker_can_stand(p):
			return p
	return Vector2.INF


func test_no_later_world_villager_patrols_through_a_wall() -> void:
	var judged := 0
	for path in WORLDS:
		var map := _build(path)
		await get_tree().physics_frame
		map.monster_spawner.set_enabled(false)
		var world: String = path.get_file().get_basename()
		var walkers := 0
		for n in map.get_children():
			if not (n is WanderingNPC):
				continue
			walkers += 1
			var pts: Array = n.get_patrol()
			for i in pts.size():
				var at := _first_blocked(map, pts[i], pts[(i + 1) % pts.size()])
				var cell := Vector2i(int(floor(at.x / map.TILE_SIZE)), int(floor(at.y / map.TILE_SIZE))) if at != Vector2.INF else Vector2i(-1, -1)
				assert_eq(at, Vector2.INF, "%s %s: leg %d leaves the ground at tile %s" % [world, n.npc_name, i, str(cell)])
				judged += 1
		assert_gt(walkers, 0, "CONTROL %s: it has villagers on patrol" % world)
		_vp.free()
	assert_gt(judged, 15, "CONTROL: patrol legs were judged (%d)" % judged)


func test_the_sampler_sees_a_wall() -> void:
	var map := _build(WORLDS[1])
	await get_tree().physics_frame
	map.monster_spawner.set_enabled(false)
	var far := Vector2(-40, -40)
	assert_ne(_first_blocked(map, Vector2(map.TILE_SIZE * 2.5, map.TILE_SIZE * 2.5), far), Vector2.INF, "CONTROL: a leg that runs off the map is caught")
