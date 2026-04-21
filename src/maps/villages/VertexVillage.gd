extends BaseVillage
class_name VertexVillageScene

## VertexVillage - Minimalist refuge in the void, stark geometry, existential calm
## Features: The Rest (inn), The Exchange (item shop), sparse NPCs in intentional emptiness

const VillageInnScript = preload("res://src/exploration/VillageInn.gd")
const VillageShopScript = preload("res://src/exploration/VillageShop.gd")
const TreasureChestScript = preload("res://src/exploration/TreasureChest.gd")

## Map dimensions
const MAP_WIDTH: int = 18
const MAP_HEIGHT: int = 16


## ---- BaseVillage hooks ----

func _get_area_id() -> String:
	return "vertex_village"


func _get_village_display_name() -> String:
	return "The Vertex"


func _get_map_pixel_size() -> Vector2i:
	return Vector2i(MAP_WIDTH * TILE_SIZE, MAP_HEIGHT * TILE_SIZE)


func _get_save_point_position() -> Vector2:
	return Vector2(9 * TILE_SIZE, 6 * TILE_SIZE)


func _get_player_spawn_fallback() -> Vector2:
	return Vector2(288, 256)


func _generate_map() -> void:
	# The Vertex layout: sparse, intentional emptiness
	# W = perimeter wall, D = dark ground (void), . = floor (sparse island)
	# I = inn (The Rest), G = shop (The Exchange)
	# X = exit path
	# Emptiness is deliberate — the void is the point
	# Each row is exactly MAP_WIDTH (18) characters
	var map_data: Array[String] = [
		"WWWWWWWWWWWWWWWWWW",
		"WDDDDDDDDDDDDDDDDW",
		"WDDD..........DDDW",
		"WDDD.II....GG.DDDW",
		"WDDD.II....GG.DDDW",
		"WDDD..........DDDW",
		"WDDDDDDDDDDDDDDDDW",
		"WDDD..........DDDW",
		"WDDD..........DDDW",
		"WDDDDDDDDDDDDDDDDW",
		"WDDD..........DDDW",
		"WDDD..........DDDW",
		"WDDDDDDDDDDDDDDDDW",
		"WDD....XXXX....DDW",
		"WDD....XXXX....DDW",
		"WWWWWWWWWWWWWWWWWW",
	]

	for y in range(MAP_HEIGHT):
		var row = map_data[y] if y < map_data.size() else ""
		for x in range(MAP_WIDTH):
			var char = row[x] if x < row.length() else "W"
			var tile_type = _char_to_tile_type(char)
			var atlas_coords = _get_atlas_coords(tile_type)
			tile_map.set_cell(Vector2i(x, y), 0, atlas_coords)

			if char == "X" and not spawn_points.has("exit"):
				spawn_points["exit"] = Vector2(x * TILE_SIZE + TILE_SIZE / 2, y * TILE_SIZE + TILE_SIZE / 2)

	spawn_points["entrance"] = Vector2(9 * TILE_SIZE, 8 * TILE_SIZE)
	spawn_points["default"] = spawn_points["entrance"]
	spawn_points["vertex_entrance"] = spawn_points["entrance"]


func _char_to_tile_type(char: String) -> int:
	match char:
		"W": return TileGeneratorScript.TileType.WALL
		"D": return TileGeneratorScript.TileType.DARK_GROUND
		"X": return TileGeneratorScript.TileType.VILLAGE_PATH
		_: return TileGeneratorScript.TileType.FLOOR


func _get_atlas_coords(tile_type: int) -> Vector2i:
	var tile_id = TileGeneratorScript.get_tile_id(tile_type)
	return Vector2i(tile_id % 5, tile_id / 5)


func _setup_transitions() -> void:
	var exit_trans = AreaTransitionScript.new()
	exit_trans.name = "Exit"
	exit_trans.target_map = "abstract_overworld"
	exit_trans.target_spawn = "vertex_entrance"
	exit_trans.require_interaction = false
	exit_trans.position = spawn_points.get("exit", Vector2(288, 448))
	_setup_transition_collision(exit_trans, Vector2(TILE_SIZE * 5, TILE_SIZE))
	exit_trans.transition_triggered.connect(_on_transition_triggered)
	transitions.add_child(exit_trans)


