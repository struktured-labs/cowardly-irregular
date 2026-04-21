extends BaseVillage
class_name GrimhollowVillageScene

## GrimhollowVillage - Haunted hamlet in the northeastern swamps
## Features: Restless Inn, Cursed Curios (items), Decrepit Chapel

const VillageInnScript = preload("res://src/exploration/VillageInn.gd")
const VillageShopScript = preload("res://src/exploration/VillageShop.gd")
const TreasureChestScript = preload("res://src/exploration/TreasureChest.gd")

## Map dimensions (20x16 swamp hamlet)
const MAP_WIDTH: int = 20
const MAP_HEIGHT: int = 16


## ---- BaseVillage hooks ----

func _get_area_id() -> String:
	return "grimhollow_village"


func _get_village_display_name() -> String:
	return "Grimhollow"


func _get_map_pixel_size() -> Vector2i:
	return Vector2i(MAP_WIDTH * TILE_SIZE, MAP_HEIGHT * TILE_SIZE)


func _get_save_point_position() -> Vector2:
	return Vector2(8 * TILE_SIZE, 6 * TILE_SIZE)


func _get_player_spawn_fallback() -> Vector2:
	return Vector2(320, 352)


func _generate_map() -> void:
	# Grimhollow layout: dark swamp hamlet
	# W = wall, . = floor, S = swamp pools, R = restless inn, C = cursed curios, D = decrepit chapel
	# G = graveyard area, X = exit
	var map_data: Array[String] = [
		"WWWWWWWWWWWWWWWWWWWW",
		"W..................W",
		"W..RRR....DDD......W",
		"W..RRR....DDD......W",
		"W..RRR....DDD......W",
		"W..................W",
		"W.....SS.....CCC...W",
		"W.....SS.....CCC...W",
		"W.....SS.....CCC...W",
		"W..................W",
		"W..GGG.............W",
		"W..GGG.............W",
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

	spawn_points["entrance"] = Vector2(10 * TILE_SIZE, 11 * TILE_SIZE)
	spawn_points["default"] = spawn_points["entrance"]
	spawn_points["grimhollow_entrance"] = spawn_points["entrance"]


func _char_to_tile_type(char: String) -> int:
	match char:
		"W": return TileGeneratorScript.TileType.WALL
		"S": return TileGeneratorScript.TileType.SWAMP
		"G": return TileGeneratorScript.TileType.DARK_GROUND
		_: return TileGeneratorScript.TileType.FLOOR


func _get_atlas_coords(tile_type: int) -> Vector2i:
	var tile_id = TileGeneratorScript.get_tile_id(tile_type)
	return Vector2i(tile_id % 5, tile_id / 5)


func _setup_transitions() -> void:
	var exit_trans = AreaTransitionScript.new()
	exit_trans.name = "Exit"
	exit_trans.target_map = "overworld"
	exit_trans.target_spawn = "grimhollow_entrance"
	exit_trans.require_interaction = false
	exit_trans.position = spawn_points.get("exit", Vector2(288, 448))
	_setup_transition_collision(exit_trans, Vector2(TILE_SIZE * 6, TILE_SIZE))
	exit_trans.transition_triggered.connect(_on_transition_triggered)
	transitions.add_child(exit_trans)


func _setup_buildings() -> void:
	# === RESTLESS INN ===
	var inn = VillageInnScript.new()
	inn.inn_name = "The Restless Inn"
	inn.position = Vector2(3.5 * TILE_SIZE, 3 * TILE_SIZE)
	buildings.add_child(inn)

	# === CURSED CURIOS (Item Shop) ===
	var curios = VillageShopScript.new()
	curios.shop_name = "Cursed Curios"
	curios.shop_type = VillageShopScript.ShopType.ITEM
	curios.keeper_name = "Mort"
	curios.position = Vector2(15 * TILE_SIZE, 7 * TILE_SIZE)
	buildings.add_child(curios)

	# === DECREPIT CHAPEL (Magic Shop) ===
	var chapel = VillageShopScript.new()
	chapel.shop_name = "Decrepit Chapel"
	chapel.shop_type = VillageShopScript.ShopType.BLACK_MAGIC
	chapel.keeper_name = "Sister Shadow"
	chapel.position = Vector2(11 * TILE_SIZE, 3 * TILE_SIZE)
	buildings.add_child(chapel)


func _setup_treasures() -> void:
	# Phoenix Down in cemetery
	var chest1 = TreasureChestScript.new()
	chest1.chest_id = "grimhollow_chest_1"
	chest1.contents_type = "item"
	chest1.contents_id = "phoenix_down"
	chest1.contents_amount = 1
	chest1.position = Vector2(1.5 * TILE_SIZE, 11 * TILE_SIZE)
	treasures.add_child(chest1)

	# Shadow Ring behind chapel
	var chest2 = TreasureChestScript.new()
	chest2.chest_id = "grimhollow_chest_2"
	chest2.contents_type = "equipment"
	chest2.contents_id = "shadow_ring"
	chest2.position = Vector2(14 * TILE_SIZE, 2 * TILE_SIZE)
	treasures.add_child(chest2)


func _setup_npcs() -> void:
	# Fortune Teller Madame Hex (dramatic)
	var hex = _create_npc("Madame Hex", "elder", Vector2(8 * TILE_SIZE, 5 * TILE_SIZE), [
		"I see your future...",
		"BOSS FIGHT!",
		"...That's all futures, really.",
		"The cards never lie. They just exaggerate dramatically.",
		"For 50 gold I can tell you which element to use. For free? Good luck."
	])
	npcs.add_child(hex)

	# Undead Shopkeeper Mort (deadpan)
	var mort = _create_npc("Undead Shopkeeper Mort", "villager", Vector2(16 * TILE_SIZE, 5 * TILE_SIZE), [
		"Being dead is great for overhead.",
		"No rent, no food costs. 10/10 would die again.",
		"I used to be an adventurer. Then I died.",
		"But the shop needed a keeper, so here I am. Un-retired."
	])
	npcs.add_child(mort)

	# Creepy Child Wednesday (meta-horror)
	var wednesday = _create_npc("Creepy Child Wednesday", "villager", Vector2(6 * TILE_SIZE, 9 * TILE_SIZE), [
		"I can see the save file from here.",
		"There's something... WRITTEN between the bytes.",
		"Can you hear it too?",
		"The data whispers your name. And your playtime.",
		"...It says you've been playing for a while. Maybe take a break?"
	])
	npcs.add_child(wednesday)

	# Ghost Barkeep Claude (friendly)
	var claude = _create_npc("Ghost Barkeep Claude", "villager", Vector2(4 * TILE_SIZE, 7 * TILE_SIZE), [
		"The usual? One Spectral Ale?",
		"...Oh right, you're alive. That limits the menu.",
		"I can offer water. Ghostly water. It's just regular water.",
		"Being dead has its perks. I never forget an order. Or close up shop."
	])
	npcs.add_child(claude)

	# Nervous Gravedigger Earl (anxious)
	var earl = _create_npc("Gravedigger Earl", "villager", Vector2(3 * TILE_SIZE, 12 * TILE_SIZE), [
		"Please don't use Raise on the graves.",
		"Last time someone did that, we had a UNION issue.",
		"The undead demanded dental coverage.",
		"Do you know how much dental costs for someone with NO TEETH?!"
	])
	npcs.add_child(earl)

	# Swamp Witch Murk (warnings)
	var murk = _create_npc("Swamp Witch Murk", "elder", Vector2(12 * TILE_SIZE, 10 * TILE_SIZE), [
		"The shadow dragon speaks in null pointers and broken promises.",
		"Fun at parties though.",
		"It lives in the darkest cave to the northeast.",
		"If you hear binary in your dreams... it's already too late.",
		"...Just kidding. Probably."
	])
	npcs.add_child(murk)
