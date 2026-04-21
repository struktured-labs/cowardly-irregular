extends BaseVillage
class_name MapleHeightsVillageScene

## MapleHeightsVillage - Nostalgic 90s suburban neighborhood
## Features: Mom's Guest Room (Inn), Suburban Mart (Item Shop), Picket fences, Mailboxes, NPCs

const VillageInnScript = preload("res://src/exploration/VillageInn.gd")
const VillageShopScript = preload("res://src/exploration/VillageShop.gd")
const TreasureChestScript = preload("res://src/exploration/TreasureChest.gd")

## Map dimensions
const MAP_WIDTH: int = 24
const MAP_HEIGHT: int = 18


## ---- BaseVillage hooks ----

func _get_area_id() -> String:
	return "maple_heights_village"


func _get_village_display_name() -> String:
	return "Maple Heights"


func _get_map_pixel_size() -> Vector2i:
	return Vector2i(MAP_WIDTH * TILE_SIZE, MAP_HEIGHT * TILE_SIZE)


func _get_save_point_position() -> Vector2:
	return Vector2(10 * TILE_SIZE, 8 * TILE_SIZE)


func _get_player_spawn_fallback() -> Vector2:
	return Vector2(384, 448)


func _generate_map() -> void:
	# Layout key:
	# W = perimeter wall
	# H = house walls (impassable)
	# I = inn (Mom's Guest Room)
	# S = shop (Suburban Mart)
	# g = grass (mowed suburban lawn)
	# p = path (sidewalk / driveway)
	# f = flower bed (garden patches)
	# e = hedge (impassable fence line)
	# d = dirt (worn areas, backyard)
	# X = exit path (sidewalk leading out)
	# Each row is exactly MAP_WIDTH (24) characters
	var map_data: Array[String] = [
		"WWWWWWWWWWWWWWWWWWWWWWWW",
		"WggggppppppppppppggfggggW",
		"WgHHHggggfggggggfgggggggW",
		"WgHHHggggggfgggggfggfgggW",
		"WgHHHgggfggggggggggggfggW",
		"WggggppppppppppppppppgggW",
		"WggfgpgggSSSggggIIIgpfggW",
		"WgggepgggSSSggggIIIgpgggW",
		"WgfgepgggSSSggggIIIgpfggW",
		"WggggppppppppppppppppgggW",
		"WgfgggggfggHHHggggggfgggW",
		"WgggggfgggHHHgggfgggggggW",
		"WggfgggggfHHHgggggfgggfgW",
		"WgggggggggggggggggggggggW",
		"WggfggggfggggfgggggfggggW",
		"WgggggggggggggggfgggggggW",
		"WgfggggggggXXXXXXgggfgggW",
		"WWWWWWWWWWWWWWWWWWWWWWWW",
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

	spawn_points["entrance"] = Vector2(12 * TILE_SIZE, 14 * TILE_SIZE)
	spawn_points["default"] = spawn_points["entrance"]
	spawn_points["maple_heights_entrance"] = spawn_points["entrance"]


func _char_to_tile_type(char: String) -> int:
	match char:
		"W": return TileGeneratorScript.TileType.WALL
		"H", "I", "S": return TileGeneratorScript.TileType.WALL
		"g": return TileGeneratorScript.TileType.VILLAGE_GRASS
		"p": return TileGeneratorScript.TileType.VILLAGE_PATH
		"d": return TileGeneratorScript.TileType.VILLAGE_DIRT
		"f": return TileGeneratorScript.TileType.VILLAGE_FLOWER
		"e": return TileGeneratorScript.TileType.VILLAGE_HEDGE
		"X": return TileGeneratorScript.TileType.VILLAGE_PATH
		_: return TileGeneratorScript.TileType.VILLAGE_GRASS


func _get_atlas_coords(tile_type: int) -> Vector2i:
	var tile_id = TileGeneratorScript.get_tile_id(tile_type)
	return Vector2i(tile_id % 5, tile_id / 5)


func _setup_transitions() -> void:
	var exit_trans = AreaTransitionScript.new()
	exit_trans.name = "Exit"
	exit_trans.target_map = "suburban_overworld"
	exit_trans.target_spawn = "maple_heights_entrance"
	exit_trans.require_interaction = false
	exit_trans.position = spawn_points.get("exit", Vector2(352, 544))
	_setup_transition_collision(exit_trans, Vector2(TILE_SIZE * 6, TILE_SIZE))
	exit_trans.transition_triggered.connect(_on_transition_triggered)
	transitions.add_child(exit_trans)


func _setup_buildings() -> void:
	# === INN (Mom's Guest Room) ===
	var inn = VillageInnScript.new()
	inn.inn_name = "Mom's Guest Room"
	inn.position = Vector2(17.5 * TILE_SIZE, 7 * TILE_SIZE)
	buildings.add_child(inn)

	# === ITEM SHOP (Suburban Mart) ===
	var shop = VillageShopScript.new()
	shop.shop_name = "Suburban Mart"
	shop.shop_type = VillageShopScript.ShopType.ITEM
	shop.keeper_name = "Donna"
	shop.position = Vector2(10 * TILE_SIZE, 7 * TILE_SIZE)
	buildings.add_child(shop)

	# === EQUIPMENT (Handyman's Garage) ===
	var smith = VillageShopScript.new()
	smith.shop_name = "Handyman's Garage"
	smith.shop_type = VillageShopScript.ShopType.BLACKSMITH
	smith.keeper_name = "Greg"
	smith.position = Vector2(13 * TILE_SIZE, 7 * TILE_SIZE)
	buildings.add_child(smith)

	# === MAGIC (Crystal Therapy Studio) ===
	var magic = VillageShopScript.new()
	magic.shop_name = "Crystal Therapy Studio"
	magic.shop_type = VillageShopScript.ShopType.WHITE_MAGIC
	magic.keeper_name = "Luna"
	magic.position = Vector2(6 * TILE_SIZE, 7 * TILE_SIZE)
	buildings.add_child(magic)


func _setup_treasures() -> void:
	# Hidden behind the house — a forgotten lunchbox with supplies
	var chest1 = TreasureChestScript.new()
	chest1.chest_id = "maple_heights_chest_1"
	chest1.contents_type = "item"
	chest1.contents_id = "potion"
	chest1.contents_amount = 2
	chest1.position = Vector2(1.5 * TILE_SIZE, 3 * TILE_SIZE)
	treasures.add_child(chest1)

	# Buried in the backyard — someone's old allowance
	var chest2 = TreasureChestScript.new()
	chest2.chest_id = "maple_heights_chest_2"
	chest2.contents_type = "gold"
	chest2.gold_amount = 80
	chest2.position = Vector2(20 * TILE_SIZE, 11 * TILE_SIZE)
	treasures.add_child(chest2)

	# Under a garden flower patch — a dusty ether
	var chest3 = TreasureChestScript.new()
	chest3.chest_id = "maple_heights_chest_3"
	chest3.contents_type = "item"
	chest3.contents_id = "ether"
	chest3.contents_amount = 1
	chest3.position = Vector2(4 * TILE_SIZE, 14 * TILE_SIZE)
	treasures.add_child(chest3)


func _setup_npcs() -> void:
	# Neighborhood Dad (BBQ tips / gameplay hints)
	var dad = _create_npc("Neighborhood Dad", "villager", Vector2(6 * TILE_SIZE, 12 * TILE_SIZE), [
		"Hey there, sport! You look like you could use some LIFE ADVICE.",
		"Always grill on medium heat. Never rush the char.",
		"Same applies to leveling up, by the way.",
		"Slow and steady. Unless you've got AUTOBATTLE running.",
		"Then honestly? Just let it rip.",
		"*flips imaginary burger*"
	])
	npcs.add_child(dad)

	# Mail Carrier (gossip / rumors)
	var mailman = _create_npc("Carriers Reg", "guard", Vector2(18 * TILE_SIZE, 4 * TILE_SIZE), [
		"Mail call! Uh... none for you, actually.",
		"But I heard some things on my route today.",
		"Old Mrs. Petrov says the caves north of here started HUMMING.",
		"The Hendersons got a new car. Very suspicious.",
		"And someone filed a complaint about reality 'feeling off'.",
		"Probably nothing. Here's a coupon."
	])
	npcs.add_child(mailman)

	# Kid on Bike (weird stuff / comedy)
	var kid = _create_npc("Tyler on Bike", "villager", Vector2(12 * TILE_SIZE, 9 * TILE_SIZE), [
		"WHOOOOOAAA—",
		"*skids to stop*",
		"Dude. DUDE. There's something in the storm drain.",
		"It blinks at me every Tuesday.",
		"I've been documenting it in a notebook.",
		"Anyway, gotta go. Mom said dinner's at 6. BYE."
	])
	npcs.add_child(kid)

	# Retired Teacher (lore about how the world changed)
	var teacher = _create_npc("Ms. Finch", "elder", Vector2(3 * TILE_SIZE, 9 * TILE_SIZE), [
		"Ah, a young traveler. Sit down. I used to teach history.",
		"Not the history in your textbooks — the REAL history.",
		"This neighborhood wasn't always... suburban.",
		"Something shifted. The aesthetics changed overnight.",
		"One morning: cobblestones and swords. Next: cul-de-sacs and minivans.",
		"I'm retired now. I don't ask questions anymore."
	])
	npcs.add_child(teacher)

	# Dog Walker (comedy relief)
	var dogwalker = _create_npc("Doug & Pretzel", "villager", Vector2(16 * TILE_SIZE, 12 * TILE_SIZE), [
		"Oh, don't mind Pretzel. He barks at adventurers.",
		"*BORK BORK BORK*",
		"He once defeated a Level 12 Goblin by sitting on it.",
		"We didn't plan that. It just happened.",
		"Anyway, he gets three walks a day and is probably stronger than you.",
		"*tail wagging intensifies*"
	])
	npcs.add_child(dogwalker)
