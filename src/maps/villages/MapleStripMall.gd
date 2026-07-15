extends BaseVillage
class_name MapleStripMall

## MapleStripMall — the rearranging strip mall on the edge of Maple Heights
## (world2_configuration_pending's stage; Madame Orrery's W2 booth for
## fine_print / wrong_blue). Three storefronts, one GAP where the frozen-
## yogurt shop stood yesterday, a parking lot with regulation stalls, and a
## fortune-teller's booth the mall's paperwork has never once acknowledged.

const MAP_WIDTH: int = 30
const MAP_HEIGHT: int = 20


func _get_area_id() -> String:
	return "maple_heights_strip_mall"


func _get_music_area_id() -> String:
	return "village"


func _get_village_display_name() -> String:
	return "Birchwood Commons"


func _get_map_pixel_size() -> Vector2i:
	return Vector2i(MAP_WIDTH * TILE_SIZE, MAP_HEIGHT * TILE_SIZE)


func _get_save_point_position() -> Vector2:
	return Vector2(6 * TILE_SIZE,14 * TILE_SIZE)


func _get_player_spawn_fallback() -> Vector2:
	return Vector2(15 * TILE_SIZE,15 * TILE_SIZE)


func _generate_map() -> void:
	# S = storefront wall (impassable), Y = the yogurt-shop GAP (walkable slab —
	# the shop is just... elsewhere today), O = Orrery's booth structure,
	# p = sidewalk, k = parking lot, d = worn dirt, X = exit road (south).
	# Every row exactly MAP_WIDTH (24) chars.
	var map_data: Array[String] = [
		"WWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
		"W............................W",
		"W............................W",
		"W...pppppppppppppppppppppp...W",
		"W...pSSSSSpSSSSSpYYYYYpppp...W",
		"W...pSSSSSpSSSSSpYYYYYpOOp...W",
		"W...pSSSSSpSSSSSpYYYYYpOOp...W",
		"W...pppppppppppppppppppppp...W",
		"W...pppppppppppppppppppppp...W",
		"W...kkkkkkkkkkkkkkkkkkkkkk...W",
		"W...kkkkkkkkkkkkkkkkkkkkkk...W",
		"W...kkkkkkkkkkkkkkkkkkkkkk...W",
		"W...kkkkkkkkkkkkkkkkkkkkkk...W",
		"W...pppppppppppppppppppppp...W",
		"W...pppppppppppppppppppppp...W",
		"W...pppppppppppppppppppppp...W",
		"W...pppppppppXXXXppppppppp...W",
		"W............................W",
		"W............................W",
		"WWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
	]
	for y in range(MAP_HEIGHT):
		var row: String = map_data[y] if y < map_data.size() else ""
		for x in range(MAP_WIDTH):
			var ch: String = row[x] if x < row.length() else "W"
			var tile_type := _char_to_tile_type(ch)
			var atlas := _get_atlas_coords(tile_type)
			tile_map.set_cell(Vector2i(x, y), 0, atlas)
			if ch == "X" and not spawn_points.has("exit"):
				spawn_points["exit"] = Vector2(x * TILE_SIZE + TILE_SIZE / 2, y * TILE_SIZE + TILE_SIZE / 2)

	spawn_points["entrance"] = Vector2(15 * TILE_SIZE,15 * TILE_SIZE)
	spawn_points["default"] = spawn_points["entrance"]


func _char_to_tile_type(ch: String) -> int:
	match ch:
		"W": return TileGeneratorScript.TileType.WALL
		"S", "O": return TileGeneratorScript.TileType.WALL  # storefronts / booth
		"Y": return TileGeneratorScript.TileType.VILLAGE_DIRT  # the gap — bare slab
		"p": return TileGeneratorScript.TileType.VILLAGE_PATH
		"k": return TileGeneratorScript.TileType.VILLAGE_DIRT  # parking lot
		"X": return TileGeneratorScript.TileType.VILLAGE_PATH
		_: return TileGeneratorScript.TileType.VILLAGE_PATH


func _get_atlas_coords(tile_type: int) -> Vector2i:
	var tile_id: int = TileGeneratorScript.get_tile_id(tile_type)
	return Vector2i(tile_id % 5, tile_id / 5)


