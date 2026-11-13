extends GutTest

## The inn was the reference room; Harmonia's item shop and blacksmith follow it through the same seam: sprites' drawn
## pieces stand on their feet with a shadow and a footprint, the mats lie underfoot, and a shop with no art for a
## piece paints exactly what it painted before (every other village's shop).

const Shop := preload("res://src/maps/interiors/ShopInterior.gd")
const ART := "res://assets/sprites/interiors/harmonia/%s_%s.png"
const ROOMS := {0: "shop_item", 3: "shop_blacksmith"}
## room -> kind -> does it block the player.
const STANDING := {
	"shop_item": {"barrels": true, "sacks": true, "crate_produce": true},
	"shop_blacksmith": {"forge": true, "coal_bin": true, "quench_barrel": true, "anvil": true, "weapon_crates": true, "bellows": false},
}
const UNDERFOOT := {"shop_item": ["mat", "door_mat"], "shop_blacksmith": ["door_mat"]}
const T := 32


func before_each() -> void:
	InteriorPlacementSweep.relocations = 0


func after_each() -> void:
	VillageProp.prop_art_override = null


func _all_drawn(room: String) -> Dictionary:
	var o := {}
	for kind in (STANDING[room] as Dictionary).keys() + (UNDERFOOT[room] as Array) + ["back_wall"]:
		o["%s_%s" % [kind, room]] = {"path": ART % [kind, room]}
	return o


func _shop(type: int, art: Dictionary) -> Node:
	VillageProp.prop_art_override = art
	var shop: Node = Shop.new()
	shop.shop_type = type
	add_child_autofree(shop)
	await get_tree().process_frame
	return shop


func _art(shop: Node, kind: String) -> Sprite2D:
	for n in shop.find_children("Art_" + kind + "*", "Sprite2D", true, false):
		var rest := str(n.name).trim_prefix("Art_" + kind)
		if rest == "" or rest.is_valid_int():
			return n as Sprite2D
	return null


func _feet(spr: Sprite2D, shop: Node) -> Vector2:
	var at := shop.to_local(spr.global_position) as Vector2
	return at + Vector2(spr.texture.get_width() / 2.0, spr.texture.get_height())


func test_the_art_this_file_names_is_on_disk() -> void:
	for room in STANDING:
		for key in _all_drawn(room):
			assert_true(FileAccess.file_exists(str(_all_drawn(room)[key]["path"])), "%s is on disk, or every arm below paints instead of drawing" % key)


func test_every_piece_stands_on_open_floor_with_a_shadow_and_a_footprint() -> void:
	for type in ROOMS:
		var room: String = ROOMS[type]
		var shop: Node = await _shop(type, _all_drawn(room))
		var solid: Dictionary = shop.get_node(InteriorWalls.BODY_NAME).get_meta("solid_cells")
		for kind in STANDING[room]:
			var spr := _art(shop, kind)
			assert_not_null(spr, "%s: the drawn %s stands in the room" % [room, kind])
			if spr == null:
				continue
			var feet := _feet(spr, shop)
			var cell := Vector2i(int(floor(feet.x / T)), int(floor((feet.y - 1.0) / T)))
			assert_false(solid.has(cell), "%s: %s's feet %s are on open floor, not in a wall, shelf or counter cell" % [room, kind, str(feet)])
			assert_true(Rect2(T, 0, (shop.MAP_WIDTH - 2) * T, (shop.MAP_HEIGHT - 1) * T).encloses(Rect2(shop.to_local(spr.global_position), spr.texture.get_size())), "%s: %s is drawn inside the side and south walls (a piece may rise against the north one)" % [room, kind])
			var body := spr.get_parent().get_node_or_null("Footprint")
			assert_eq(body != null, bool(STANDING[room][kind]), "%s: %s %s" % [room, kind, "blocks the player at its feet" if STANDING[room][kind] else "blocks nobody"])
		var shadows := 0
		for n in shop._floor_pieces.get_children():
			if str(n.name).begins_with(InteriorPiece.SHADOW_NAME):
				shadows += 1
		assert_eq(shadows, (STANDING[room] as Dictionary).size(), "%s: one contact shadow per standing piece, on the floor layer" % room)
		for kind in UNDERFOOT[room]:
			var flat := _art(shop, kind)
			assert_not_null(flat, "%s: the %s is laid" % [room, kind])
			if flat != null:
				assert_eq(flat.get_parent(), shop._floor_pieces, "%s: the %s lies on the floor layer, under everyone" % [room, kind])
		assert_true(shop.y_sort_enabled and shop.decorations.y_sort_enabled and shop.npcs.y_sort_enabled, "%s: with pieces standing, the room sorts by feet" % room)
		shop.free()
		await get_tree().process_frame


