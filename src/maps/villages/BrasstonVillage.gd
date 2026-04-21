extends BaseVillage
class_name BrasstonVillageScene

## BrasstonVillage - Clockwork market town with brass pipes, gas lamps, and gear-shaped fountains
## Features: The Cog & Pillow (Inn), Gearwright's Forge (Blacksmith), Tinkerers, Steam Merchant

const VillageInnScript = preload("res://src/exploration/VillageInn.gd")
const VillageShopScript = preload("res://src/exploration/VillageShop.gd")
const TreasureChestScript = preload("res://src/exploration/TreasureChest.gd")

## Map dimensions
const MAP_WIDTH: int = 22
const MAP_HEIGHT: int = 18


## ---- BaseVillage hooks ----

func _get_area_id() -> String:
	return "brasston_village"


func _get_village_display_name() -> String:
	return "Brasston"


func _get_map_pixel_size() -> Vector2i:
	return Vector2i(MAP_WIDTH * TILE_SIZE, MAP_HEIGHT * TILE_SIZE)


func _get_save_point_position() -> Vector2:
	return Vector2(8 * TILE_SIZE, 8 * TILE_SIZE)


func _get_player_spawn_fallback() -> Vector2:
	return Vector2(352, 416)


func _generate_map() -> void:
	# Layout key:
	# W = perimeter wall (brick boundary)
	# H = building walls (impassable brick structures)
	# I = inn (The Cog & Pillow)
	# B = blacksmith (Gearwright's Forge)
	# p = cobblestone path (market streets)
	# d = village dirt (worn cobble, back alleys)
	# f = flower bed (gas lamp bases / decorative grates)
	# e = hedge (iron fence / pipe railing, impassable)
	# F = water (gear-shaped fountain basin)
	# g = village grass (scrubby patches between buildings)
	# X = exit path (cobblestone gate leading out)
	# Each row is exactly MAP_WIDTH (22) characters
	var map_data: Array[String] = [
		"WWWWWWWWWWWWWWWWWWWWWW",
		"WppfpppppppppppppfpppW",
		"WpHHHppdgggdpBBBppfppW",
		"WpHHHppdgFgdpBBBpppppW",
		"WpHHHppdgFgdpBBBppfppW",
		"WppppppdgggdppppppeppW",
		"WppfpppddddddppppeeppW",
		"WpppIIIpppppppppeeepW",
		"WpppIIIpppppppppeppppW",
		"WpppIIIppfppppppeppppW",
		"WpppppppppppppppppfppW",
		"WpfpppHHHpppppHHHppppW",
		"WppppHHHpppppHHHppfppW",
		"WpppppppppppppppppeppW",
		"WppfpppppppppppppeppppW",
		"WpppppppppppppppppfppW",
		"WppfpppXXXXXXppppppppW",
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

	spawn_points["entrance"] = Vector2(11 * TILE_SIZE, 13 * TILE_SIZE)
	spawn_points["default"] = spawn_points["entrance"]
	spawn_points["brasston_entrance"] = spawn_points["entrance"]


func _char_to_tile_type(char: String) -> int:
	match char:
		"W": return TileGeneratorScript.TileType.WALL
		"H", "I", "B": return TileGeneratorScript.TileType.WALL
		"p": return TileGeneratorScript.TileType.VILLAGE_PATH
		"d": return TileGeneratorScript.TileType.VILLAGE_DIRT
		"f": return TileGeneratorScript.TileType.VILLAGE_FLOWER
		"e": return TileGeneratorScript.TileType.VILLAGE_HEDGE
		"F": return TileGeneratorScript.TileType.WATER
		"g": return TileGeneratorScript.TileType.VILLAGE_GRASS
		"X": return TileGeneratorScript.TileType.VILLAGE_PATH
		_: return TileGeneratorScript.TileType.VILLAGE_PATH


func _get_atlas_coords(tile_type: int) -> Vector2i:
	var tile_id = TileGeneratorScript.get_tile_id(tile_type)
	return Vector2i(tile_id % 5, tile_id / 5)


func _setup_transitions() -> void:
	var exit_trans = AreaTransitionScript.new()
	exit_trans.name = "Exit"
	exit_trans.target_map = "steampunk_overworld"
	exit_trans.target_spawn = "brasston_entrance"
	exit_trans.require_interaction = false
	exit_trans.position = spawn_points.get("exit", Vector2(320, 544))
	_setup_transition_collision(exit_trans, Vector2(TILE_SIZE * 6, TILE_SIZE))
	exit_trans.transition_triggered.connect(_on_transition_triggered)
	transitions.add_child(exit_trans)


func _setup_buildings() -> void:
	# === INN (The Cog & Pillow) ===
	var inn = VillageInnScript.new()
	inn.inn_name = "The Cog & Pillow"
	inn.position = Vector2(4.5 * TILE_SIZE, 8 * TILE_SIZE)
	buildings.add_child(inn)

	# === BLACKSMITH (Gearwright's Forge) ===
	var forge = VillageShopScript.new()
	forge.shop_name = "Gearwright's Forge"
	forge.shop_type = VillageShopScript.ShopType.BLACKSMITH
	forge.keeper_name = "Vesper"
	forge.position = Vector2(14 * TILE_SIZE, 3 * TILE_SIZE)
	buildings.add_child(forge)

	# === ITEM SHOP (Brasston Provisions) ===
	var provisions = VillageShopScript.new()
	provisions.shop_name = "Brasston Provisions"
	provisions.shop_type = VillageShopScript.ShopType.ITEM
	provisions.keeper_name = "Ratchet"
	provisions.position = Vector2(9 * TILE_SIZE, 3 * TILE_SIZE)
	buildings.add_child(provisions)

	# === MAGIC (The Whistling Kettle) ===
	var magic = VillageShopScript.new()
	magic.shop_name = "The Whistling Kettle"
	magic.shop_type = VillageShopScript.ShopType.BLACK_MAGIC
	magic.keeper_name = "Alembic"
	magic.position = Vector2(11 * TILE_SIZE, 8 * TILE_SIZE)
	buildings.add_child(magic)


func _setup_treasures() -> void:
	# Locked gear-box behind the inn — clockwork trinket
	var chest1 = TreasureChestScript.new()
	chest1.chest_id = "brasston_chest_1"
	chest1.contents_type = "item"
	chest1.contents_id = "ether"
	chest1.contents_amount = 2
	chest1.position = Vector2(1.5 * TILE_SIZE, 8 * TILE_SIZE)
	treasures.add_child(chest1)

	# Hidden under market stall corner — merchant's emergency fund
	var chest2 = TreasureChestScript.new()
	chest2.chest_id = "brasston_chest_2"
	chest2.contents_type = "gold"
	chest2.gold_amount = 200
	chest2.position = Vector2(19 * TILE_SIZE, 2 * TILE_SIZE)
	treasures.add_child(chest2)

	# Tucked in the alley behind the clockwork buildings
	var chest3 = TreasureChestScript.new()
	chest3.chest_id = "brasston_chest_3"
	chest3.contents_type = "equipment"
	chest3.contents_id = "lucky_charm"
	chest3.position = Vector2(19 * TILE_SIZE, 12 * TILE_SIZE)
	treasures.add_child(chest3)


func _setup_npcs() -> void:
	# Sprocket the Tinkerer (upgrade hints)
	var sprocket = _create_npc("Sprocket", "villager", Vector2(8 * TILE_SIZE, 5 * TILE_SIZE), [
		"Ahh, a newcomer! Welcome to BRASSTON, city of perpetual motion!",
		"Everything here runs on steam, gears, and sheer stubbornness.",
		"You know, your equipment could be AUGMENTED.",
		"A few modifications and that sword of yours could hum like a turbine.",
		"Vesper at the Forge does excellent work. Tell her Sprocket sent you.",
		"She'll still overcharge you, but at least she'll be polite about it."
	])
	npcs.add_child(sprocket)

	# Lamplighter (night-shift, shadows in the pipes)
	var lamplighter = _create_npc("Clem the Lamplighter", "guard", Vector2(17 * TILE_SIZE, 10 * TILE_SIZE), [
		"I work the night shift. Keeps the gas lamps burning.",
		"Most folk don't notice me. That's fine.",
		"But I notice THINGS. Things in the pipes.",
		"Movements. Echoes. Shadows that go the wrong way.",
		"The engineers say it's 'pressure differentials'.",
		"I say something LIVES down there. Been there since the gears were new."
	])
	npcs.add_child(lamplighter)

	# Steam Merchant (exotic goods)
	var merchant = _create_npc("Madame Orrery", "mysterious", Vector2(10 * TILE_SIZE, 11 * TILE_SIZE), [
		"You have the look of someone who travels between worlds.",
		"Interesting. Most people don't even know there ARE other worlds.",
		"I sell goods from all of them. Steampunk. Suburban. Medieval.",
		"The trick is knowing what a thing is WORTH across realities.",
		"A potion here might be called 'Gatorade' somewhere else.",
		"Same effect, different branding."
	])
	npcs.add_child(merchant)

	# Clockwork Cat (mechanical pet, responds with sound effects)
	var clockcat = _create_npc("Cogsworth", "villager", Vector2(5 * TILE_SIZE, 13 * TILE_SIZE), [
		"*whirr*",
		"*click click*",
		"*purr-tick-purr-tick*",
		"*CLUNK*",
		"*whirr click click whirr*",
		"*settles into idle stance and blinks with a soft ding*"
	])
	npcs.add_child(clockcat)

	# Retired Engineer (city history / exposition)
	var engineer = _create_npc("Brigadier Flux", "elder", Vector2(17 * TILE_SIZE, 5 * TILE_SIZE), [
		"Fifty-three years I served the Brasston Steam Authority.",
		"I BUILT the Great Gear Fountain in the square. By hand. With my own wrenches.",
		"This city was wilderness when I arrived. Mud and shadows.",
		"Now look at it. Pipes and brass as far as the eye can see.",
		"Of course, the pipes have been... making sounds lately.",
		"But I'm retired. That's someone else's problem now."
	])
	npcs.add_child(engineer)
