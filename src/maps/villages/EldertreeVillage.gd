extends BaseVillage
class_name EldertreeVillageScene

## EldertreeVillage - Elven treehouse village in the northern forest
## Features: Canopy Inn, Herb Garden (items), Training Hollow (weapons)

const VillageInnScript = preload("res://src/exploration/VillageInn.gd")
const VillageShopScript = preload("res://src/exploration/VillageShop.gd")
const TreasureChestScript = preload("res://src/exploration/TreasureChest.gd")

## Map dimensions (25x20 forest village)
const MAP_WIDTH: int = 25
const MAP_HEIGHT: int = 20


## ---- BaseVillage hooks ----

func _get_area_id() -> String:
	return "eldertree_village"


func _get_village_display_name() -> String:
	return "Eldertree"


func _get_map_pixel_size() -> Vector2i:
	return Vector2i(MAP_WIDTH * TILE_SIZE, MAP_HEIGHT * TILE_SIZE)


func _get_save_point_position() -> Vector2:
	return Vector2(12 * TILE_SIZE, 8 * TILE_SIZE)


func _get_player_spawn_fallback() -> Vector2:
	return Vector2(384, 480)


func _generate_map() -> void:
	# Eldertree layout: forest canopy village, trees throughout
	# W = wall, . = floor, T = tree, N = canopy inn, G = herb garden, H = training hollow
	# X = exit
	var map_data: Array[String] = [
		"WWWWWWWWWWWWWWWWWWWWWWWWW",
		"W.....T....T.....T......W",
		"W..NNN..T.......HHH..T..W",
		"W..NNN........T.HHH.....W",
		"W..NNN..........HHH.....W",
		"W.....T....T.............W",
		"W..........T....T........W",
		"W...T..GGG...............W",
		"W......GGG.......T.......W",
		"W......GGG...............W",
		"W..T.........T...........W",
		"W............T.....T.....W",
		"W.....T..................W",
		"W..T...........T.........W",
		"W........................W",
		"W...T..........T.........W",
		"W........................W",
		"W.......XXXXXX...........W",
		"W.......XXXXXX...........W",
		"WWWWWWWWWWWWWWWWWWWWWWWWW",
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

	spawn_points["entrance"] = Vector2(12 * TILE_SIZE, 15 * TILE_SIZE)
	spawn_points["default"] = spawn_points["entrance"]
	spawn_points["eldertree_entrance"] = spawn_points["entrance"]


func _char_to_tile_type(char: String) -> int:
	match char:
		"W": return TileGeneratorScript.TileType.WALL
		"T": return TileGeneratorScript.TileType.FOREST
		_: return TileGeneratorScript.TileType.FLOOR


func _get_atlas_coords(tile_type: int) -> Vector2i:
	var tile_id = TileGeneratorScript.get_tile_id(tile_type)
	return Vector2i(tile_id % 5, tile_id / 5)


func _setup_transitions() -> void:
	var exit_trans = AreaTransitionScript.new()
	exit_trans.name = "Exit"
	exit_trans.target_map = "overworld"
	exit_trans.target_spawn = "eldertree_entrance"
	exit_trans.require_interaction = false
	exit_trans.position = spawn_points.get("exit", Vector2(352, 576))
	_setup_transition_collision(exit_trans, Vector2(TILE_SIZE * 6, TILE_SIZE))
	exit_trans.transition_triggered.connect(_on_transition_triggered)
	transitions.add_child(exit_trans)


func _setup_buildings() -> void:
	# === CANOPY INN ===
	var inn = VillageInnScript.new()
	inn.inn_name = "Canopy Inn"
	inn.position = Vector2(3.5 * TILE_SIZE, 3 * TILE_SIZE)
	buildings.add_child(inn)

	# === HERB GARDEN (Item Shop) ===
	var herb_garden = VillageShopScript.new()
	herb_garden.shop_name = "Herb Garden"
	herb_garden.shop_type = VillageShopScript.ShopType.ITEM
	herb_garden.keeper_name = "Thorn"
	herb_garden.position = Vector2(8 * TILE_SIZE, 8 * TILE_SIZE)
	buildings.add_child(herb_garden)

	# === TRAINING HOLLOW (Weapon Shop) ===
	var training = VillageShopScript.new()
	training.shop_name = "Training Hollow"
	training.shop_type = VillageShopScript.ShopType.BLACKSMITH
	training.keeper_name = "Ranger Oak"
	training.position = Vector2(19 * TILE_SIZE, 3 * TILE_SIZE)
	buildings.add_child(training)


func _setup_treasures() -> void:
	# 3x Ether in herb garden
	var chest1 = TreasureChestScript.new()
	chest1.chest_id = "eldertree_chest_1"
	chest1.contents_type = "item"
	chest1.contents_id = "ether"
	chest1.contents_amount = 3
	chest1.position = Vector2(6 * TILE_SIZE, 9 * TILE_SIZE)
	treasures.add_child(chest1)

	# Forest Amulet behind training grounds
	var chest2 = TreasureChestScript.new()
	chest2.chest_id = "eldertree_chest_2"
	chest2.contents_type = "equipment"
	chest2.contents_id = "forest_amulet"
	chest2.position = Vector2(22 * TILE_SIZE, 2 * TILE_SIZE)
	treasures.add_child(chest2)


func _setup_npcs() -> void:
	# Tutorial Fairy Pip (unwanted help)
	var pip = _create_npc("Tutorial Fairy Pip", "villager", Vector2(12 * TILE_SIZE, 5 * TILE_SIZE), [
		"HEY! LISTEN!",
		"Did you know you can press buttons to do things?",
		"You're WELCOME!",
		"Also, did you know walking moves you FORWARD?",
		"I'm SO helpful. You'd be LOST without me.",
		"...Please don't mute me. I get lonely."
	])
	npcs.add_child(pip)

	# Merchant Thorn (suspicious)
	var thorn = _create_npc("Merchant Thorn", "villager", Vector2(10 * TILE_SIZE, 7 * TILE_SIZE), [
		"These goods? Oh, they fell off a caravan.",
		"Several caravans. Look, do you want them or not?",
		"I have potions, ethers, and 'definitely not stolen' equipment.",
		"No refunds. No questions. No eye contact."
	])
	npcs.add_child(thorn)

	# Speedrun Monk Dash (efficiency)
	var dash = _create_npc("Speedrun Monk Dash", "villager", Vector2(18 * TILE_SIZE, 6 * TILE_SIZE), [
		"Words are experience points you're leaving on the table.",
		"Skip my dialogue. Go. NOW.",
		"...Why are you still reading?",
		"Every frame you spend here is a frame wasted.",
		"I've optimized my own dialogue to four lines. You're welcome."
	])
	npcs.add_child(dash)

	# Elder Moss (wisdom)
	var moss = _create_npc("Elder Moss", "elder", Vector2(5 * TILE_SIZE, 13 * TILE_SIZE), [
		"The forest remembers all who pass.",
		"It also remembers your embarrassing defeats.",
		"ALL of them.",
		"That time you died to a slime? The trees whisper about it.",
		"But fear not. Growth comes from failure. And fertilizer."
	])
	npcs.add_child(moss)

	# Ranger Ivy (practical)
	var ivy = _create_npc("Ranger Ivy", "guard", Vector2(20 * TILE_SIZE, 12 * TILE_SIZE), [
		"Watch for wolves. They hunt in packs.",
		"And they've learned your autobattle patterns.",
		"I've seen one dodge a scripted Fire spell.",
		"Nature adapts. Your scripts should too."
	])
	npcs.add_child(ivy)

	# Mushroom Collector Spore (weird)
	var spore = _create_npc("Mushroom Collector Spore", "villager", Vector2(15 * TILE_SIZE, 14 * TILE_SIZE), [
		"The mushrooms here talk to me.",
		"They say you need more defense.",
		"The mushrooms are usually right.",
		"Last week they predicted the weather. And a boss fight.",
		"...I should probably stop eating them."
	])
	npcs.add_child(spore)
