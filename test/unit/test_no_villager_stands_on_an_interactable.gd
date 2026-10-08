extends GutTest

const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const MapScripts := preload("res://test/unit/helpers/map_scripts.gd")

## Rivet Row authored "Factory Kid Pell" on the exact tile of its save crystal, (17, 8): he stood on it and a press
## there reached whichever the nearest-wins router picked. The NPC-alone guard compares NPCs only with NPCs, so it
## could not see this. Every village is built and no talking NPC may share a cell with a save point or a chest.

const VILLAGE_DIR := "res://src/maps/villages"


func _collect(n: Node, npcs: Array, props: Array) -> void:
	for c in n.get_children():
		if c.has_method("get_npc_id"):
			npcs.append(c)
		elif c is SavePoint or c is TreasureChest:
			props.append(c)
		_collect(c, npcs, props)


func test_no_villager_shares_a_cell_with_a_save_point_or_chest() -> void:
	var clashes: Array = []
	var villages := 0
	var props_seen := 0
	for path in MapScripts.maps_in(VILLAGE_DIR):
		var vp := SubViewport.new()
		vp.size = Vector2i(64, 64)
		vp.world_2d = World2D.new()
		add_child_autofree(vp)
		var village = load(path).new()
		vp.add_child(village)
		await get_tree().physics_frame
		await get_tree().process_frame
		villages += 1
		var tile: int = int(village.get("TILE_SIZE")) if village.get("TILE_SIZE") != null else 32
		var npcs: Array = []
		var props: Array = []
		_collect(village, npcs, props)
		props_seen += props.size()
		var prop_cells := {}
		for p in props:
			prop_cells[Vector2i((p as Node2D).global_position / tile)] = p
		for n in npcs:
			var cell := Vector2i((n as Node2D).global_position / tile)
			if prop_cells.has(cell):
				var p: Node = prop_cells[cell]
				clashes.append("%s: %s on %s at %s" % [path.get_file(), str(n.get("npc_name")), p.get_script().get_global_name(), str(cell)])
	assert_gt(villages, 10, "CONTROL: the walk built the villages (%d)" % villages)
	assert_gt(props_seen, 15, "CONTROL: save points and chests were found (%d)" % props_seen)
	assert_eq(clashes, [], "a villager stands on an interactable: %s" % [clashes])


func after_all() -> void:
	SoundState.restore()
