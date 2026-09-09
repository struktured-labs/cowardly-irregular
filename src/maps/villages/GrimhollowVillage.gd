extends BaseVillage
class_name GrimhollowVillageScene

## GrimhollowVillage - Haunted hamlet in the northeastern swamps
## Features: Restless Inn, Cursed Curios (items), Decrepit Chapel

const VillageInnScript = preload("res://src/exploration/VillageInn.gd")
const VillageShopScript = preload("res://src/exploration/VillageShop.gd")
const TreasureChestScript = preload("res://src/exploration/TreasureChest.gd")

## Map dimensions (20x16 swamp hamlet)
const MAP_WIDTH: int = 24
const MAP_HEIGHT: int = 20


## ---- BaseVillage hooks ----

func _get_area_id() -> String:
	return "grimhollow_village"


func _get_village_display_name() -> String:
	return "Grimhollow"


func _get_map_pixel_size() -> Vector2i:
	return Vector2i(MAP_WIDTH * TILE_SIZE, MAP_HEIGHT * TILE_SIZE)


func _get_save_point_position() -> Vector2:
	return Vector2(10 * TILE_SIZE,8 * TILE_SIZE)


func _get_player_spawn_fallback() -> Vector2:
	return Vector2(656, 48)


## Empty forces the procedural palette below — medieval.png otherwise wins over it (struktured 2026-09-06 W1 fix)
func _get_cliff_sheet_key() -> String:
	return ""


## Dark mossy stone — struktured 2026-09-06 sunken-hollow elevation pass
func _get_cliff_palette() -> Dictionary:
	return {
		"face_dark": Color(0.10, 0.11, 0.10),
		"face_mid": Color(0.20, 0.24, 0.19),
		"face_light": Color(0.32, 0.38, 0.28),
		"lip": Color(0.55, 0.60, 0.42),
		"lip_shadow": Color(0.08, 0.09, 0.08, 0.85),
		"grass": Color(0.22, 0.34, 0.20),
		"grass_light": Color(0.30, 0.44, 0.26),
		"stair_tread": Color(0.42, 0.46, 0.36),
		"stair_riser": Color(0.18, 0.20, 0.17),
	}


