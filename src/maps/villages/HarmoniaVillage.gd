extends BaseVillage
class_name HarmoniaVillageScene

## HarmoniaVillage - Starter village with full JRPG amenities
## Features: Inn, Shops, Bar with dancer, Fountain, Treasures, NPCs

const VillageInnScript = preload("res://src/exploration/VillageInn.gd")
const VillageShopScript = preload("res://src/exploration/VillageShop.gd")
const VillageBarScript = preload("res://src/exploration/VillageBar.gd")
const TreasureChestScript = preload("res://src/exploration/TreasureChest.gd")
const VillageFountainScript = preload("res://src/exploration/VillageFountain.gd")

## Map dimensions (expanded for full village)
const MAP_WIDTH: int = 30
const MAP_HEIGHT: int = 25


## ---- BaseVillage hooks ----

func _get_area_id() -> String:
	return "harmonia_village"


func _get_village_display_name() -> String:
	return "Harmonia"


func _get_map_pixel_size() -> Vector2i:
	return Vector2i(MAP_WIDTH * TILE_SIZE, MAP_HEIGHT * TILE_SIZE)


func _get_save_point_position() -> Vector2:
	# Near village fountain
	return Vector2(10 * TILE_SIZE, 8 * TILE_SIZE)


func _get_player_spawn_fallback() -> Vector2:
	return Vector2(480, 576)


func _generate_map() -> void:
	# Rich village layout with multiple terrain types:
	# W = stone wall (perimeter), H = house walls (impassable building)
	# I = inn, A = armor/magic shop, P = weapon shop, G = general store, B = bar
	# g = village grass (warm, sun-dappled)
	# p = cobblestone path (walkways between buildings)
	# d = bare dirt (worn areas, market square)
	# f = flower bed (decorative patches)
	# e = hedge (impassable decorative border)
	# F = fountain water
	# X = exit path (cobblestone leading out)
	# Each row is exactly MAP_WIDTH (30) characters
	var map_data: Array[String] = [
		"WWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
		"WgfgpppppggggggggggpppgfgfgggW",
		"WggHHHgdppgfgAAAgddppgggfgfggW",
		"WgfHHHgdppgggAAAggdppgPPPgfggW",
		"WggHHHgdppggfAAAggdppgPPPgfggW",
		"WgggggddpppppppppppppppggfgggW",
		"WgfgggddppFFFFFFggdppggfgfgggW",
		"WggIIIgdppFFFFFFggdppGGGgfgggW",
		"WggIIIgdppFFFFFFggdppGGGggfggW",
		"WgfIIIgdppFFFFFFggdppGGGgfgfgW",
		"WgggggddppFFFFFFggdppgggggfggW",
		"WgfgggddpppppppppppppppgfgfggW",
		"WggggggdppggggfggggggdppggfggW",
		"WgfHHHgdppgfgfggfggdppgBBBfggW",
		"WggHHHgdppggggggggfgdppBBBfggW",
		"WggHHHgdppgfgggggggdppgBBBfggW",
		"WgfggggdpppppppppppppppggfgggW",
		"WgggHHHgdppggfggfgggggggfgfggW",
		"WgfgHHHgdppggggggfggfggfgfgfgW",
		"WgggHHHgdppgfggggggggggfggfggW",
		"WggfggggddpppppppppggfgggfgggW",
		"WgggfgggddppXXXXXXdppggggfgggW",
		"WggggfggddppXXXXXXdppgfgfggggW",
		"WgfgggggdddddddddddppgggfggggW",
		"WWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
	]

	for y in range(MAP_HEIGHT):
		var row = map_data[y] if y < map_data.size() else ""
		for x in range(MAP_WIDTH):
			var char = row[x] if x < row.length() else "W"
			var tile_type = _char_to_tile_type(char)
			var atlas_coords = _get_atlas_coords(tile_type)
			tile_map.set_cell(Vector2i(x, y), 0, atlas_coords)

			# Mark special locations
			if char == "X" and not spawn_points.has("exit"):
				spawn_points["exit"] = Vector2(x * TILE_SIZE + TILE_SIZE / 2, y * TILE_SIZE + TILE_SIZE / 2)

	# Entrance spawn (safe distance from exit)
	spawn_points["entrance"] = Vector2(15 * TILE_SIZE, 18 * TILE_SIZE)
	spawn_points["default"] = spawn_points["entrance"]
	# Bar exit spawn (in front of The Dancing Tonberry)
	spawn_points["bar_exit"] = Vector2(26 * TILE_SIZE, 16 * TILE_SIZE)


