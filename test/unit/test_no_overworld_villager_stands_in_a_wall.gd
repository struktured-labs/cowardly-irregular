extends GutTest

## The overworld reach guard lets a thing sit inside terrain if open ground is near, which is right for a signpost you read from beside it.
## A PERSON drawn standing inside a wall is wrong however close the ground is, so every overworld's villagers are judged on the tile they stand on.

const WORLDS := [
	"res://src/exploration/OverworldScene.gd",
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


## Standing villagers: OverworldNPC itself (not WanderingNPC, judged by its patrol elsewhere), a person rather than an object.
func _villagers(map: Node) -> Array:
	var out: Array = []
	var stack: Array = [map]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n.get_script() == null or str(n.get_script().resource_path).get_file() != "OverworldNPC.gd":
			continue
		if bool(n.get("is_object")) or not bool(n.get("interactable")):
			continue
		out.append(n)
	return out


func test_no_overworld_villager_stands_on_an_impassable_tile() -> void:
	var judged := 0
	for path in WORLDS:
		var map := _build(path)
		await get_tree().physics_frame
		if "monster_spawner" in map and map.monster_spawner != null:
			map.monster_spawner.set_enabled(false)
		var people := _villagers(map)
		assert_gt(people.size(), 2, "CONTROL: %s has standing villagers to judge (%d)" % [path.get_file(), people.size()])
		for npc in people:
			var at: Vector2 = (npc as Node2D).global_position
			judged += 1
			assert_true(map.walker_can_stand(at), "%s %s stands inside a wall at tile %s" % [path.get_file().get_basename(), npc.npc_name, str(Vector2i(int(floor(at.x / map.TILE_SIZE)), int(floor(at.y / map.TILE_SIZE))))])
		_vp.free()
	assert_gt(judged, 30, "CONTROL: villagers judged across the six overworlds (%d)" % judged)

