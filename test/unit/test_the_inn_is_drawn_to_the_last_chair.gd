extends GutTest

## struktured 2026-11-12: "the inside of the inn is still pretty basic or crude". Harmonia's inn is the reference room:
## every piece of furniture comes through the InteriorArt seam (sprites' thirteen hand-pixelled pieces), sorts by its
## feet, casts a contact shadow, and the room's own painters still stand everything where no art exists.

const Inn := preload("res://src/maps/interiors/InnInterior.gd")
const ART := "res://assets/sprites/interiors/harmonia/%s_inn.png"
## kind -> how many stand in the room.
const PIECES := {"desk": 1, "barrel": 1, "crate": 1, "armchair": 2, "bench": 2, "table": 1, "table_things": 1,
	"round_table": 1, "stool": 2, "coat_rack": 1, "gear_pile": 1, "rug": 1, "door_mat": 1}
## Flat or laid-on pieces: nothing casts a shadow from them.
const NO_SHADOW := ["rug", "door_mat", "bench", "table_things"]
const UNDERFOOT := ["rug", "door_mat"]
const T := 32

var _flicker := true


func before_each() -> void:
	_flicker = InteriorLighting.flicker_enabled
	InteriorLighting.flicker_enabled = false
	InteriorPlacementSweep.relocations = 0


func after_each() -> void:
	VillageProp.prop_art_override = null
	InteriorLighting.flicker_enabled = _flicker


func _all_drawn() -> Dictionary:
	var o := {}
	for kind in PIECES:
		o[kind + "_inn"] = {"path": ART % kind}
	o["back_wall_inn"] = {"path": ART % "back_wall"}
	return o


func _inn(art: Dictionary) -> Node:
	VillageProp.prop_art_override = art
	var inn: Node = Inn.new()
	add_child_autofree(inn)
	await get_tree().process_frame
	return inn


func _art(inn: Node, kind: String) -> Array:
	var out: Array = []
	for n in inn.find_children("Art_" + kind + "*", "Sprite2D", true, false):
		# "Art_table" must not answer for "Art_table_things".
		var rest := str(n.name).trim_prefix("Art_" + kind)
		if rest == "" or rest.is_valid_int():
			out.append(n)
	return out


func _under(node: Node, ancestor: Node) -> bool:
	var p := node.get_parent()
	while p != null:
		if p == ancestor:
			return true
		p = p.get_parent()
	return false


## True when the player's body (radius + safe margin, 8 px) standing in the middle of `cell` touches no collider.
func _body_fits(inn: Node, cell: Vector2i) -> bool:
	var q := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 8.0
	q.shape = shape
	q.collision_mask = 1
	q.transform = Transform2D(0.0, (inn as Node2D).to_global((Vector2(cell) + Vector2(0.5, 0.5)) * T))
	return (inn as Node2D).get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty()


func test_the_art_this_file_names_is_on_disk() -> void:
	for kind in PIECES:
		assert_true(FileAccess.file_exists(ART % kind), "%s is on disk, or every arm below paints instead of drawing" % (ART % kind))


func test_every_piece_stands_drawn_and_the_painters_stand_down() -> void:
	var inn: Node = await _inn(_all_drawn())
	for kind in PIECES:
		assert_eq(_art(inn, kind).size(), int(PIECES[kind]), "%s: drawn pieces in the room" % kind)
	assert_null(inn.decorations.get_node_or_null("RegistrationDesk"), "the painted desk does not stand beside the drawn one")
	assert_null(inn.decorations.get_node_or_null("CommunalTable"), "nor the painted table")
	var chairs := _art(inn, "armchair")
	if chairs.size() == 2:
		assert_ne((chairs[0] as Sprite2D).flip_h, (chairs[1] as Sprite2D).flip_h, "the two chairs face each other across the fire: one is the flip")