func _setup_buildings() -> void:
	# === THE REST (Inn) ===
	var inn = VillageInnScript.new()
	inn.inn_name = "The Rest"
	inn.position = Vector2(4.5 * TILE_SIZE, 4 * TILE_SIZE)
	buildings.add_child(inn)

	# === THE EXCHANGE (Item Shop) ===
	var exchange = VillageShopScript.new()
	exchange.shop_name = "The Exchange"
	exchange.shop_type = VillageShopScript.ShopType.ITEM
	exchange.keeper_name = "The Keeper"
	exchange.position = Vector2(11.5 * TILE_SIZE, 4 * TILE_SIZE)
	buildings.add_child(exchange)

	# === THE RECALL (Magic) ===
	# Remembers a few spells that used to exist.
	var recall = VillageShopScript.new()
	recall.shop_name = "The Recall"
	recall.shop_type = VillageShopScript.ShopType.WHITE_MAGIC
	recall.keeper_name = "The Archivist"
	recall.position = Vector2(7.5 * TILE_SIZE, 4 * TILE_SIZE)
	buildings.add_child(recall)

	# === THE REMAINDER (Equipment) ===
	# Sells what wasn't optimized away.
	var remainder = VillageShopScript.new()
	remainder.shop_name = "The Remainder"
	remainder.shop_type = VillageShopScript.ShopType.BLACKSMITH
	remainder.keeper_name = "The Smith"
	remainder.position = Vector2(4.5 * TILE_SIZE, 10 * TILE_SIZE)
	buildings.add_child(remainder)


func _setup_treasures() -> void:
	# Something left behind — no explanation given
	var chest1 = TreasureChestScript.new()
	chest1.chest_id = "vertex_chest_1"
	chest1.contents_type = "item"
	chest1.contents_id = "elixir"
	chest1.contents_amount = 1
	chest1.position = Vector2(15 * TILE_SIZE, 2 * TILE_SIZE)
	treasures.add_child(chest1)


func _setup_npcs() -> void:
	# The Keeper (philosophical fragments)
	var keeper = _create_npc("The Keeper", "elder", Vector2(9 * TILE_SIZE, 4 * TILE_SIZE), [
		"You arrived.",
		"That is sufficient.",
		"Most things are not sufficient. This is.",
		"The void does not ask why you came.",
		"Neither do I.",
		"Rest if you need to. Leave when you are ready. That is all."
	])
	npcs.add_child(keeper)

	# The Shape (geometric entity, cryptic hints)
	var shape = _create_npc("The Shape", "mysterious", Vector2(4 * TILE_SIZE, 8 * TILE_SIZE), [
		"I have no name. I have a form.",
		"The form is: triangle. The meaning is: up.",
		"You are going somewhere. You have always been going somewhere.",
		"The path ahead is shaped like a question.",
		"The answer is shaped like a choice.",
		"Both are correct. Neither is safe."
	])
	npcs.add_child(shape)

	# The Echo (references player's battle history)
	var echo = _create_npc("The Echo", "villager", Vector2(14 * TILE_SIZE, 10 * TILE_SIZE), [
		"I remember the battles.",
		"All of them. Even the ones you'd rather forget.",
		"You have fought. You have won. You have also lost.",
		"The numbers don't lie — but they don't tell the whole truth either.",
		"What matters is that you kept going.",
		"...Or maybe the autobattle kept going. Close enough."
	])
	npcs.add_child(echo)

	# The Absence (empty NPC slot)
	var absence = _create_npc("The Absence", "villager", Vector2(9 * TILE_SIZE, 11 * TILE_SIZE), [
		"There is nothing here.",
		"That is the point.",
		"...You're still talking to it, though. Which means it isn't, quite.",
		"Thank you. That's an odd kind of gift."
	])
	npcs.add_child(absence)
