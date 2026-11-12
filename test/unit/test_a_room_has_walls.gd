extends GutTest

## Measured 2026-11-12 (.793): no interior had any collision but the inn's hearth. Held "up" for 4 s, the player left
## the inn at (320, -94), the tavern, the cartographer's and the chapel the same way; only the camera stopped at the
## room's edge. Every room now builds its walls from its own layout string (InteriorWalls).

const DIR := "res://src/maps/interiors"
const T := 32
const N4: Array = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


func _room_scripts() -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with("Interior.gd") and f != "BaseInterior.gd":
			out.append(f)
	out.sort()
	return out


func _open(path: String) -> Node:
	var room: Node = load(DIR + "/" + path).new()
	add_child(room)
	await get_tree().process_frame
	return room


func _cell(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / T)), int(floor(pos.y / T)))


func _size(solid: Dictionary) -> Vector2i:
	var w := 0
	var h := 0
	for c in solid:
		w = maxi(w, c.x)
		h = maxi(h, c.y)
	return Vector2i(w, h)  # the ring's far corner = the layout's width and height


## True when `reach` holds `cell` or a cell beside it.
func _touches(reach: Dictionary, cell: Vector2i) -> bool:
	for d in N4:
		if reach.has(cell + d):
			return true
	return false


## Every cell a body of half-width `r` standing at `pos` reaches into.
func _cells_under(pos: Vector2, r: float) -> Array:
	var out: Array = []
	var a := _cell(pos - Vector2(r, r))
	var b := _cell(pos + Vector2(r - 0.01, r - 0.01))
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			out.append(Vector2i(x, y))
	return out


func test_the_builder_seals_a_box_and_leaves_a_door_open() -> void:
	var layout := ["WWWWW", "W...W", "W.T.W", "WDWWW"]
	var solid := InteriorWalls.solid_cells(layout, "T")
	assert_true(solid.has(Vector2i(0, 0)) and solid.has(Vector2i(4, 2)), "a 'W' cell is solid")
	assert_true(solid.has(Vector2i(2, 2)), "a named furniture glyph is solid")
	assert_false(solid.has(Vector2i(1, 3)), "a door glyph on the outer row is not")
	assert_true(solid.has(Vector2i(1, 4)), "the ring outside the map seals what lies beyond the door")
	var reach := InteriorWalls.reach(solid, Vector2i(1, 1))
	assert_eq(reach.size(), 6, "from inside, a walker reaches the five floor cells and the door cell, nothing else")
	var carved := InteriorWalls.solid_cells(["WWW", "W.W", "WWW"], "", [Rect2(32, 64, 32, 32)])
	assert_false(carved.has(Vector2i(1, 2)), "a wall cell under a door's trigger is opened")
	assert_true(carved.has(Vector2i(1, 3)), "and still leads nowhere")
	assert_eq(InteriorWalls.solid_cells(layout, "").has(Vector2i(2, 2)), false, "CONTROL: a glyph nobody named stays floor")


