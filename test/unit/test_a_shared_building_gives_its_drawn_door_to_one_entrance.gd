extends GutTest

const MapScripts := preload("res://test/unit/helpers/map_scripts.gd")

## struktured's .808 log, once per Harmonia entry: "[VILLAGE] block [P: (30, 5), S: (6, 3)] has 2 entrances; none moved under its drawn door".
## The Harmonia Arms facade draws ONE shop door and held two entrances, the smithy at its right edge and the attic door one cell left of the
## drawn door, so neither stood under it: his 2026-11-01 report ("right on the door and not allowed to enter") was still true of this building.

const VILLAGE_DIR := "res://src/maps/villages"
const HARMONIA := "res://src/maps/villages/HarmoniaVillage.gd"
const ARMS_CELL := Vector2i(30, 5)

var _vps: Array = []


func after_each() -> void:
	for vp in _vps:
		if is_instance_valid(vp):
			vp.free()
	_vps.clear()


func _build(path: String) -> Node:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	vp.world_2d = World2D.new()
	add_child(vp)
	_vps.append(vp)
	var v: Node = load(path).new()
	vp.add_child(v)
	return v


func _named(v: Node, node_name: String) -> Node2D:
	return v.buildings.get_node_or_null(node_name) as Node2D


func _smithy(v: Node) -> Node2D:
	for b in v.buildings.get_children():
		if b is VillageShop and b.shop_type == VillageShop.ShopType.BLACKSMITH:
			return b
	return null


## Where the facade draws its door, from the manifest's own rect: the art is as wide as its block, so image x is block x.
func _drawn_door_span() -> Vector2:
	var art: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json")) as Dictionary)["building_art"][HarmoniaVillageScene.BUILDING_ART[ARMS_CELL]]
	var r: Array = art["door"]["rect"]
	var left: float = ARMS_CELL.x * 32.0 + float(r[0])
	return Vector2(left, left + float(r[2]))


## The world x-span an entrance answers on, from its own collision box.
func _zone(n: Node2D) -> Vector2:
	for c in n.get_children():
		if c is CollisionShape2D and c.shape is RectangleShape2D:
			var half: float = (c.shape as RectangleShape2D).size.x / 2.0
			return Vector2(n.global_position.x + c.position.x - half, n.global_position.x + c.position.x + half)
	return Vector2.ZERO


func test_no_village_leaves_a_drawn_door_without_its_entrance() -> void:
	var built: int = 0
	for path in MapScripts.maps_in(VILLAGE_DIR):
		var v := _build(path)
		await get_tree().process_frame
		assert_eq(v.blocks_left_unaligned.size(), 0, "%s: %s drew a door that no single entrance took" % [path.get_file(), str(v.blocks_left_unaligned)])
		built += 1
	assert_gt(built, 8, "CONTROL: villages were built (%d)" % built)


## The whole answer-zone of an entrance, from its own collision box.
func _box(n: Node2D) -> Rect2:
	for c in n.get_children():
		if c is CollisionShape2D and c.shape is RectangleShape2D:
			var size: Vector2 = (c.shape as RectangleShape2D).size
			return Rect2(n.global_position + c.position - size / 2.0, size)
	return Rect2()


## Standing an entrance under a drawn door must not park it on a neighbour: every move in every village, printed and judged.
func test_no_entrance_is_moved_onto_another() -> void:
	var moves: int = 0
	var shared: int = 0
	for path in MapScripts.maps_in(VILLAGE_DIR):
		var v := _build(path)
		await get_tree().process_frame
		for m in v.entrance_moves:
			var moved: Node2D = m["moved"]
			moves += 1
			if not (m["others"] as Array).is_empty():
				shared += 1
				gut.p("  %s block %s: %s moved x %.0f -> %.0f beside %d other entrance(s)" % [path.get_file(), str(m["block"]), moved.name, float(m["from_x"]), float(m["to_x"]), (m["others"] as Array).size()])
			for o in m["others"]:
				assert_false(_box(moved).intersects(_box(o)), "%s block %s: %s now answers on %s, over %s at %s" % [path.get_file(), str(m["block"]), moved.name, str(_box(moved)), (o as Node).name, str(_box(o))])
	assert_gt(moves, 10, "CONTROL: entrances were stood under drawn doors (%d)" % moves)
	assert_gt(shared, 3, "CONTROL: some of them share their building (%d)" % shared)
	assert_true(Rect2(0, 0, 64, 64).intersects(Rect2(32, 32, 64, 64)), "CONTROL: two overlapping zones read as overlapping")