func _char_to_tile_type(char: String) -> int:
	match char:
		"W": return TileGeneratorScript.TileType.WALL
		"H", "I", "A", "P", "G", "B": return TileGeneratorScript.TileType.WALL  # Building walls
		"g": return TileGeneratorScript.TileType.VILLAGE_GRASS
		"p": return TileGeneratorScript.TileType.VILLAGE_PATH
		"d": return TileGeneratorScript.TileType.VILLAGE_DIRT
		"f": return TileGeneratorScript.TileType.VILLAGE_FLOWER
		"e": return TileGeneratorScript.TileType.VILLAGE_HEDGE
		"F": return TileGeneratorScript.TileType.WATER
		"X": return TileGeneratorScript.TileType.VILLAGE_PATH  # Exit is also cobblestone
		_: return TileGeneratorScript.TileType.VILLAGE_GRASS


func _get_atlas_coords(tile_type: int) -> Vector2i:
	# Map tile types to atlas coordinates (5-column layout)
	var tile_id = TileGeneratorScript.get_tile_id(tile_type)
	return Vector2i(tile_id % 5, tile_id / 5)


func _setup_transitions() -> void:
	# Exit back to overworld
	var exit_trans = AreaTransitionScript.new()
	exit_trans.name = "Exit"
	exit_trans.target_map = "overworld"
	exit_trans.target_spawn = "village_entrance"
	exit_trans.require_interaction = false  # Auto-exit on touch
	exit_trans.position = spawn_points.get("exit", Vector2(480, 704))
	_setup_transition_collision(exit_trans, Vector2(TILE_SIZE * 6, TILE_SIZE))
	exit_trans.transition_triggered.connect(_on_transition_triggered)
	transitions.add_child(exit_trans)

	# Suburban portal - mysterious glowing teleporter pad
	var suburban_portal = AreaTransitionScript.new()
	suburban_portal.name = "SuburbanPortal"
	suburban_portal.target_map = "suburban_overworld"
	suburban_portal.target_spawn = "entrance"
	suburban_portal.require_interaction = true
	suburban_portal.indicator_text = "Strange Device (90s???)"
	suburban_portal.position = Vector2(20 * TILE_SIZE, 11 * TILE_SIZE)
	_setup_transition_collision(suburban_portal, Vector2(TILE_SIZE, TILE_SIZE))
	suburban_portal.transition_triggered.connect(_on_transition_triggered)
	transitions.add_child(suburban_portal)


func _setup_buildings() -> void:
	# === INN ===
	var inn = VillageInnScript.new()
	inn.inn_name = "Sleepy Slime Inn"
	inn.position = Vector2(3.5 * TILE_SIZE, 8 * TILE_SIZE)
	buildings.add_child(inn)

	# === BLACKSMITH ===
	var blacksmith = VillageShopScript.new()
	blacksmith.shop_name = "Ironclad Arms"
	blacksmith.shop_type = VillageShopScript.ShopType.BLACKSMITH
	blacksmith.keeper_name = "Brutus"
	blacksmith.position = Vector2(25 * TILE_SIZE, 3.5 * TILE_SIZE)
	buildings.add_child(blacksmith)

	# === WHITE MAGIC SHOP ===
	var white_magic_shop = VillageShopScript.new()
	white_magic_shop.shop_name = "Chapel of Light"
	white_magic_shop.shop_type = VillageShopScript.ShopType.WHITE_MAGIC
	white_magic_shop.keeper_name = "Sister Lenora"
	white_magic_shop.position = Vector2(16 * TILE_SIZE, 3.5 * TILE_SIZE)
	buildings.add_child(white_magic_shop)

	# === ITEM SHOP ===
	var item_shop = VillageShopScript.new()
	item_shop.shop_name = "Mystic Remedies"
	item_shop.shop_type = VillageShopScript.ShopType.ITEM
	item_shop.keeper_name = "Willow"
	item_shop.position = Vector2(22 * TILE_SIZE, 8 * TILE_SIZE)
	buildings.add_child(item_shop)

	# === BLACK MAGIC SHOP ===
	var black_magic_shop = VillageShopScript.new()
	black_magic_shop.shop_name = "Mortimer's Arcana"
	black_magic_shop.shop_type = VillageShopScript.ShopType.BLACK_MAGIC
	black_magic_shop.keeper_name = "Mortimer"
	black_magic_shop.position = Vector2(10 * TILE_SIZE, 3.5 * TILE_SIZE)
	buildings.add_child(black_magic_shop)

	# === BAR ===
	var bar = VillageBarScript.new()
	bar.bar_name = "The Dancing Tonberry"
	bar.position = Vector2(26 * TILE_SIZE, 14.5 * TILE_SIZE)
	bar.transition_triggered.connect(_on_transition_triggered)
	buildings.add_child(bar)

	# === FOUNTAIN ===
	var fountain = VillageFountainScript.new()
	fountain.fountain_name = "Harmony Fountain"
	fountain.tree_type = "cherry"
	fountain.position = Vector2(11 * TILE_SIZE, 8 * TILE_SIZE)
	buildings.add_child(fountain)