func test_with_no_art_the_room_is_painted_exactly_as_before() -> void:
	var inn: Node = await _inn({})
	assert_eq(inn.find_children("Art_*", "Sprite2D", true, false).size(), 0, "CONTROL: nothing is drawn when the seam has no art")
	assert_not_null(inn.decorations.get_node_or_null("RegistrationDesk"), "the painted desk stands")
	assert_not_null(inn.decorations.get_node_or_null("CommunalTable"), "and the painted table")
	assert_eq(inn.tilemap.get_cell_source_id(Vector2i(5, 7)), 3, "and the carpet runner is laid beside it")
	var drawn: Node = await _inn(_all_drawn())
	assert_eq(drawn.tilemap.get_cell_source_id(Vector2i(5, 7)), 0, "where the hearth rug is drawn, the runner's cells are plain floor")


func test_a_piece_sorts_by_its_feet_and_casts_one_shadow() -> void:
	var inn: Node = await _inn(_all_drawn())
	assert_true(inn.y_sort_enabled and inn.decorations.y_sort_enabled and inn.npcs.y_sort_enabled, "the room, its furniture and its people sort together by y")
	var standing := 0
	var shadowed := 0
	for kind in PIECES:
		if UNDERFOOT.has(kind):
			continue
		for a in _art(inn, kind):
			var spr := a as Sprite2D
			standing += 1
			assert_almost_eq(spr.position.y + spr.texture.get_height(), 0.0, 0.01, "%s: its holder sits at its feet, so it sorts by them" % kind)
			if not NO_SHADOW.has(kind):
				shadowed += 1
	assert_gt(standing, 8, "CONTROL: the room has standing pieces to judge (%d)" % standing)
	assert_eq(inn._floor_pieces.find_children("Shadow*", "Sprite2D", true, false).size(), shadowed, "one contact shadow per standing piece, on the floor layer")


func test_what_lies_underfoot_can_be_walked_on_and_the_lane_is_clear() -> void:
	var inn: Node = await _inn(_all_drawn())
	for kind in UNDERFOOT:
		for a in _art(inn, kind):
			assert_true(_under(a, inn._floor_pieces), "%s lies on the floor layer" % kind)
			assert_false(_under(a, inn.decorations), "%s is not furniture" % kind)
	# Judged as the PLAYER meets it (a body against the room's colliders); the NPC sweep's rule also counts wall paintings.
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(_body_fits(inn, Vector2i(12, 6)), "the middle of the hearth rug is walkable")
	assert_true(_body_fits(inn, Vector2i(10, 12)), "and the door mat")
	assert_false(_body_fits(inn, Vector2i(5, 9)), "CONTROL: the long table is not")
	assert_false(_body_fits(inn, Vector2i(0, 4)), "CONTROL: nor a wall cell")
	for x in range(1, 19):
		assert_true(_body_fits(inn, Vector2i(x, 4)), "row 4 is the walk from the desk past the hearth to the stairs: cell (%d, 4) is clear" % x)
	assert_eq(InteriorPlacementSweep.relocations, 0, "no guest had to be moved off the new furniture")
	assert_gt(inn.decorations.find_children("*", "StaticBody2D", true, false).size(), 6, "the standing pieces are solid to the player")


func test_the_drawn_room_is_lit_from_its_wall_its_hearth_and_its_candle() -> void:
	var inn: Node = await _inn(_all_drawn())
	var lights := inn.find_children("*", "PointLight2D", true, false)
	assert_eq(inn.lighting.lamp_count(), lights.size(), "every light answers to the rig (%d lights)" % lights.size())
	assert_not_null(inn.decorations.get_node_or_null("CandleLight"), "the laid table's candle is lit")
	var at_the_wall := 0
	for l in lights:
		if absf((l as PointLight2D).position.y - 1.75 * T) < 0.5:
			at_the_wall += 1
	assert_eq(at_the_wall, Inn.WALL_LANTERN_X.size(), "the room's lanterns hang under the wall's drawn ones")
	var bare: Node = await _inn({})
	assert_null(bare.decorations.get_node_or_null("CandleLight"), "CONTROL: a painted table has no candle to light")
