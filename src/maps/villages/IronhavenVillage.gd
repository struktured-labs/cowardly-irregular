extends BaseVillage
class_name IronhavenVillageScene

## IronhavenVillage - Industrial frontier forge town in the volcanic southeast
## Features: Ironclad Inn, Master Forge (weapons), Steamworks (unique), Miner's Tavern

const VillageInnScript = preload("res://src/exploration/VillageInn.gd")
const VillageShopScript = preload("res://src/exploration/VillageShop.gd")
const TreasureChestScript = preload("res://src/exploration/TreasureChest.gd")

## Map dimensions (25x20 industrial town)
const MAP_WIDTH: int = 25
const MAP_HEIGHT: int = 20


## ---- BaseVillage hooks ----

func _get_area_id() -> String:
	return "ironhaven_village"


func _get_village_display_name() -> String:
	return "Ironhaven"


func _get_map_pixel_size() -> Vector2i:
	return Vector2i(MAP_WIDTH * TILE_SIZE, MAP_HEIGHT * TILE_SIZE)


func _get_save_point_position() -> Vector2:
	return Vector2(10 * TILE_SIZE, 8 * TILE_SIZE)


func _get_player_spawn_fallback() -> Vector2:
	return Vector2(384, 480)


func _generate_map() -> void:
	# Ironhaven layout: industrial forge town with lava channels
	# W = wall, . = floor, V = lava, I = ironclad inn, F = master forge
	# S = steamworks, M = miner's tavern, X = exit
	var map_data: Array[String] = [
		"WWWWWWWWWWWWWWWWWWWWWWWWW",
		"W.......................W",
		"W..III.....FFF..........W",
		"W..III.....FFF...SSS....W",
		"W..III.....FFF...SSS....W",
		"W..........FFF...SSS....W",
		"W.......................W",
		"W.........VVV...........W",
		"W.........VVV...........W",
		"W.........VVV...........W",
		"W.......................W",
		"W..MMM..................W",
		"W..MMM..................W",
		"W..MMM..................W",
		"W.......................W",
		"W.......................W",
		"W.......................W",
		"W........XXXXXX.........W",
		"W........XXXXXX.........W",
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
	spawn_points["ironhaven_entrance"] = spawn_points["entrance"]


func _char_to_tile_type(char: String) -> int:
	match char:
		"W": return TileGeneratorScript.TileType.WALL
		"V": return TileGeneratorScript.TileType.LAVA
		_: return TileGeneratorScript.TileType.FLOOR


func _get_atlas_coords(tile_type: int) -> Vector2i:
	var tile_id = TileGeneratorScript.get_tile_id(tile_type)
	return Vector2i(tile_id % 5, tile_id / 5)


func _setup_transitions() -> void:
	var exit_trans = AreaTransitionScript.new()
	exit_trans.name = "Exit"
	exit_trans.target_map = "overworld"
	exit_trans.target_spawn = "ironhaven_entrance"
	exit_trans.require_interaction = false
	exit_trans.position = spawn_points.get("exit", Vector2(384, 576))
	_setup_transition_collision(exit_trans, Vector2(TILE_SIZE * 6, TILE_SIZE))
	exit_trans.transition_triggered.connect(_on_transition_triggered)
	transitions.add_child(exit_trans)


func _setup_buildings() -> void:
	# === IRONCLAD INN ===
	var inn = VillageInnScript.new()
	inn.inn_name = "Ironclad Inn"
	inn.position = Vector2(3.5 * TILE_SIZE, 3 * TILE_SIZE)
	buildings.add_child(inn)

	# === MASTER FORGE (Weapon Shop) ===
	var forge = VillageShopScript.new()
	forge.shop_name = "Master Forge"
	forge.shop_type = VillageShopScript.ShopType.BLACKSMITH
	forge.keeper_name = "Magda"
	forge.position = Vector2(12.5 * TILE_SIZE, 4 * TILE_SIZE)
	buildings.add_child(forge)

	# === STEAMWORKS (Item Shop - unique tech items) ===
	var steamworks = VillageShopScript.new()
	steamworks.shop_name = "Steamworks"
	steamworks.shop_type = VillageShopScript.ShopType.ITEM
	steamworks.keeper_name = "Dr. Cog"
	steamworks.position = Vector2(20 * TILE_SIZE, 4 * TILE_SIZE)
	buildings.add_child(steamworks)

	# === MINER'S TAVERN ===
	var tavern = VillageInnScript.new()
	tavern.inn_name = "Miner's Tavern"
	tavern.position = Vector2(3.5 * TILE_SIZE, 12 * TILE_SIZE)
	buildings.add_child(tavern)


func _setup_treasures() -> void:
	# Iron Shield near forge
	var chest1 = TreasureChestScript.new()
	chest1.chest_id = "ironhaven_chest_1"
	chest1.contents_type = "equipment"
	chest1.contents_id = "iron_shield"
	chest1.position = Vector2(10 * TILE_SIZE, 2 * TILE_SIZE)
	treasures.add_child(chest1)

	# 3x Hi-Potion in tavern cellar
	var chest2 = TreasureChestScript.new()
	chest2.chest_id = "ironhaven_chest_2"
	chest2.contents_type = "item"
	chest2.contents_id = "hi_potion"
	chest2.contents_amount = 3
	chest2.position = Vector2(1.5 * TILE_SIZE, 14 * TILE_SIZE)
	treasures.add_child(chest2)


func _setup_npcs() -> void:
	# Blacksmith Magda (eager)
	var magda = _create_npc("Blacksmith Magda", "villager", Vector2(14 * TILE_SIZE, 6 * TILE_SIZE), [
		"Dragon scales, you say?",
		"Oh, I could forge LEGENDARY equipment from those.",
		"Come back with four. Bring receipts.",
		"I don't accept scales of questionable provenance.",
		"Last guy brought me lizard skin. LIZARD. The audacity."
	])
	npcs.add_child(magda)

	# War Veteran Koss (mysterious)
	var koss = _create_npc("War Veteran Koss", "guard", Vector2(18 * TILE_SIZE, 10 * TILE_SIZE), [
		"I've seen what lies beyond the southern gate.",
		"Concrete. Streetlights. ...Saxophone music.",
		"The future is WEIRD.",
		"If you go south, bring earplugs.",
		"And maybe a map. The streets don't make sense."
	])
	npcs.add_child(koss)

	# Automation Researcher Dr. Cog (philosophical)
	var cog = _create_npc("Dr. Cog", "villager", Vector2(21 * TILE_SIZE, 6 * TILE_SIZE), [
		"What if the NPCs could automate too?",
		"What if I already HAVE and this dialogue is just my script running?",
		"...Hypothesis confirmed.",
		"I've been running my own autobattle scripts for YEARS.",
		"My dialogue tree is fully optimized. You're in the fast path."
	])
	npcs.add_child(cog)

	# Miner Pete (tired)
	var pete = _create_npc("Miner Pete", "villager", Vector2(6 * TILE_SIZE, 10 * TILE_SIZE), [
		"The volcanic caves are brutal.",
		"My pickaxe melted. MY BOOTS melted.",
		"The dragon just laughed.",
		"It breathes fire AND sarcasm.",
		"I'm taking a LONG vacation."
	])
	npcs.add_child(pete)

	# Apprentice Bolt (eager)
	var bolt = _create_npc("Apprentice Bolt", "villager", Vector2(8 * TILE_SIZE, 14 * TILE_SIZE), [
		"I'm building a machine that plays the game FOR you!",
		"...Wait, isn't that just autobattle?",
		"Oh NO.",
		"My entire thesis is redundant.",
		"Well, at least mine has GEARS. That counts for something, right?"
	])
	npcs.add_child(bolt)

	# Barkeep Ember (warm)
	var ember = _create_npc("Barkeep Ember", "villager", Vector2(4 * TILE_SIZE, 14 * TILE_SIZE), [
		"Welcome to the last inn before the fire cave.",
		"We serve drinks and existential dread.",
		"Both are on the house.",
		"The special today is 'Lava Lager.' It's... warm.",
		"Like, REALLY warm. We haven't figured out cooling yet."
	])
	npcs.add_child(ember)

	# Mysterious Stranger (foreshadowing)
	var stranger = _create_npc("Mysterious Stranger", "villager", Vector2(20 * TILE_SIZE, 16 * TILE_SIZE), [
		"The portal to the south...",
		"It leads to a place where magic runs on coal...",
		"And dreams run on rails.",
		"Are you ready?",
		"...Don't answer that. It was rhetorical. Also, probably no."
	])
	npcs.add_child(stranger)