func test_nobody_stands_in_a_piece_and_the_way_in_is_clear() -> void:
	for type in ROOMS:
		var room: String = ROOMS[type]
		var shop: Node = await _shop(type, _all_drawn(room))
		var blocked: Array = []
		for kind in STANDING[room]:
			var spr := _art(shop, kind)
			if spr == null or not bool(STANDING[room][kind]):
				continue
			var shape := spr.get_parent().get_node("Footprint").get_child(0) as CollisionShape2D
			var size: Vector2 = (shape.shape as RectangleShape2D).size
			blocked.append([kind, Rect2(shop.to_local(shape.global_position) - size / 2.0, size)])
		assert_gt(blocked.size(), 2, "%s: CONTROL: there are footprints to judge (%d)" % [room, blocked.size()])
		var stand_points: Array = []
		for n in shop.npcs.get_children():
			if n is Node2D:
				stand_points.append([str(n.get("npc_name")), (n as Node2D).position])
		for spawn in shop.spawn_points:
			stand_points.append(["spawn " + str(spawn), (shop.spawn_points[spawn] as Vector2) * T])
		assert_gt(stand_points.size(), 3, "%s: CONTROL: NPCs and spawns were found (%d)" % [room, stand_points.size()])
		assert_eq(InteriorPlacementSweep.relocations, 0, "%s: nobody had to be moved off the new pieces (the first run moved Sir Corvath off the weapon crates)" % room)
		for sp in stand_points:
			for b in blocked:
				assert_false((b[1] as Rect2).grow(10.0).has_point(sp[1]), "%s: %s at %s stands clear of the %s's footprint %s" % [room, sp[0], str(sp[1]), b[0], str(b[1])])
		# From the door a body can still walk to the counter: the open cells left of or right of each footprint row.
		var door := (shop.spawn_points["entrance"] as Vector2) * T
		for b in blocked:
			assert_false((b[1] as Rect2).grow(8.0).has_point(door), "%s: the %s does not sit on the doorway" % [room, b[0]])
		shop.free()
		await get_tree().process_frame


func test_a_shop_with_no_art_paints_what_it_always_did() -> void:
	for type in ROOMS:
		var shop: Node = await _shop(type, {})
		assert_eq(shop.find_children("Art_*", "Sprite2D", true, false).size(), 0, "%s: CONTROL: nothing is drawn when no art is named" % ROOMS[type])
		assert_eq(shop.find_children("Piece_*", "Node2D", true, false).size(), 0, "no empty holder is left behind")
		assert_eq(shop._floor_pieces.get_child_count(), 0, "no shadow or mat without a drawn piece")
		assert_false(shop.y_sort_enabled, "a painted shop keeps its old draw order")
		if type == 0:
			assert_not_null(shop.decorations.get_node_or_null("BarrelCluster"), "the item shop's painted barrels stand")
		else:
			assert_not_null(shop.decorations.get_node_or_null("Anvil"), "the blacksmith's painted anvil stands")
			assert_not_null(shop.decorations.get_node_or_null("WeaponCrates"), "and its painted crates")
		shop.free()
		await get_tree().process_frame


## main 24577, from the first stills: the drawn back wall was sorted under the wall tiles, a plank hung across it,
## and the blacksmith's stone forge stood ON the painted one in front of the counter.
func test_the_back_wall_is_the_rooms_north_face_and_there_is_one_forge() -> void:
	for type in ROOMS:
		var room: String = ROOMS[type]
		var shop: Node = await _shop(type, _all_drawn(room))
		var wall := _art(shop, "back_wall")
		assert_not_null(wall, "%s: the back wall stands" % room)
		if wall != null:
			assert_eq(wall.get_parent(), shop._floor_pieces, "%s: on the floor layer, which draws after the wall tiles and is not sorted by y" % room)
			assert_lt(wall.position.y, 0.0, "%s: CONTROL: the strip's origin is above the map, which is what a y-sort buried" % room)
		assert_eq(shop.camera.limit_top, -T, "%s: the camera can show the part of the wall above the map" % room)
		var planks := 0
		for n in shop.decorations.get_children():
			if n is Label and str((n as Label).text) == str(shop.shop_name):
				planks += 1
		assert_eq(planks, 0, "%s: no plank naming the shop hangs across its drawn wall" % room)
		shop.free()
		await get_tree().process_frame
	var smith: Node = await _shop(3, _all_drawn("shop_blacksmith"))
	var frame: Image = (smith._forge_frames[0] as ImageTexture).get_image()
	assert_eq(frame.get_pixel(2, 60).a, 0.0, "with the stone body drawn, the painted forge's own stonework is not painted under it")
	assert_gt(frame.get_pixel(20, 44).a, 0.5, "CONTROL: its embers still are")
	var body := _art(smith, "forge")
	assert_almost_eq(smith._forge_sprite.position.x, _feet(body, smith).x, 0.5, "the flames play in the drawn body, wherever it stands")
	assert_almost_eq(smith.decorations.get_node("ForgeLight").position.x, _feet(body, smith).x, 0.5, "and its light is there too")
	var door := (smith.spawn_points["entrance"] as Vector2) * T
	var counter := Vector2(8.5 * T, 5 * T)
	assert_false(Rect2(door.x - 24, counter.y, 48, door.y - counter.y).has_point(_feet(body, smith)), "the forge is not on the walk from the door to the counter")
	smith.free()
	await get_tree().process_frame
	var plain: Node = await _shop(3, {})
	assert_gt(((plain._forge_frames[0] as ImageTexture).get_image()).get_pixel(2, 60).a, 0.5, "CONTROL: a painted blacksmith still paints its whole forge")
	assert_eq(plain.camera.limit_top, 0, "CONTROL: and its camera stops at the map's edge")
	assert_eq(plain._forge_sprite.position, Vector2(8 * T, 6 * T), "where it always stood")
