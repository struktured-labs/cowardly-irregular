extends BaseVillage
class_name SandriftVillageScene

## SandriftVillage - Nomad camp/oasis in the southwestern desert
## Features: Oasis Inn, Bazaar (items+weapons), Nomad Elder's Tent

const VillageInnScript = preload("res://src/exploration/VillageInn.gd")
const VillageShopScript = preload("res://src/exploration/VillageShop.gd")
const TreasureChestScript = preload("res://src/exploration/TreasureChest.gd")

## Map dimensions (24x18 desert oasis)
const MAP_WIDTH: int = 24
const MAP_HEIGHT: int = 18


## ---- BaseVillage hooks ----

func _get_area_id() -> String:
	return "sandrift_village"


func _get_village_display_name() -> String:
	return "Sandrift"


func _get_map_pixel_size() -> Vector2i:
	return Vector2i(MAP_WIDTH * TILE_SIZE, MAP_HEIGHT * TILE_SIZE)


func _get_save_point_position() -> Vector2:
	return Vector2(10 * TILE_SIZE, 8 * TILE_SIZE)


func _get_player_spawn_fallback() -> Vector2:
	return Vector2(384, 416)


func _generate_map() -> void:
	# Sandrift layout: desert oasis with tents and bazaar
	# W = wall, . = floor (sand base), O = oasis water, I = oasis inn, B = bazaar, E = elder tent
	# T = hidden tent, X = exit
	var map_data: Array[String] = [
		"WWWWWWWWWWWWWWWWWWWWWWWW",
		"W......................W",
		"W..III.......BBB.......W",
		"W..III.......BBB.......W",
		"W..III.......BBB.......W",
		"W......................W",
		"W.......OOOO...........W",
		"W.......OOOO...EEE.....W",
		"W.......OOOO...EEE.....W",
		"W.......OOOO...EEE.....W",
		"W......................W",
		"W..TT..................W",
		"W..TT..................W",
		"W......................W",
		"W......................W",
		"W.......XXXXXX.........W",
		"W.......XXXXXX.........W",
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

	spawn_points["entrance"] = Vector2(12 * TILE_SIZE, 13 * TILE_SIZE)
	spawn_points["default"] = spawn_points["entrance"]
	spawn_points["sandrift_entrance"] = spawn_points["entrance"]


func _char_to_tile_type(char: String) -> int:
	match char:
		"W": return TileGeneratorScript.TileType.WALL
		"O": return TileGeneratorScript.TileType.WATER
		".": return TileGeneratorScript.TileType.SAND
		_: return TileGeneratorScript.TileType.FLOOR


func _get_atlas_coords(tile_type: int) -> Vector2i:
	var tile_id = TileGeneratorScript.get_tile_id(tile_type)
	return Vector2i(tile_id % 5, tile_id / 5)


func _setup_transitions() -> void:
	var exit_trans = AreaTransitionScript.new()
	exit_trans.name = "Exit"
	exit_trans.target_map = "overworld"
	exit_trans.target_spawn = "sandrift_entrance"
	exit_trans.require_interaction = false
	exit_trans.position = spawn_points.get("exit", Vector2(352, 512))
	_setup_transition_collision(exit_trans, Vector2(TILE_SIZE * 6, TILE_SIZE))
	exit_trans.transition_triggered.connect(_on_transition_triggered)
	transitions.add_child(exit_trans)


func _setup_buildings() -> void:
	# === OASIS INN ===
	var inn = VillageInnScript.new()
	inn.inn_name = "Oasis Inn"
	inn.position = Vector2(3.5 * TILE_SIZE, 3 * TILE_SIZE)
	buildings.add_child(inn)

	# === BAZAAR (Item + Weapon Shop) ===
	var bazaar_items = VillageShopScript.new()
	bazaar_items.shop_name = "Desert Bazaar"
	bazaar_items.shop_type = VillageShopScript.ShopType.ITEM
	bazaar_items.keeper_name = "Shifty"
	bazaar_items.position = Vector2(14 * TILE_SIZE, 3 * TILE_SIZE)
	buildings.add_child(bazaar_items)

	var bazaar_weapons = VillageShopScript.new()
	bazaar_weapons.shop_name = "Bazaar Arms"
	bazaar_weapons.shop_type = VillageShopScript.ShopType.BLACKSMITH
	bazaar_weapons.keeper_name = "Dune"
	bazaar_weapons.position = Vector2(14 * TILE_SIZE, 5.5 * TILE_SIZE)
	buildings.add_child(bazaar_weapons)

	# === GLASSMAKER'S WORKSHOP DOOR ===
	# Senga's hut on the open south-east tundra of the village map.
	# She foreshadows Pyrroth (W1 fire dragon) through the desert
	# glass she collects from sand fused by the dragon's breath.
	spawn_points["glassmaker_exit"] = Vector2(8 * TILE_SIZE, 11 * TILE_SIZE)
	_add_interior_door("GlassmakerDoor", "sandrift_glassmaker", "Enter Glassmaker's Workshop", Vector2(8 * TILE_SIZE, 10 * TILE_SIZE))
	# === RAIN LEDGER DOOR ===
	# South face of the BBB building (cols 13-15, rows 2-4) — four centuries of hope, one entry.
	spawn_points["ledger_exit"] = Vector2(14 * TILE_SIZE, 5.5 * TILE_SIZE)
	_add_interior_door("RainLedgerDoor", "sandrift_rain_ledger", "Enter Rain Ledger", Vector2(14 * TILE_SIZE, 4.5 * TILE_SIZE))


func _setup_treasures() -> void:
	# 500 Gold in hidden tent
	var chest1 = TreasureChestScript.new()
	chest1.chest_id = "sandrift_chest_1"
	chest1.contents_type = "gold"
	chest1.gold_amount = 500
	chest1.position = Vector2(2 * TILE_SIZE, 12 * TILE_SIZE)
	treasures.add_child(chest1)

	# Speed Boots in bazaar back room
	var chest2 = TreasureChestScript.new()
	chest2.chest_id = "sandrift_chest_2"
	chest2.contents_type = "equipment"
	chest2.contents_id = "speed_boots"
	chest2.position = Vector2(17 * TILE_SIZE, 2 * TILE_SIZE)
	treasures.add_child(chest2)


func _setup_npcs() -> void:
	_place_masterite_warden()

	# Conspiracy Theorist Rex (paranoid)
	var rex = _create_npc("Conspiracy Theorist Rex", "villager", Vector2(6 * TILE_SIZE, 6 * TILE_SIZE), [
		"The encounter rate is RIGGED!",
		"I've done the math. It's supposed to be 5%...",
		"But I SWEAR it's higher when you're low on potions!",
		"It's a CONSPIRACY by the random number generator!",
		"...Don't look at me like that. The RNG has EYES."
	])
	npcs.add_child(rex)

	# Retired Hero Gramps (nostalgic)
	var gramps = _create_npc("Retired Hero Gramps", "elder", Vector2(18 * TILE_SIZE, 8 * TILE_SIZE), [
		"Back in MY game, we walked BOTH ways through the dungeon.",
		"Uphill. In 8-bit. And we LIKED it.",
		"No autobattle, no save states, no 'quality of life.'",
		"We had QUALITY OF DEATH and we were GRATEFUL.",
		"Kids these days with their scripts and their 'fun'..."
	])
	npcs.add_child(gramps)

	# Script Dealer Shifty (shady)
	var shifty = _create_npc("Script Dealer Shifty", "villager", Vector2(16 * TILE_SIZE, 6 * TILE_SIZE), [
		"Psst. Got some premium autogrind configs.",
		"One-shot setups. Very efficient.",
		"...Totally not stolen from the dev console.",
		"50 gold each. No refunds. No questions.",
		"And definitely don't tell the Scriptweaver Guild."
	])
	npcs.add_child(shifty)

	# Caravan Leader Dune (practical)
	var dune = _create_npc("Caravan Leader Dune", "villager", Vector2(10 * TILE_SIZE, 10 * TILE_SIZE), [
		"The desert teaches patience.",
		"Also, bring water. Lots of water.",
		"The game doesn't have a thirst mechanic yet, but still.",
		"Better safe than sorry. Or dehydrated."
	])
	npcs.add_child(dune)

	# Sand Sage Mirage (cryptic)
	var mirage = _create_npc("Sand Sage Mirage", "elder", Vector2(5 * TILE_SIZE, 14 * TILE_SIZE), [
		"The lightning dragon moves at the speed of thought.",
		"Which, if your thoughts are anything like mine...",
		"...isn't that fast.",
		"It guards the Storm Scale in the desert caves.",
		"Bring rubber boots. Trust me."
	])
	npcs.add_child(mirage)

	# Young Adventurer Kit (enthusiastic)
	var kit = _create_npc("Young Adventurer Kit", "villager", Vector2(20 * TILE_SIZE, 12 * TILE_SIZE), [
		"I'm gonna be the very best!",
		"Like no one ever-- wait, wrong franchise.",
		"I mean, I'm gonna automate the very best!",
		"My autobattle scripts are gonna be LEGENDARY!",
		"...As soon as I figure out how conditions work."
	])
	npcs.add_child(kit)


## Warden of the Old Guard — L7 masterite blocking the trade road until
## the party can prove "legitimate business" (Rat King defeated). Placement
## on the south exit tile so a first entry post-Harmonia walks straight into
## the encounter. Doc: docs/design/w1-progression-expansion.md.
func _place_masterite_warden() -> void:
	var MasteriteScript = load("res://src/exploration/MasteriteEncounter.gd")
	if MasteriteScript == null:
		return
	var warden = MasteriteScript.new()
	warden.archetype = "warden"
	warden.monster_id = "masterite_warden_medieval"
	warden.prereq_flag = "cave_rat_king_defeated"
	warden.display_name = "Warden of the Old Guard"
	warden.position = Vector2(11 * TILE_SIZE, 14 * TILE_SIZE)
	npcs.add_child(warden)