func test_no_room_lets_the_player_out_and_none_seals_anything_off() -> void:
	var rooms := _room_scripts()
	assert_gt(rooms.size(), 25, "CONTROL: the interiors were found (%d)" % rooms.size())
	for f in rooms:
		var room: Node = await _open(f)
		var body := room.get_node_or_null(InteriorWalls.BODY_NAME) as StaticBody2D
		assert_not_null(body, "%s builds its walls" % f)
		if body == null:
			room.free()
			continue
		assert_gt(body.get_child_count(), 3, "%s: the wall body has shapes" % f)
		var solid: Dictionary = body.get_meta("solid_cells")
		var size := _size(solid)
		var player: Node2D = room.player
		var start := _cell(player.position)
		var reach := InteriorWalls.reach(solid, start)
		assert_gt(reach.size(), 4, "%s: the player starts on open floor at %s" % [f, str(start)])
		for c in reach:
			if c.x < 0 or c.y < 0 or c.x >= size.x or c.y >= size.y:
				fail_test("%s: a walker from %s gets OUT of the room at %s" % [f, str(start), str(c)])
				break
		# GameLoop places the player at a NAMED spawn after _ready: none may be inside a wall, or the room traps him at the door.
		for spawn in room.spawn_points:
			room.spawn_player_at(str(spawn))
			var at := _cell(player.position)
			assert_false(solid.has(at), "%s: spawn '%s' puts the player in a solid cell %s" % [f, str(spawn), str(at)])
			assert_true(reach.has(at), "%s: spawn '%s' at %s is cut off from where the room starts him" % [f, str(spawn), str(at)])
			for c in _cells_under(player.position, InteriorWalls.BODY_CLEARANCE):
				assert_false(solid.has(c), "%s: spawn '%s' leaves the player's body touching the solid cell %s" % [f, str(spawn), str(c)])
		for r in InteriorWalls.door_rects(room):
			var at_door := false
			for c in reach:
				if (r as Rect2).intersects(Rect2(Vector2(c) * T, Vector2(T, T)).grow(-2.0)):
					at_door = true
					break
			assert_true(at_door, "%s: the walker can stand in the door's trigger %s" % [f, str(r)])
		assert_gt(InteriorWalls.door_rects(room).size(), 0, "%s: CONTROL: the room has a door to judge" % f)
		for n in room.npcs.get_children():
			if n is Node2D and bool(n.get("interactable") if "interactable" in n else true):
				assert_true(_touches(reach, _cell((n as Node2D).position)), "%s: %s at %s can be walked up to" % [f, str(n.get("npc_name") if "npc_name" in n else n.name), str(_cell((n as Node2D).position))])
		for a in room.get_tree().get_nodes_in_group("interactables"):
			if a is Node2D and room.is_ancestor_of(a):
				assert_true(_touches(reach, _cell(room.to_local((a as Node2D).global_position))), "%s: %s can be walked up to" % [f, a.name])
		room.free()
		await get_tree().process_frame


func test_the_inn_stops_a_body_at_all_four_walls() -> void:
	var room: Node = await _open("InnInterior.gd")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var player: CharacterBody2D = room.player
	for push in [Vector2(0, -3000), Vector2(0, 3000), Vector2(-3000, 0), Vector2(3000, 0)]:
		assert_true(player.test_move(player.global_transform, push), "a body pushed %s from the inn's door meets a wall" % str(push))
	room.get_node(InteriorWalls.BODY_NAME).free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_false(player.test_move(player.global_transform, Vector2(-3000, 0)), "CONTROL: with the wall body gone the same push meets nothing, as it did before")
	room.free()
	await get_tree().process_frame


func test_every_room_script_builds_its_walls_and_a_village_does_not() -> void:
	for path in [DIR + "/BaseInterior.gd", DIR + "/InnInterior.gd", DIR + "/ShopInterior.gd", DIR + "/TavernInterior.gd"]:
		var src := FileAccess.get_file_as_string(path)
		var walls := src.find("InteriorWalls.build(")
		assert_gt(walls, src.find("_setup_transitions()"), "%s builds its walls after its doors exist (a door's trigger opens its cell)" % path.get_file())
		assert_gt(walls, src.find("_setup_player()"), "%s builds them after the player stands in the room" % path.get_file())
	assert_eq(FileAccess.get_file_as_string("res://src/maps/villages/BaseVillage.gd").find("InteriorWalls"), -1, "CONTROL: a village keeps its own tile collision and never builds these")


class CornerRoom:
	extends Node2D
	var spawn_points := {"desk": Vector2(2, 2)}


func test_a_spawn_on_a_cell_corner_opens_the_furniture_it_touches() -> void:
	var layout := ["WWWWW", "WTT.W", "W...W", "WWWWW"]
	var room := CornerRoom.new()
	add_child_autofree(room)
	var solid: Dictionary = InteriorWalls.build(room, layout, "T").get_meta("solid_cells")
	assert_false(solid.has(Vector2i(1, 1)) or solid.has(Vector2i(2, 1)), "the two table cells the standing body reaches into are open")
	assert_true(solid.has(Vector2i(0, 1)) and solid.has(Vector2i(2, 0)), "the walls a cell away are not")
	room.spawn_points = {"desk": Vector2(3.5, 2.5)}
	room.get_node(InteriorWalls.BODY_NAME).free()
	var plain: Dictionary = InteriorWalls.build(room, layout, "T").get_meta("solid_cells")
	assert_true(plain.has(Vector2i(1, 1)) and plain.has(Vector2i(2, 1)), "CONTROL: with the spawn in the middle of a floor cell the table is whole")