func test_the_arms_shop_door_opens_the_smithy() -> void:
	var v := _build(HARMONIA)
	await get_tree().process_frame
	var smithy := _smithy(v)
	var door := _drawn_door_span()
	assert_not_null(smithy, "CONTROL: Harmonia has a blacksmith")
	assert_gt(door.y - door.x, 8.0, "CONTROL: the Arms facade draws a door (%s)" % str(door))
	if smithy == null:
		return
	var zone := _zone(smithy)
	assert_gt(zone.y - zone.x, 0.0, "CONTROL: the smithy has an entrance zone")
	assert_true(zone.x <= door.x and zone.y >= door.y, "the smithy answers on %s, the drawn door spans %s: a player on the door is not on the shop" % [str(zone), str(door)])
	assert_almost_eq(smithy.global_position.x, (door.x + door.y) / 2.0, 1.0, "the smithy stands centred under its drawn door")
	## The shipped layout, for the record of what was wrong: smithy at x 36 cells, attic door at 32 cells with a 2-cell-wide zone.
	assert_false(36.0 * 32.0 - 32.0 <= door.x, "CONTROL: at its shipped x the smithy's zone began right of the drawn door")
	assert_lt(32.0 * 32.0 + 32.0, door.y, "CONTROL: at its shipped x the attic door's zone ended before the drawn door's right edge")


func test_the_attic_door_is_clear_of_the_shop_door() -> void:
	var v := _build(HARMONIA)
	await get_tree().process_frame
	var smithy := _smithy(v)
	var attic := _named(v, "CartographerDoor")
	assert_not_null(attic, "CONTROL: Harmonia still has the attic door")
	if smithy == null or attic == null:
		return
	var a := _zone(attic)
	var s := _zone(smithy)
	assert_gt(a.y - a.x, 0.0, "CONTROL: the attic door has a zone")
	assert_true(a.y + 16.0 <= s.x or s.y + 16.0 <= a.x, "the attic zone %s and the smithy zone %s leave no room to stand between them" % [str(a), str(s)])
	var block_left: float = ARMS_CELL.x * 32.0
	assert_true(attic.global_position.x >= block_left - 1.0 and attic.global_position.x <= block_left + 6 * 32.0, "the attic door is still on the Arms' own facade (x %.0f)" % attic.global_position.x)


func test_leaving_the_attic_lands_beside_its_door_not_on_a_trigger() -> void:
	var v := _build(HARMONIA)
	await get_tree().process_frame
	var smithy := _smithy(v)
	var attic := _named(v, "CartographerDoor")
	assert_true(v.spawn_points.has("cartographer_exit"), "CONTROL: the attic's return spawn exists")
	if smithy == null or attic == null or not v.spawn_points.has("cartographer_exit"):
		return
	var at: Vector2 = v.spawn_points["cartographer_exit"]
	assert_true(v._is_cell_walkable(Vector2i(int(at.x / 32.0), int(at.y / 32.0))), "the return spawn %s stands on walkable ground" % str(at))
	for pair in [["attic", _zone(attic)], ["smithy", _zone(smithy)]]:
		var z: Vector2 = pair[1]
		assert_false(at.x > z.x and at.x < z.y, "the return spawn x %.0f is inside the %s zone %s" % [at.x, pair[0], str(z)])
	assert_lt(absf(at.x - attic.global_position.x), 3 * 32.0, "and it is within three cells of the attic door it came out of")
