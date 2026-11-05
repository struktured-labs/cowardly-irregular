extends GutTest

## cowir-main 22008, off the .771 Harmonia store frame: Scholar Milo was authored centred on the line between the pond and the
## grass, so half of him stood in the water under the tier wall. A village NPC is centred on its position, so BOTH halves of
## its footprint must stand on walkable ground, judged by the village's own _is_cell_walkable.

const VILLAGES := "res://src/maps/villages"
const HALF := 12.0


func _village(path: String) -> Node:
	var v = load(path).instantiate() if path.ends_with(".tscn") else load(path).new()
	add_child_autofree(v)
	return v


func _scenes() -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(VILLAGES):
		if f.ends_with("Village.gd") and f != "BaseVillage.gd":
			var tscn := VILLAGES + "/" + f.replace(".gd", ".tscn")
			out.append(tscn if ResourceLoader.exists(tscn) else VILLAGES + "/" + f)
	return out


func _offenders(v: Node) -> Array:
	var out: Array = []
	if v.get("npcs") == null:
		return out
	for n in v.npcs.get_children():
		if not (n is OverworldNPC) or n is WanderingNPC:
			continue
		var foot: Vector2 = (n as Node2D).position + Vector2(0, 8)
		for dx in [-HALF, HALF]:
			var cell := Vector2i(floori((foot.x + dx) / 32.0), floori(foot.y / 32.0))
			if not v._is_cell_walkable(cell):
				out.append("%s: %s at %s has a foot on %s" % [str(v.name), str(n.get("npc_name")), (n as Node2D).position, cell])
				break
	return out


func test_milo_stands_on_dry_ground() -> void:
	var v := _village(VILLAGES + "/HarmoniaVillage.tscn")
	var milo: Node2D = null
	for n in v.npcs.get_children():
		if str(n.get("npc_name")) == "Scholar Milo":
			milo = n
	assert_not_null(milo, "PRECONDITION: Harmonia places Scholar Milo")
	if milo == null:
		return
	assert_eq(_offenders(v).filter(func(o): return "Scholar Milo" in o), [], "Milo's footprint must be on walkable ground")


func test_no_fixed_villager_stands_on_unwalkable_ground() -> void:
	var offenders: Array = []
	var judged := 0
	for path in _scenes():
		var v := _village(path)
		if v.get("npcs") != null:
			for n in v.npcs.get_children():
				if n is OverworldNPC and not (n is WanderingNPC):
					judged += 1
		offenders.append_array(_offenders(v))
	assert_gt(judged, 40, "FLOOR: every village's fixed NPCs must be judged (saw %d)" % judged)
	assert_eq(offenders, [], "a villager is authored with a foot on unwalkable ground: %s" % [offenders])


## CONTROL: the check sees the defect it exists for. Milo's OLD spot straddles the pond's edge.
func test_the_old_spot_is_caught() -> void:
	var v := _village(VILLAGES + "/HarmoniaVillage.tscn")
	var foot := Vector2(24 * 32, 10 * 32) + Vector2(0, 8)
	assert_false(v._is_cell_walkable(Vector2i(floori((foot.x - HALF) / 32.0), floori(foot.y / 32.0))),
		"CONTROL: the old spot's left half is on the pond")