func _setup_transitions() -> void:
	var exit_trans = AreaTransitionScript.new()
	exit_trans.name = "Exit"
	exit_trans.target_map = "maple_heights_village"
	exit_trans.target_spawn = "strip_mall_return"
	exit_trans.require_interaction = false
	exit_trans.position = spawn_points.get("exit", Vector2(15 * TILE_SIZE,16 * TILE_SIZE))
	_setup_transition_collision(exit_trans, Vector2(TILE_SIZE * 4, TILE_SIZE))
	exit_trans.transition_triggered.connect(_on_transition_triggered)
	transitions.add_child(exit_trans)


func _setup_buildings() -> void:
	_paint_storefront_signs()


## Painted store signage + parking stripes + the gap's outline — flat sprites.
func _paint_storefront_signs() -> void:
	var canvas := Sprite2D.new()
	canvas.name = "MallDressing"
	var img := Image.create(MAP_WIDTH * TILE_SIZE, MAP_HEIGHT * TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	var stripe := Color(0.85, 0.82, 0.35, 0.85)
	# Parking stall stripes (rows 7-10): verticals every 3 tiles
	for sx in range(3, 21, 3):
		for y in range(7 * TILE_SIZE + 4, 11 * TILE_SIZE - 4):
			img.set_pixel(sx * TILE_SIZE, y, stripe)
	# The yogurt gap: a dashed outline where the shop USED to be
	var ghost := Color(0.55, 0.6, 0.68, 0.6)
	for x in range(14 * TILE_SIZE, 19 * TILE_SIZE):
		if (x / 6) % 2 == 0:
			img.set_pixel(x, 2 * TILE_SIZE, ghost)
			img.set_pixel(x, 5 * TILE_SIZE - 1, ghost)
	for y in range(2 * TILE_SIZE, 5 * TILE_SIZE):
		if (y / 6) % 2 == 0:
			img.set_pixel(14 * TILE_SIZE, y, ghost)
			img.set_pixel(19 * TILE_SIZE - 1, y, ghost)
	canvas.texture = ImageTexture.create_from_image(img)
	canvas.centered = false
	canvas.position = Vector2.ZERO
	buildings.add_child(canvas)


func _setup_npcs() -> void:
	# Surplus teen — configuration_pending giver, outside the surplus store.
	var teen = _create_npc("Surplus Teen", "villager", Vector2(7 * TILE_SIZE,8 * TILE_SIZE), [
		"The mall rearranged again last night. Third time this month.",
		"I keep a log. Nobody asked me to. Somebody should.",
	])
	teen.npc_id = "surplus_teen_w2"
	npcs.add_child(teen)

	# The three owners (talk-tally: owners_interviewed).
	var candle = _create_npc("Candle Shop Owner", "shopkeeper", Vector2(13 * TILE_SIZE,8 * TILE_SIZE), [
		"My shop faced EAST yesterday. East! Do you know what morning light does to inventory?",
		"Forty years of retail and I have never ONCE been consulted about the layout.",
	])
	candle.npc_id = "candle_shop_owner_w2"
	npcs.add_child(candle)

	var armory = _create_npc("Armory Owner", "shopkeeper", Vector2(15 * TILE_SIZE,8 * TILE_SIZE), [
		"The mall moves. The stock stays sorted. I've made my peace.",
		"A sword doesn't care which wall it hangs on. There's a lesson in that.",
	])
	armory.npc_id = "armory_owner_w2"
	npcs.add_child(armory)

	var yogurt = _create_npc("Yogurt Shop Owner", "villager", Vector2(19 * TILE_SIZE,11 * TILE_SIZE), [
		"This is where my shop was. I'm standing in the freezer section. Roughly.",
		"It'll come back. It always comes back. Just not where I left it.",
	])
	yogurt.npc_id = "yogurt_owner_w2"
	npcs.add_child(yogurt)

	# Madame Orrery's W2 booth — the mall's paperwork has never logged it.
	var orrery = _create_npc("Madame Orrery", "mysterious", Vector2(23 * TILE_SIZE + TILE_SIZE / 2,7 * TILE_SIZE), [
		"Your energy profile is familiar. The cards remember you even here.",
		"The mall rearranges. My booth does not. Draw your own conclusions.",
	])
	orrery.npc_id = "madame_orrery_w2"
	npcs.add_child(orrery)