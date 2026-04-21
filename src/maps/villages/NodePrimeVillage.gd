extends BaseVillage
class_name NodePrimeVillageScene

## NodePrimeVillage - Digital rest stop / data hub in the futuristic overworld
## Features: Sleep.exe (inn), Cache Store (magic shop), holographic signs, geometric architecture

const VillageInnScript = preload("res://src/exploration/VillageInn.gd")
const VillageShopScript = preload("res://src/exploration/VillageShop.gd")
const TreasureChestScript = preload("res://src/exploration/TreasureChest.gd")

## Map dimensions
const MAP_WIDTH: int = 20
const MAP_HEIGHT: int = 18


## ---- BaseVillage hooks ----

func _get_area_id() -> String:
	return "node_prime_village"


func _get_village_display_name() -> String:
	return "Node Prime"


func _get_map_pixel_size() -> Vector2i:
	return Vector2i(MAP_WIDTH * TILE_SIZE, MAP_HEIGHT * TILE_SIZE)


func _get_save_point_position() -> Vector2:
	return Vector2(8 * TILE_SIZE, 8 * TILE_SIZE)


func _get_player_spawn_fallback() -> Vector2:
	return Vector2(320, 320)


func _generate_map() -> void:
	# Node Prime layout: clean geometric digital architecture
	# W = wall, . = floor (polished), p = path (grid lines)
	# I = inn (Sleep.exe), C = cache store, F = firewall barrier (wall)
	# X = exit, W = water (coolant channels)
	# Each row is exactly MAP_WIDTH (20) characters
	var map_data: Array[String] = [
		"WWWWWWWWWWWWWWWWWWWW",
		"W..................W",
		"W.III....CCC.......W",
		"W.III....CCC.......W",
		"W.III....CCC.......W",
		"W..................W",
		"W...pppppppp.......W",
		"W...pppppppp.......W",
		"W..................W",
		"W..................W",
		"W..FFFF............W",
		"W..FFFF............W",
		"W..FFFF............W",
		"W..................W",
		"W..................W",
		"W......XXXXXX......W",
		"W......XXXXXX......W",
		"WWWWWWWWWWWWWWWWWWWW",
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

	spawn_points["entrance"] = Vector2(10 * TILE_SIZE, 10 * TILE_SIZE)
	spawn_points["default"] = spawn_points["entrance"]
	spawn_points["node_prime_entrance"] = spawn_points["entrance"]


func _char_to_tile_type(char: String) -> int:
	match char:
		"W": return TileGeneratorScript.TileType.WALL
		"F": return TileGeneratorScript.TileType.WALL
		"p": return TileGeneratorScript.TileType.VILLAGE_PATH
		"X": return TileGeneratorScript.TileType.VILLAGE_PATH
		_: return TileGeneratorScript.TileType.FLOOR


func _get_atlas_coords(tile_type: int) -> Vector2i:
	var tile_id = TileGeneratorScript.get_tile_id(tile_type)
	return Vector2i(tile_id % 5, tile_id / 5)


func _setup_transitions() -> void:
	var exit_trans = AreaTransitionScript.new()
	exit_trans.name = "Exit"
	exit_trans.target_map = "futuristic_overworld"
	exit_trans.target_spawn = "node_prime_entrance"
	exit_trans.require_interaction = false
	exit_trans.position = spawn_points.get("exit", Vector2(320, 512))
	_setup_transition_collision(exit_trans, Vector2(TILE_SIZE * 6, TILE_SIZE))
	exit_trans.transition_triggered.connect(_on_transition_triggered)
	transitions.add_child(exit_trans)


func _setup_buildings() -> void:
	# === SLEEP.EXE (Inn) ===
	var inn = VillageInnScript.new()
	inn.inn_name = "Sleep.exe"
	inn.position = Vector2(2.5 * TILE_SIZE, 3 * TILE_SIZE)
	buildings.add_child(inn)

	# === CACHE STORE (White Magic Shop) ===
	var cache_store = VillageShopScript.new()
	cache_store.shop_name = "Cache Store"
	cache_store.shop_type = VillageShopScript.ShopType.WHITE_MAGIC
	cache_store.keeper_name = "CACHE-1"
	cache_store.position = Vector2(10 * TILE_SIZE, 3 * TILE_SIZE)
	buildings.add_child(cache_store)

	# === HEAP (Item Shop) ===
	var heap = VillageShopScript.new()
	heap.shop_name = "Heap Allocator"
	heap.shop_type = VillageShopScript.ShopType.ITEM
	heap.keeper_name = "MALLOC-7"
	heap.position = Vector2(6 * TILE_SIZE, 3 * TILE_SIZE)
	buildings.add_child(heap)

	# === KERNEL SMITHY (Equipment) ===
	var smith = VillageShopScript.new()
	smith.shop_name = "Kernel Smithy"
	smith.shop_type = VillageShopScript.ShopType.BLACKSMITH
	smith.keeper_name = "COMPILE-R"
	smith.position = Vector2(14 * TILE_SIZE, 3 * TILE_SIZE)
	buildings.add_child(smith)


func _setup_treasures() -> void:
	# Corrupted data packet — unclaimed memory
	var chest1 = TreasureChestScript.new()
	chest1.chest_id = "node_prime_chest_1"
	chest1.contents_type = "item"
	chest1.contents_id = "ether"
	chest1.contents_amount = 2
	chest1.position = Vector2(17 * TILE_SIZE, 1.5 * TILE_SIZE)
	treasures.add_child(chest1)

	# Archived gold — old transaction log
	var chest2 = TreasureChestScript.new()
	chest2.chest_id = "node_prime_chest_2"
	chest2.contents_type = "gold"
	chest2.gold_amount = 200
	chest2.position = Vector2(17 * TILE_SIZE, 13 * TILE_SIZE)
	treasures.add_child(chest2)


func _setup_npcs() -> void:
	# System Admin ADMIN-01 (terminal commands)
	var admin = _create_npc("ADMIN-01", "guard", Vector2(7 * TILE_SIZE, 2 * TILE_SIZE), [
		"> QUERY: purpose_of_visit",
		"> INPUT RECEIVED: adventurer",
		"> STATUS: access_granted",
		"Proceed to designated rest nodes. Unauthorized processes will be terminated.",
		"> NOTE: the optimization layer is watching",
		"> END TRANSMISSION"
	])
	npcs.add_child(admin)

	# Debugger DEBUG-7 (glitches)
	var debugger = _create_npc("DEBUG-7", "villager", Vector2(14 * TILE_SIZE, 7 * TILE_SIZE), [
		"Oh good, you can see me. That means the render pass is working.",
		"I've been flagging anomalies in sector nine for three cycles.",
		"Something keeps rewriting the encounter tables.",
		"I call it a 'glitch.' The admin calls it 'intended behavior.'",
		"...The admin is lying.",
		"Also, your HP display flickered on my end. You might want to check that."
	])
	npcs.add_child(debugger)

	# Tourist Program TOURIST.EXE (confused)
	var tourist = _create_npc("TOURIST.EXE", "villager", Vector2(10 * TILE_SIZE, 12 * TILE_SIZE), [
		"ERROR: context_mismatch — expected 'scenic overlook', received 'data hub'",
		"I booked a package tour. The brochure said 'breathtaking vistas.'",
		"This is a floor. It is very flat. I am not taking breath.",
		"...Is this the scenic route?",
		"I will leave a review. It will be two stars.",
		"One star for the floor. One star for you. You seem nice."
	])
	npcs.add_child(tourist)

	# Data Archivist (lore keeper)
	var archivist = _create_npc("Data Archivist", "elder", Vector2(3 * TILE_SIZE, 9 * TILE_SIZE), [
		"Before the optimization, this place had a name.",
		"A real name. Not a designation.",
		"People lived here. They had routines that were not mandated.",
		"The system said efficiency required... simplification.",
		"I kept the old records. In here.",
		"*taps head* They cannot optimize what they cannot index."
	])
	npcs.add_child(archivist)

	# Firewall Guard (blocks path, future content hint)
	var firewall = _create_npc("FIREWALL-ALPHA", "guard", Vector2(3 * TILE_SIZE, 13 * TILE_SIZE), [
		"HALT. Access to sector twelve is restricted.",
		"Clearance level required: DELTA.",
		"Your current clearance level: NONE.",
		"When you have acquired sufficient system permissions, return.",
		"...I will be here. I am always here.",
		"I have been here for four hundred cycles. I am fine. Everything is fine."
	])
	npcs.add_child(firewall)