func _setup_treasures() -> void:
	# Hidden treasure behind house 1 (top left)
	var chest1 = TreasureChestScript.new()
	chest1.chest_id = "harmonia_chest_1"
	chest1.contents_type = "item"
	chest1.contents_id = "potion"
	chest1.contents_amount = 3
	chest1.position = Vector2(1.5 * TILE_SIZE, 4 * TILE_SIZE)
	treasures.add_child(chest1)

	# Treasure near bar
	var chest2 = TreasureChestScript.new()
	chest2.chest_id = "harmonia_chest_2"
	chest2.contents_type = "gold"
	chest2.gold_amount = 150
	chest2.position = Vector2(28 * TILE_SIZE, 13 * TILE_SIZE)
	treasures.add_child(chest2)

	# Treasure behind bottom left house
	var chest3 = TreasureChestScript.new()
	chest3.chest_id = "harmonia_chest_3"
	chest3.contents_type = "item"
	chest3.contents_id = "ether"
	chest3.contents_amount = 2
	chest3.position = Vector2(1.5 * TILE_SIZE, 20 * TILE_SIZE)
	treasures.add_child(chest3)

	# Equipment treasure (hidden corner)
	var chest4 = TreasureChestScript.new()
	chest4.chest_id = "harmonia_chest_4"
	chest4.contents_type = "equipment"
	chest4.contents_id = "lucky_charm"
	chest4.position = Vector2(28 * TILE_SIZE, 1.5 * TILE_SIZE)
	treasures.add_child(chest4)


