extends BaseVillage
class_name RivetRowVillageScene

## RivetRowVillage - Workers' settlement on factory outskirts
## Features: Workers' Barracks, Company Store, canteen, smokestacks, graffiti wall

const VillageInnScript = preload("res://src/exploration/VillageInn.gd")
const VillageShopScript = preload("res://src/exploration/VillageShop.gd")
const TreasureChestScript = preload("res://src/exploration/TreasureChest.gd")

## Map dimensions
const MAP_WIDTH: int = 22
const MAP_HEIGHT: int = 16


## ---- BaseVillage hooks ----

func _get_area_id() -> String:
	return "rivet_row_village"


func _get_village_display_name() -> String:
	return "Rivet Row"


func _get_map_pixel_size() -> Vector2i:
	return Vector2i(MAP_WIDTH * TILE_SIZE, MAP_HEIGHT * TILE_SIZE)


func _get_save_point_position() -> Vector2:
	return Vector2(10 * TILE_SIZE, 6 * TILE_SIZE)


func _get_player_spawn_fallback() -> Vector2:
	return Vector2(352, 320)


func _generate_map() -> void:
	# Rivet Row layout: industrial workers' settlement
	# W = perimeter wall, . = floor (concrete), d = village dirt (yard)
	# I = inn (barracks), G = general store (company store), C = canteen
	# V = lava channel (industrial runoff), X = exit
	# Each row is exactly MAP_WIDTH (22) characters
	var map_data: Array[String] = [
		"WWWWWWWWWWWWWWWWWWWWWW",
		"W....................W",
		"W.III..ddd..GGG......W",
		"W.III..ddd..GGG......W",
		"W.III..ddd..GGG......W",
		"W....................W",
		"W....VVVVVVV.........W",
		"W....VVVVVVV.........W",
		"W....................W",
		"W.CCC................W",
		"W.CCC................W",
		"W.CCC................W",
		"W....................W",
		"W.......XXXXXX.......W",
		"W.......XXXXXX.......W",
		"WWWWWWWWWWWWWWWWWWWWWW",
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

	spawn_points["entrance"] = Vector2(11 * TILE_SIZE, 10 * TILE_SIZE)
	spawn_points["default"] = spawn_points["entrance"]
	spawn_points["rivet_row_entrance"] = spawn_points["entrance"]


func _char_to_tile_type(char: String) -> int:
	match char:
		"W": return TileGeneratorScript.TileType.WALL
		"V": return TileGeneratorScript.TileType.LAVA
		"d": return TileGeneratorScript.TileType.VILLAGE_DIRT
		"X": return TileGeneratorScript.TileType.VILLAGE_PATH
		_: return TileGeneratorScript.TileType.FLOOR


func _get_atlas_coords(tile_type: int) -> Vector2i:
	var tile_id = TileGeneratorScript.get_tile_id(tile_type)
	return Vector2i(tile_id % 5, tile_id / 5)


func _setup_transitions() -> void:
	var exit_trans = AreaTransitionScript.new()
	exit_trans.name = "Exit"
	exit_trans.target_map = "industrial_overworld"
	exit_trans.target_spawn = "rivet_row_entrance"
	exit_trans.require_interaction = false
	exit_trans.position = spawn_points.get("exit", Vector2(352, 448))
	_setup_transition_collision(exit_trans, Vector2(TILE_SIZE * 6, TILE_SIZE))
	exit_trans.transition_triggered.connect(_on_transition_triggered)
	transitions.add_child(exit_trans)


func _setup_buildings() -> void:
	# === WORKERS' BARRACKS (Inn) ===
	var inn = VillageInnScript.new()
	inn.inn_name = "Workers' Barracks"
	inn.position = Vector2(2.5 * TILE_SIZE, 3 * TILE_SIZE)
	buildings.add_child(inn)

	# === COMPANY STORE (Item Shop) ===
	var store = VillageShopScript.new()
	store.shop_name = "Company Store"
	store.shop_type = VillageShopScript.ShopType.ITEM
	store.keeper_name = "Overseer Brack"
	store.position = Vector2(12.5 * TILE_SIZE, 3 * TILE_SIZE)
	buildings.add_child(store)

	# === SHOP FLOOR FORGE (Equipment) ===
	var forge = VillageShopScript.new()
	forge.shop_name = "Shop Floor Forge"
	forge.shop_type = VillageShopScript.ShopType.BLACKSMITH
	forge.keeper_name = "Mag"
	forge.position = Vector2(12.5 * TILE_SIZE, 8 * TILE_SIZE)
	buildings.add_child(forge)

	# === BOILERMAN'S APOTHECARY (Magic) ===
	var magic = VillageShopScript.new()
	magic.shop_name = "Boilerman's Apothecary"
	magic.shop_type = VillageShopScript.ShopType.BLACK_MAGIC
	magic.keeper_name = "Slag"
	magic.position = Vector2(6 * TILE_SIZE, 8 * TILE_SIZE)
	buildings.add_child(magic)


func _setup_treasures() -> void:
	# Contraband stash behind the barracks
	var chest1 = TreasureChestScript.new()
	chest1.chest_id = "rivet_row_chest_1"
	chest1.contents_type = "item"
	chest1.contents_id = "potion"
	chest1.contents_amount = 2
	chest1.position = Vector2(1.5 * TILE_SIZE, 1.5 * TILE_SIZE)
	treasures.add_child(chest1)

	# Union dues hidden under canteen floorboard
	var chest2 = TreasureChestScript.new()
	chest2.chest_id = "rivet_row_chest_2"
	chest2.contents_type = "gold"
	chest2.gold_amount = 80
	chest2.position = Vector2(1.5 * TILE_SIZE, 11 * TILE_SIZE)
	treasures.add_child(chest2)


func _setup_npcs() -> void:
	# Shift Foreman (work-related hints)
	var foreman = _create_npc("Shift Foreman Grix", "guard", Vector2(8 * TILE_SIZE, 3 * TILE_SIZE), [
		"Shift starts when the whistle blows. No excuses.",
		"We run three shifts here: early, late, and 'extended late'.",
		"Management calls it 'optimization.' I call it Tuesday.",
		"If your HP drops below twenty-five percent, REST. That's an ORDER.",
		"A dead worker is an inefficient worker. And inefficiency is UNACCEPTABLE."
	])
	npcs.add_child(foreman)

	# Union Rep (subversive)
	var union_rep = _create_npc("Union Rep Voss", "villager", Vector2(17 * TILE_SIZE, 9 * TILE_SIZE), [
		"*whispers* Keep your voice down.",
		"The foreman tracks output. Every action you take is LOGGED.",
		"They called it 'optimization gone wrong' — I call it working as designed.",
		"They automate us. We automate back. Fair is fair.",
		"If you find out how to edit the shift log... come find me.",
		"I'll make it worth your while."
	])
	npcs.add_child(union_rep)

	# Canteen Cook (heals party, humor)
	var cook = _create_npc("Canteen Cook Murl", "villager", Vector2(3 * TILE_SIZE, 11 * TILE_SIZE), [
		"Welcome to the canteen! Today's special is Mystery Stew.",
		"Yesterday's special was also Mystery Stew.",
		"Every day is Mystery Stew. We haven't solved the mystery yet.",
		"...Actually, eat up. Your whole party looks terrible.",
		"*the stew restores the party's spirits, if not their dignity*"
	])
	npcs.add_child(cook)

	# Factory Kid (aspirational)
	var kid = _create_npc("Factory Kid Pell", "villager", Vector2(15 * TILE_SIZE, 6 * TILE_SIZE), [
		"I'm gonna be Employee of the Month someday!",
		"I swept the east corridor TWICE yesterday.",
		"The quota is once. I am TWICE the worker.",
		"Management gave me a certificate. It said 'satisfactory.'",
		"...I'm going to frame it."
	])
	npcs.add_child(kid)

	# Graffiti Wall (interactable object)
	var graffiti = _create_npc("Graffiti Wall", "villager", Vector2(19 * TILE_SIZE, 2 * TILE_SIZE), [
		"Scrawled on the wall:",
		"'AUTOMATE THE FOREMAN'",
		"'QUOTA IS A LIE'",
		"'THE CAVE DOESN'T LOG YOUR HOURS'",
		"'EMPLOYEE OF THE MONTH IS RIGGED — ASK VOSS'",
		"Someone has drawn a surprisingly accurate map of the overworld. In crayon."
	])
	npcs.add_child(graffiti)
