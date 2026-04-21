extends BaseVillage
class_name FrostholdVillageScene

## FrostholdVillage - Nordic outpost in the frozen northwest
## Features: Nordic Lodge (inn), Fur Trader (items), Ice Chapel (magic shop)

const VillageInnScript = preload("res://src/exploration/VillageInn.gd")
const VillageShopScript = preload("res://src/exploration/VillageShop.gd")
const TreasureChestScript = preload("res://src/exploration/TreasureChest.gd")

## Map dimensions (22x18 ice village)
const MAP_WIDTH: int = 22
const MAP_HEIGHT: int = 18


## ---- BaseVillage hooks ----

func _get_area_id() -> String:
	return "frosthold_village"


func _get_village_display_name() -> String:
	return "Frosthold"


func _get_map_pixel_size() -> Vector2i:
	return Vector2i(MAP_WIDTH * TILE_SIZE, MAP_HEIGHT * TILE_SIZE)


func _get_save_point_position() -> Vector2:
	return Vector2(8 * TILE_SIZE, 8 * TILE_SIZE)


func _get_player_spawn_fallback() -> Vector2:
	return Vector2(256, 416)


func _generate_map() -> void:
	# Frosthold layout: stone walls, ice terrain
	# W = wall, . = floor, L = lodge (inn), F = fur trader, C = chapel
	# I = ice/snow decoration, X = exit
	var map_data: Array[String] = [
		"WWWWWWWWWWWWWWWWWWWWWW",
		"W....................W",
		"W..LLL......CCC.....W",
		"W..LLL......CCC.....W",
		"W..LLL......CCC.....W",
		"W....................W",
		"W......IIII..........W",
		"W......IIII..FFF.....W",
		"W......IIII..FFF.....W",
		"W......IIII..FFF.....W",
		"W....................W",
		"W....................W",
		"W....................W",
		"W....................W",
		"W....................W",
		"W.....XXXXXX.........W",
		"W.....XXXXXX.........W",
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

	spawn_points["entrance"] = Vector2(8 * TILE_SIZE, 13 * TILE_SIZE)
	spawn_points["default"] = spawn_points["entrance"]
	spawn_points["frosthold_entrance"] = spawn_points["entrance"]


func _char_to_tile_type(char: String) -> int:
	match char:
		"W": return TileGeneratorScript.TileType.WALL
		"I": return TileGeneratorScript.TileType.ICE
		_: return TileGeneratorScript.TileType.FLOOR


func _get_atlas_coords(tile_type: int) -> Vector2i:
	var tile_id = TileGeneratorScript.get_tile_id(tile_type)
	return Vector2i(tile_id % 5, tile_id / 5)


func _setup_transitions() -> void:
	var exit_trans = AreaTransitionScript.new()
	exit_trans.name = "Exit"
	exit_trans.target_map = "overworld"
	exit_trans.target_spawn = "frosthold_entrance"
	exit_trans.require_interaction = false
	exit_trans.position = spawn_points.get("exit", Vector2(256, 512))
	_setup_transition_collision(exit_trans, Vector2(TILE_SIZE * 6, TILE_SIZE))
	exit_trans.transition_triggered.connect(_on_transition_triggered)
	transitions.add_child(exit_trans)


func _setup_buildings() -> void:
	# === NORDIC LODGE (Inn) ===
	var inn = VillageInnScript.new()
	inn.inn_name = "Nordic Lodge"
	inn.position = Vector2(3.5 * TILE_SIZE, 3 * TILE_SIZE)
	buildings.add_child(inn)

	# === FUR TRADER (Item Shop) ===
	var fur_trader = VillageShopScript.new()
	fur_trader.shop_name = "Fur Trader"
	fur_trader.shop_type = VillageShopScript.ShopType.ITEM
	fur_trader.keeper_name = "Helga"
	fur_trader.position = Vector2(15 * TILE_SIZE, 8 * TILE_SIZE)
	buildings.add_child(fur_trader)

	# === ICE CHAPEL (Magic Shop) ===
	var chapel = VillageShopScript.new()
	chapel.shop_name = "Ice Chapel"
	chapel.shop_type = VillageShopScript.ShopType.WHITE_MAGIC
	chapel.keeper_name = "Brother Frost"
	chapel.position = Vector2(14 * TILE_SIZE, 3 * TILE_SIZE)
	buildings.add_child(chapel)


func _setup_treasures() -> void:
	# 2x Hi-Potion behind lodge
	var chest1 = TreasureChestScript.new()
	chest1.chest_id = "frosthold_chest_1"
	chest1.contents_type = "item"
	chest1.contents_id = "hi_potion"
	chest1.contents_amount = 2
	chest1.position = Vector2(1.5 * TILE_SIZE, 5 * TILE_SIZE)
	treasures.add_child(chest1)

	# Ice Charm in chapel corner
	var chest2 = TreasureChestScript.new()
	chest2.chest_id = "frosthold_chest_2"
	chest2.contents_type = "equipment"
	chest2.contents_id = "ice_charm"
	chest2.position = Vector2(17 * TILE_SIZE, 2 * TILE_SIZE)
	treasures.add_child(chest2)


func _setup_npcs() -> void:
	# Old Man Björn (exposition)
	var bjorn = _create_npc("Old Man Björn", "elder", Vector2(6 * TILE_SIZE, 6 * TILE_SIZE), [
		"The ice dragon Glacius has been here since the first compile...",
		"I mean, the first winter.",
		"It guards the frozen peak with breath that freezes code— er, BONE.",
		"If you seek the Ice Scale, you'll need more than warm clothes."
	])
	npcs.add_child(bjorn)

	# Guard Ingrid (pessimistic)
	var ingrid = _create_npc("Guard Ingrid", "guard", Vector2(8 * TILE_SIZE, 14 * TILE_SIZE), [
		"Turn back. You're clearly not high enough level.",
		"I can see your stats from here.",
		"...What? No, I can't literally SEE them.",
		"It's a figure of speech. But seriously, you look weak."
	])
	npcs.add_child(ingrid)

	# Hermit Kael (autobattle)
	var kael = _create_npc("Hermit Kael", "villager", Vector2(10 * TILE_SIZE, 10 * TILE_SIZE), [
		"I automated my entire LIFE, friend.",
		"Breakfast? Automated. Conversations? Scripted.",
		"Do I regret it? ...That's also scripted.",
		"Press F5 to open the Autobattle Editor. Trust me.",
		"Once you automate combat, you'll want to automate EVERYTHING."
	])
	npcs.add_child(kael)

	# Merchant Helga (shivering)
	var helga = _create_npc("Merchant Helga", "villager", Vector2(16 * TILE_SIZE, 11 * TILE_SIZE), [
		"B-buy something warm, please.",
		"The d-developer forgot to add heating.",
		"I've been standing here since the scene loaded.",
		"Do you know how COLD a 32x32 tile gets?!"
	])
	npcs.add_child(helga)

	# Scholar Fynn (lore)
	var fynn = _create_npc("Scholar Fynn", "villager", Vector2(4 * TILE_SIZE, 11 * TILE_SIZE), [
		"Legend says four dragons guard four elemental scales.",
		"Collect them all and... actually, nobody remembers what happens next.",
		"The ancient texts just say 'TODO: implement endgame.'",
		"I'm sure it'll be patched eventually."
	])
	npcs.add_child(fynn)

	# Child Lumi (cheerful)
	var lumi = _create_npc("Child Lumi", "villager", Vector2(12 * TILE_SIZE, 4 * TILE_SIZE), [
		"I built a snowman! I named him 'Null Reference.'",
		"He keeps crashing.",
		"Every time I try to give him a nose, he throws an exception!",
		"Mom says I should try-catch him but that sounds mean."
	])
	npcs.add_child(lumi)
