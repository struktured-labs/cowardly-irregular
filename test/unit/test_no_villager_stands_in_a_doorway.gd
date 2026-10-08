extends GutTest

const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const MapScripts := preload("res://test/unit/helpers/map_scripts.gd")

## An interior door's press zone is a 2 x 1.5-tile box on the approach below its gate. Frosthold authored Scholar
## Fynn on the Warden Hut door's own tile, (6, 13): he stood in the doorway, and a press there went to whichever of
## the two the nearest-wins router picked. Every village is built; no talking NPC -- nor shop, chest, save point or
## examine point (Sandrift's weapons stall stood on the Rain Ledger door's zone and exit spawn) -- may stand in one.

const VILLAGE_DIR := "res://src/maps/villages"
const BODY_REACH := 8.0


func _collect(n: Node, doors: Array, npcs: Array) -> void:
	for c in n.get_children():
		if c is AreaTransition and c.get("require_interaction") == true:
			doors.append(c)
		elif c.has_method("get_npc_id") or c is VillageShop or c is TreasureChest or c is SavePoint or c is QuestExaminePoint:
			npcs.append(c)
		_collect(c, doors, npcs)


func _zone(door: Node2D) -> Rect2:
	for c in door.get_children():
		if c is CollisionShape2D and c.shape is RectangleShape2D:
			var size: Vector2 = (c.shape as RectangleShape2D).size
			return Rect2(door.global_position + c.position - size * 0.5, size)
	return Rect2()


func test_no_villager_stands_in_a_doors_press_zone() -> void:
	var inside: Array = []
	var doors_seen := 0
	var villages := 0
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
		var doors: Array = []
		var npcs: Array = []
		_collect(village, doors, npcs)
		for d in doors:
			var z := _zone(d)
			if not z.has_area():
				continue
			doors_seen += 1
			for n in npcs:
				# A villager's body is ~half a tile: standing on the zone's edge still puts it in the doorway.
				var p: Vector2 = (n as Node2D).global_position
				if z.grow(BODY_REACH).has_point(p):
					var who = n.get("npc_name") if n.has_method("get_npc_id") else n.get_script().get_global_name()
					inside.append("%s: %s @%s in %s" % [path.get_file(), str(who), str((n as Node2D).global_position / 32.0), d.name])
	assert_gt(villages, 10, "CONTROL: the walk built the villages (%d)" % villages)
	assert_gt(doors_seen, 15, "CONTROL: interior doors with a press zone were found (%d)" % doors_seen)
	assert_eq(inside, [], "an interactable stands in a doorway: %s" % [inside])


func after_all() -> void:
	SoundState.restore()
