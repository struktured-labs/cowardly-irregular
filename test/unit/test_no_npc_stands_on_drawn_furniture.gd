extends GutTest

## cowir-main 21502, read off cowir-sprites' .761 after-shots: Gethena stood on the item shop's left shelf, Sir Corvath on the
## smithy's armour table, Scholar Fen on the inn's south bench. InteriorPlacementSweep already existed and missed all three:
## the shelves became TILES (layout "S") when the shops were drawn, and the benches are 14 px tall, under the 24 px furniture
## floor. The sweep now takes a room's tile-furniture glyphs and any sprite marked furniture; the authored spots moved.

const ShopInteriorScript := preload("res://src/maps/interiors/ShopInterior.gd")
const InnInteriorScript := preload("res://src/maps/interiors/InnInterior.gd")


func _host_with_npc(at: Vector2) -> Dictionary:
	var host := Node2D.new()
	add_child_autofree(host)
	var npcs := Node2D.new()
	host.add_child(npcs)
	var npc := Node2D.new()
	npc.position = at
	npcs.add_child(npc)
	var decorations := Node2D.new()
	host.add_child(decorations)
	return {"host": host, "npcs": npcs, "npc": npc, "decorations": decorations}


func test_a_shelf_glyph_blocks_and_only_when_the_room_says_so() -> void:
	var layout := ["WWWWW", "W.S.W", "W...W", "WWWWW"]
	var on_shelf := Vector2(2.5 * 32, 1.5 * 32)
	var a := _host_with_npc(on_shelf)
	InteriorPlacementSweep.relocations = 0
	InteriorPlacementSweep.sweep(a["host"], a["npcs"], a["decorations"], layout, "planted")
	assert_eq(InteriorPlacementSweep.relocations, 0, "CONTROL: without the glyph a shelf cell reads as floor")
	var b := _host_with_npc(on_shelf)
	InteriorPlacementSweep.sweep(b["host"], b["npcs"], b["decorations"], layout, "planted", "S")
	assert_eq(InteriorPlacementSweep.relocations, 1, "an NPC on a shelf cell must be moved once the room names its shelves")
	assert_ne(Vector2i((b["npc"] as Node2D).position / 32.0), Vector2i(2, 1), "and it must leave the shelf")


func test_a_small_sprite_marked_furniture_blocks() -> void:
	var layout := ["WWWWW", "W...W", "W...W", "WWWWW"]
	var c := _host_with_npc(Vector2(2.5 * 32, 1.0 * 32))
	var bench := Sprite2D.new()
	bench.texture = ImageTexture.create_from_image(Image.create(64, 14, false, Image.FORMAT_RGBA8))
	bench.position = Vector2(2.5 * 32, 1.0 * 32 + 12)
	(c["decorations"] as Node).add_child(bench)
	InteriorPlacementSweep.relocations = 0
	InteriorPlacementSweep.sweep(c["host"], c["npcs"], c["decorations"], layout, "planted")
	assert_eq(InteriorPlacementSweep.relocations, 0, "CONTROL: a 14 px sprite is decor until it is marked")
	bench.set_meta("furniture", true)
	InteriorPlacementSweep.sweep(c["host"], c["npcs"], c["decorations"], layout, "planted")
	assert_eq(InteriorPlacementSweep.relocations, 1, "a bench marked furniture must move the NPC standing on it")


func test_no_shop_npc_stands_on_a_shelf() -> void:
	var offenders: Array = []
	var seen := 0
	for t in ShopInteriorScript.ShopType.values():
		var shop = ShopInteriorScript.new()
		shop.shop_type = t
		add_child_autofree(shop)
		await get_tree().process_frame
		for n in shop.npcs.get_children():
			seen += 1
			var foot: Vector2 = (n as Node2D).position + Vector2(0, 16)
			var cell := Vector2i(floori(foot.x / 32.0), floori(foot.y / 32.0))
			var row: String = ShopInteriorScript.SHOP_LAYOUT[cell.y]
			if ShopInteriorScript.SHELF_GLYPHS.contains(row[cell.x]):
				offenders.append("%s (type %d) at %s" % [n.name, t, cell])
	assert_gt(seen, 8, "FLOOR: every shop type must have spawned its NPCs (saw %d)" % seen)
	assert_eq(offenders, [], "an NPC's feet stand on a drawn shelf: %s" % [offenders])


func test_no_inn_npc_stands_on_a_bench() -> void:
	var inn = InnInteriorScript.new()
	add_child_autofree(inn)
	await get_tree().process_frame
	var benches: Array = []
	for s in inn.find_children("*", "Sprite2D", true, false):
		if bool(s.get_meta("furniture", false)):
			benches.append(s)
	assert_eq(benches.size(), 2, "FLOOR: the communal table's two benches must be marked furniture")
	var offenders: Array = []
	for n in inn.npcs.get_children():
		var foot := InteriorPlacementSweep._npc_footprint((n as Node2D).position)
		for b in benches:
			var sp := b as Sprite2D
			var size: Vector2 = sp.texture.get_size() * sp.scale
			var r := Rect2(sp.global_position - inn.global_position - size * 0.5, size)
			if r.intersects(foot):
				offenders.append(str(n.name))
	assert_eq(offenders, [], "an inn NPC stands on a bench: %s" % [offenders])