func _setup_npcs() -> void:
	# === STORY/LORE NPCs ===

	# Village Elder (near fountain)
	var elder = _create_npc("Elder Theron", "elder", Vector2(8 * TILE_SIZE, 6 * TILE_SIZE), [
		"Welcome to Harmonia Village, young adventurer.",
		"Our peaceful village has stood for generations...",
		"But dark rumors spread from the Whispering Cave to the north.",
		"Many brave souls have ventured there... few return.",
		"If you seek glory, be warned: the cave adapts to those who challenge it.",
		"May the light guide your path."
	])
	npcs.add_child(elder)

	# === AUTOBATTLE HINT NPCs ===

	# Scholar (hints about automation)
	var scholar = _create_npc("Scholar Milo", "villager", Vector2(16 * TILE_SIZE, 6 * TILE_SIZE), [
		"Ah, a fellow seeker of knowledge!",
		"I've been studying an ancient art called 'AUTOBATTLE'.",
		"Press F5 or START to open the Autobattle Editor!",
		"You can create rules like 'If HP < 25%, use Potion'.",
		"The system executes your script when it's your turn.",
		"It's not cheating - it's ENLIGHTENMENT!"
	])
	npcs.add_child(scholar)

	# Retired Adventurer (autogrind hints)
	var retired = _create_npc("Greta the Grey", "elder", Vector2(4 * TILE_SIZE, 15 * TILE_SIZE), [
		"*cough* In my day, we ground levels by HAND!",
		"But these young folk... they let the game PLAY ITSELF.",
		"Press F6 or Select to toggle autobattle for everyone!",
		"Some say it's lazy. I say it's WISDOM.",
		"Why waste time when monsters await?",
		"Just... be careful in that cave. It... adapts."
	])
	npcs.add_child(retired)

	# === HUMOROUS NPCs ===

	# Existential Villager
	var existential = _create_npc("Phil the Lost", "villager", Vector2(20 * TILE_SIZE, 16 * TILE_SIZE), [
		"Do you ever wonder if we're just... NPCs?",
		"Standing here... saying the same things...",
		"Waiting for someone to talk to us...",
		"What if there's someone CONTROLLING us?!",
		"...",
		"Nah, that's ridiculous. Carry on!"
	])
	npcs.add_child(existential)

	# Chicken Chaser wannabe
	var chicken = _create_npc("Cluck Norris", "villager", Vector2(6 * TILE_SIZE, 19 * TILE_SIZE), [
		"HAVE YOU SEEN MY CHICKENS?!",
		"They escaped during the last monster attack!",
		"I had SEVENTEEN of them!",
		"...What do you mean 'wrong game'?",
		"Every game needs a chicken guy!",
		"*bawk bawk*"
	])
	npcs.add_child(chicken)

	# Fourth Wall Breaker
	var meta = _create_npc("???", "villager", Vector2(25 * TILE_SIZE, 20 * TILE_SIZE), [
		"Psst... hey... over here...",
		"I know things. SECRET things.",
		"Like how the save file is just JSON.",
		"Or how the monsters in the cave scale with you.",
		"The more you fight, the STRONGER they get.",
		"But also... so do YOU. Funny how that works."
	])
	npcs.add_child(meta)

	# Sleeping NPC
	var sleepy = _create_npc("Zzz...", "villager", Vector2(3.5 * TILE_SIZE, 3 * TILE_SIZE), [
		"Zzz...",
		"Zzz... five more minutes...",
		"Zzz... no... I don't want to fight slimes...",
		"Zzz... automate... the farming...",
		"Zzz... *snore* ...",
		"ZZZ!!!"
	])
	npcs.add_child(sleepy)

	# === HELPFUL NPCs ===

	# Guard near exit
	var guard = _create_npc("Guard Boris", "guard", Vector2(8 * TILE_SIZE, 21 * TILE_SIZE), [
		"Halt! ...Oh, you're heading OUT? Carry on then.",
		"I'm here to keep monsters from getting IN.",
		"The overworld isn't too dangerous...",
		"Slimes, bats, goblins - nothing you can't handle.",
		"But the cave... *shudder* ...don't ask."
	])
	npcs.add_child(guard)

	# Kid by fountain
	var kid = _create_npc("Young Pip", "villager", Vector2(16 * TILE_SIZE, 10 * TILE_SIZE), [
		"Wow! A real adventurer!",
		"I'm gonna be just like you when I grow up!",
		"I practice swinging my stick every day!",
		"Mom says I can't go near the cave though.",
		"Something about 'infinite loops'?",
		"Whatever that means!"
	])
	npcs.add_child(kid)

	# Flower Lady
	var flower = _create_npc("Flora", "villager", Vector2(17 * TILE_SIZE, 12 * TILE_SIZE), [
		"*humming* La la la~",
		"Oh! Would you like to buy some flowers?",
		"...I don't actually sell them. Just ask.",
		"They remind me of the old days.",
		"Before the cave started... changing.",
		"Take care of yourself out there."
	])
	npcs.add_child(flower)

	# === PORTAL GUIDE ===

	# Dr. Temporal (near suburban portal)
	var temporal = _create_npc("Dr. Temporal", "mysterious", Vector2(18 * TILE_SIZE, 11 * TILE_SIZE), [
		"This device materialized overnight... it hums with a '16-bit' frequency.",
		"My instruments detect suburban housing developments on the other side.",
		"Strip malls. Parking lots. The horror.",
		"Step on the pad and press A to activate. If you dare."
	])
	npcs.add_child(temporal)
