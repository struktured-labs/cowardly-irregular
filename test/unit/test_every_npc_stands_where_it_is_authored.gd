extends GutTest

## 29 authored NPC/interactable spots sat on walls or furniture and the runtime sweep moved them, so what shipped was the sweep's guess, not the author's choice.

const DIRS := ["res://src/maps/interiors", "res://src/maps/villages"]
const NOT_A_MAP := ["BaseInterior.gd", "BaseVillage.gd", "InteriorPlacementSweep.gd"]


func _map_scripts() -> Array:
	var out: Array = []
	for dir in DIRS:
		var d := DirAccess.open(dir)
		for f in d.get_files():
			if f.ends_with(".gd") and not (f in NOT_A_MAP):
				out.append("%s/%s" % [dir, f])
	return out


## Bring one map into the tree and report what its sweep did: {swept, moved}.
func _run(path: String) -> Dictionary:
	var scr = load(path)
	if scr == null or not scr.can_instantiate():
		return {}
	InteriorPlacementSweep.relocations = 0
	InteriorPlacementSweep.sweeps = 0
	var inst = scr.new()
	if not (inst is Node):
		return {}
	add_child_autofree(inst)
	for _i in 3:
		await get_tree().process_frame
	var swept: bool = InteriorPlacementSweep.sweeps > 0 or bool(inst.get("placements_validated"))
	var moved: int = InteriorPlacementSweep.relocations + int(inst.get("relocated_count") if inst.get("relocated_count") != null else 0)
	return {"swept": swept, "moved": moved}


func test_no_map_needs_its_npcs_moved() -> void:
	var moved: Array = []
	var swept := 0
	for path in _map_scripts():
		var r: Dictionary = await _run(path)
		if r.is_empty():
			continue
		if bool(r["swept"]):
			swept += 1
		if int(r["moved"]) > 0:
			moved.append("%s: %d" % [str(path).get_file(), int(r["moved"])])
	assert_gt(swept, 30, "CONTROL: the sweeps must actually run on the maps, saw %d" % swept)
	assert_eq(moved, [], "authored spots on a wall or furniture get moved at runtime; author them where they stand: %s" % [moved])


func test_the_counter_sees_a_planted_offender() -> void:
	InteriorPlacementSweep.relocations = 0
	var host := Node2D.new()
	add_child_autofree(host)
	var npcs := Node2D.new()
	host.add_child(npcs)
	var npc := Node2D.new()
	npc.position = Vector2(0, 0)
	npcs.add_child(npc)
	InteriorPlacementSweep.sweep(host, npcs, null, ["WWW", "W.W", "WWW"], "planted")
	assert_eq(InteriorPlacementSweep.relocations, 1, "CONTROL: an NPC authored on a wall must register as a relocation")