func _generate_map() -> void:
	# Grimhollow layout: dark swamp hamlet, sunken around a spiral descent in the NE corner
	# W = wall, . = floor, S = swamp pools, R = restless inn, C = cursed curios, D = decrepit chapel
	# G = graveyard area, X = exit, / = ramp (spiral descent, cols19-22 rows1-7)
	var map_data: Array[String] = [
		"WWWWWWWWWWWWWWWWWWWWWWWW",
		"W.................W....W",
		"W.................W....W",
		"W.................W..//W",
		"W....RRR....DDD...W....W",
		"W....RRR....DDD...W//..W",
		"W....RRR....DDD...W....W",
		"W....................//W",
		"W.......SS.....CCC.....W",
		"W.......SS.....CCC.....W",
		"W.......SS.....CCC.....W",
		"W......................W",
		"W....GGG...............W",
		"W....GGG...............W",
		"W......................W",
		"W........XXXXXX........W",
		"W........XXXXXX........W",
		"W......................W",
		"W......................W",
		"WWWWWWWWWWWWWWWWWWWWWWWW",
	]
	# Spiral descent (struktured 2026-09-06): rim (3) -> 2 -> 1 -> floor (0), two switchback turns, cols19-22 walled off (col18) from the rest of the floor so the only way down is the ramps — Mort sits at (18,7), one column outside the pit, so shifting the pit to col19+ keeps him clear of the derived cliff face
	var height_data: Array[String] = [
		"000000000000000000000000",
		"000000000000000000033330",
		"000000000000000000033330",
		"000000000000000000022220",
		"000000000000000000022220",
		"000000000000000000011110",
		"000000000000000000011110",
		"000000000000000000000000",
		"000000000000000000000000",
		"000000000000000000000000",
		"000000000000000000000000",
		"000000000000000000000000",
		"000000000000000000000000",
		"000000000000000000000000",
		"000000000000000000000000",
		"000000000000000000000000",
		"000000000000000000000000",
		"000000000000000000000000",
		"000000000000000000000000",
		"000000000000000000000000",
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

	_build_derived_layers(map_data, height_data)

	# Entrance now spawns on the sunken hollow's rim (struktured 2026-09-06); the player spirals down into the floor where the rest of the village lives
	spawn_points["entrance"] = Vector2(20 * TILE_SIZE + TILE_SIZE / 2,1 * TILE_SIZE + TILE_SIZE / 2)
	spawn_points["default"] = spawn_points["entrance"]
	spawn_points["grimhollow_entrance"] = spawn_points["entrance"]


func _char_to_tile_type(char: String) -> int:
	match char:
		"W": return TileGeneratorScript.TileType.WALL
		"S": return TileGeneratorScript.TileType.SWAMP
		"G": return TileGeneratorScript.TileType.DARK_GROUND
		"R": return TileGeneratorScript.TileType.WALL  # restless inn
		"C": return TileGeneratorScript.TileType.WALL  # cursed curios
		"D": return TileGeneratorScript.TileType.WALL  # decrepit chapel
		"X": return TileGeneratorScript.TileType.VILLAGE_PATH  # exit
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
	exit_trans.position = spawn_points.get("exit", Vector2(352, 512))
	_setup_transition_collision(exit_trans, Vector2(TILE_SIZE * 6, TILE_SIZE))
	exit_trans.transition_triggered.connect(_on_transition_triggered)
	transitions.add_child(exit_trans)


func _setup_buildings() -> void:
	# === RESTLESS INN ===
	var inn = VillageInnScript.new()
	inn.inn_name = "The Restless Inn"
	inn.position = Vector2(5.5 * TILE_SIZE,5 * TILE_SIZE)
	buildings.add_child(inn)

	# === CURSED CURIOS (Item Shop) ===
	var curios = VillageShopScript.new()
	curios.shop_name = "Cursed Curios"
	curios.shop_type = VillageShopScript.ShopType.ITEM
	curios.keeper_name = "Mort"
	curios.position = Vector2(17 * TILE_SIZE,9 * TILE_SIZE)
	buildings.add_child(curios)

	# === DECREPIT CHAPEL (Magic Shop) ===
	var chapel = VillageShopScript.new()
	chapel.shop_name = "Decrepit Chapel"
	chapel.shop_type = VillageShopScript.ShopType.BLACK_MAGIC
	chapel.keeper_name = "Sister Shadow"
		# Moved to the building's face 2026-09-09: the shop sat at the block's CENTRE, which was reachable only while the building rendered as walk-through floor.
	chapel.position = Vector2(13 * TILE_SIZE,3 * TILE_SIZE)
	buildings.add_child(chapel)

	# === WITCH'S HUT DOOR ===
	# Old Mire's hut at the bog's edge. She foreshadows Umbraxis (W1
	# shadow dragon) — the room's payload.
	spawn_points["witch_hut_exit"] = Vector2(6 * TILE_SIZE,12 * TILE_SIZE)
	_add_interior_door("WitchHutDoor", "grimhollow_witch_hut", "Enter Witch's Hut", Vector2(6 * TILE_SIZE,11 * TILE_SIZE))
	# === LANTERN DEBT OFFICE DOOR ===
	# South face of the CCC building (cols 13-15, rows 6-8) — where the swamp's light is loaned.
	spawn_points["lantern_exit"] = Vector2(16 * TILE_SIZE,11.5 * TILE_SIZE)
	_add_interior_door("LanternDebtDoor", "grimhollow_lantern_debt", "Enter Lantern Debt Office", Vector2(16 * TILE_SIZE,10.5 * TILE_SIZE))


	# The dark one: lamps are the character here, and the pit head is where the gear sits.
	_add_lamp_post(Vector2i(3, 8))
	_add_lamp_post(Vector2i(17, 13))
	_add_lamp_post(Vector2i(8, 17))
	_add_prop(VillagePropScript.Kind.BARREL, Vector2i(10, 4))
	_add_prop(VillagePropScript.Kind.CRATE, Vector2i(11, 4))
	_add_prop(VillagePropScript.Kind.CART, Vector2i(15, 12))
	_add_prop(VillagePropScript.Kind.CRATE, Vector2i(7, 11))
	_add_prop(VillagePropScript.Kind.BARREL, Vector2i(8, 11))
	_add_prop(VillagePropScript.Kind.FENCE, Vector2i(4, 16))
	_add_prop(VillagePropScript.Kind.FENCE, Vector2i(5, 16))

func _setup_treasures() -> void:
	# Phoenix Down in cemetery
	var chest1 = TreasureChestScript.new()
	chest1.chest_id = "grimhollow_chest_1"
	chest1.contents_type = "item"
	chest1.contents_id = "phoenix_down"
	chest1.contents_amount = 1
	chest1.position = Vector2(3.5 * TILE_SIZE,13 * TILE_SIZE)
	treasures.add_child(chest1)

	# Shadow Ring behind chapel
	var chest2 = TreasureChestScript.new()
	chest2.chest_id = "grimhollow_chest_2"
	chest2.contents_type = "equipment"
	chest2.contents_id = "magic_ring"
	chest2.position = Vector2(16 * TILE_SIZE,4 * TILE_SIZE)
	treasures.add_child(chest2)


func _setup_npcs() -> void:
	_place_masterite_arbiter()

	# Shared post-cave state check for Hex / Mort / Wednesday. Same
	# spawn-time pattern as Sandrift/Eldertree/Harmonia; gate =
	# rat_king_defeated. Claude/Earl/Murk untouched — bar gag, undead-
	# union gag, and shadow-dragon lore respectively, none cave-hooked.
	# Grimhollow's register is deadpan-macabre, NOT solemn: post lines
	# keep the jokes and let the weight land underneath them.
	var _after_cave_gs = get_node_or_null("/root/GameState")
	var _after_cave_done: bool = false
	if _after_cave_gs:
		_after_cave_done = bool(_after_cave_gs.game_constants.get("cutscene_flag_rat_king_defeated", false))

	# Fortune Teller Madame Hex (dramatic)
	# Post-cave: she called it. She calls it every time — but this one
	# LANDED, which gives her a track record and therefore a pricing
	# problem. Joke escalates rather than resolving.
	var _hex_pre := [
		"I see your future...",
		"BOSS FIGHT!",
		"...That's all futures, really.",
		"The cards never lie. They just exaggerate dramatically.",
		"For 50 gold I can tell you which element to use. For free? Good luck."
	]
	var _hex_post := [
		"I SAW this. I said BOSS FIGHT. I was RIGHT.",
		"...I say that to everyone. But this time it was right, and that is different. That is a track record.",
		"The cards never lie, they only exaggerate. This time they UNDER-exaggerated. That has never happened before.",
		"Fifty gold for what comes next. Free preview: another boss fight.",
		"It is always another boss fight. I have raised my prices accordingly."
	]
	var hex = _create_npc("Madame Hex", "elder", Vector2(10 * TILE_SIZE,7 * TILE_SIZE), _hex_post if _after_cave_done else _hex_pre)
	npcs.add_child(hex)

	# Undead Shopkeeper Mort (deadpan)
	# Post-cave: he's the one who went in and didn't come out. Grimhollow
	# handles that the Grimhollow way — flatly, then sells you something.
	var _mort_pre := [
		"Being dead is great for overhead.",
		"No rent, no food costs. 10/10 would die again.",
		"I used to be an adventurer. Then I died.",
		"But the shop needed a keeper, so here I am. Un-retired."
	]
	var _mort_post := [
		"You went into a cave. You came back out of it. Those are two separate achievements and most people manage only the first.",
		"I used to be an adventurer. I did mention. The difference between us is about four feet of cave floor and some luck.",
		"No, I am not bitter. Bitter takes glands.",
		"Buy something. Surviving is expensive and so is not surviving. The dead still have overhead."
	]
	var mort = _create_npc("Undead Shopkeeper Mort", "shopkeeper", Vector2(18 * TILE_SIZE,7 * TILE_SIZE), _mort_post if _after_cave_done else _mort_pre)
	npcs.add_child(mort)

	# Creepy Child Wednesday (meta-horror)
	# Post-cave: she reads the save file, so she is the ONE npc in the
	# game who can diegetically notice a story flag flip. Her post lines
	# describe cutscene_flag_rat_king_defeated going true, in child-
	# horror register, without ever naming the mechanic.
	var _wednesday_pre := [
		"I can see the save file from here.",
		"There's something... WRITTEN between the bytes.",
		"Can you hear it too?",
		"The data whispers your name. And your playtime.",
		"...It says you've been playing for a while. Maybe take a break?"
	]
	var _wednesday_post := [
		"Something changed in the save file. There is a new line. It was not there yesterday.",
		"It says a thing is TRUE that used to be FALSE. Just the one word. Just: true.",
		"I don't know what it turned on. I only know the file is bigger now.",
		"And things that are bigger have more room in them for other things.",
		"...Congratulations, probably? That is usually what a bigger file means."
	]
	var wednesday = _create_npc("Creepy Child Wednesday", "child", Vector2(8 * TILE_SIZE,11 * TILE_SIZE), _wednesday_post if _after_cave_done else _wednesday_pre)
	npcs.add_child(wednesday)

	# Ghost Barkeep Claude (friendly)
	var claude = _create_npc("Ghost Barkeep Claude", "ghost", Vector2(6 * TILE_SIZE,9 * TILE_SIZE), [
		"The usual? One Spectral Ale?",
		"...Oh right, you're alive. That limits the menu.",
		"I can offer water. Ghostly water. It's just regular water.",
		"Being dead has its perks. I never forget an order. Or close up shop."
	])
	npcs.add_child(claude)

	# Nervous Gravedigger Earl (anxious)
	var earl = _create_npc("Gravedigger Earl", "villager", Vector2(5 * TILE_SIZE,14 * TILE_SIZE), [
		"Please don't use Raise on the graves.",
		"Last time someone did that, we had a UNION issue.",
		"The undead demanded dental coverage.",
		"Do you know how much dental costs for someone with NO TEETH?!"
	])
	npcs.add_child(earl)

	# Swamp Witch Murk (warnings)
	var murk = _create_npc("Swamp Witch Murk", "elder", Vector2(14 * TILE_SIZE,12 * TILE_SIZE), [
		"The shadow dragon speaks in null pointers and broken promises.",
		"Fun at parties though.",
		"It lives in the darkest cave to the northeast.",
		"If you hear binary in your dreams... it's already too late.",
		"...Just kidding. Probably."
	])
	npcs.add_child(murk)

	# Miner Trude — foremans_ledger giver, at the mine gate east of the graveyard.
	var trude = _create_npc("Miner Trude", "villager", Vector2(20 * TILE_SIZE,12 * TILE_SIZE), [
		"Three days. He has never once been late coming up.",
		"The foreman's ledger says he was 'reallocated.' I asked what to.",
		"The foreman doesn't know. He didn't write it. He showed me the page — it isn't his hand.",
		"Somebody wrote a word into his book that he can't read, and now my husband is a word.",
	])
	# Without this the quest is UNSTARTABLE — QuestSystem.gd:125 matches npc_id to giver.npc_id.
	trude.npc_id = "miner_trude"
	npcs.add_child(trude)

	_add_quest_examine_point("w1_grimhollow_foremans_ledger",
		"quest_w1_grimhollow_foremans_ledger_accepted", "[A] Read the ledger",
		"'Reallocated.' The word sits in a column that used to say WHERE. Not the foreman's hand — the letters lean like a court clerk's.",
		"The mine office. A ledger lies open, turned to a page nobody here wrote.",
		Vector2(21 * TILE_SIZE,10 * TILE_SIZE))


## Arbiter of Steel — L8 masterite guarding the mine approach as a
## corrupted foreman-cum-judge. Placed south of the CCC block (chapel /
## mine head) so the encounter meets the party on the approach path.
## Doc: docs/design/w1-progression-expansion.md.
func _place_masterite_arbiter() -> void:
	var MasteriteScript = load("res://src/exploration/MasteriteEncounter.gd")
	if MasteriteScript == null:
		return
	var arbiter = MasteriteScript.new()
	arbiter.archetype = "arbiter"
	arbiter.monster_id = "masterite_arbiter_medieval"
	arbiter.display_name = "Arbiter of Steel"
	arbiter.quest_flag = "quest_w1_grimhollow_ledger_read"
	arbiter.position = Vector2(16 * TILE_SIZE,12 * TILE_SIZE)
	npcs.add_child(arbiter)
