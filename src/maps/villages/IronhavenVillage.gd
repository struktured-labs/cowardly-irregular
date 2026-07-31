extends BaseVillage
class_name IronhavenVillageScene

## IronhavenVillage - Industrial frontier forge town in the volcanic southeast
## Features: Ironclad Inn, Master Forge (weapons), Steamworks (unique), Miner's Tavern

const VillageInnScript = preload("res://src/exploration/VillageInn.gd")
const VillageShopScript = preload("res://src/exploration/VillageShop.gd")
const TreasureChestScript = preload("res://src/exploration/TreasureChest.gd")

## Map dimensions (25x20 industrial town)
const MAP_WIDTH: int = 30
const MAP_HEIGHT: int = 24


## ---- BaseVillage hooks ----

func _get_area_id() -> String:
	return "ironhaven_village"


func _get_village_display_name() -> String:
	return "Ironhaven"


func _get_map_pixel_size() -> Vector2i:
	return Vector2i(MAP_WIDTH * TILE_SIZE, MAP_HEIGHT * TILE_SIZE)


func _get_save_point_position() -> Vector2:
	return Vector2(12 * TILE_SIZE,10 * TILE_SIZE)


func _get_player_spawn_fallback() -> Vector2:
	return Vector2(448, 544)


func _generate_map() -> void:
	# Ironhaven layout: industrial forge town with lava channels
	# W = wall, . = floor, V = lava, I = ironclad inn, F = master forge
	# S = steamworks, M = miner's tavern, X = exit
	var map_data: Array[String] = [
		"WWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
		"W............................W",
		"W............................W",
		"W............................W",
		"W....III.....FFF.............W",
		"W....III.....FFF...SSS.......W",
		"W....III.....FFF...SSS.......W",
		"W............FFF...SSS.......W",
		"W............................W",
		"W...........VVV..............W",
		"W...........VVV..............W",
		"W...........VVV..............W",
		"W............................W",
		"W....MMM.....................W",
		"W....MMM.....................W",
		"W....MMM.....................W",
		"W............................W",
		"W............................W",
		"W............................W",
		"W..........XXXXXX............W",
		"W..........XXXXXX............W",
		"W............................W",
		"W............................W",
		"WWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
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

	spawn_points["entrance"] = Vector2(14 * TILE_SIZE,17 * TILE_SIZE)
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
	exit_trans.position = spawn_points.get("exit", Vector2(448, 640))
	_setup_transition_collision(exit_trans, Vector2(TILE_SIZE * 6, TILE_SIZE))
	exit_trans.transition_triggered.connect(_on_transition_triggered)
	transitions.add_child(exit_trans)


func _setup_buildings() -> void:
	# === IRONCLAD INN ===
	var inn = VillageInnScript.new()
	inn.inn_name = "Ironclad Inn"
	inn.position = Vector2(5.5 * TILE_SIZE,5 * TILE_SIZE)
	buildings.add_child(inn)

	# === MASTER FORGE (Weapon Shop) ===
	var forge = VillageShopScript.new()
	forge.shop_name = "Master Forge"
	forge.shop_type = VillageShopScript.ShopType.BLACKSMITH
	forge.keeper_name = "Magda"
	forge.position = Vector2(14.5 * TILE_SIZE,6 * TILE_SIZE)
	buildings.add_child(forge)

	# === STEAMWORKS (Item Shop - unique tech items) ===
	var steamworks = VillageShopScript.new()
	steamworks.shop_name = "Steamworks"
	steamworks.shop_type = VillageShopScript.ShopType.ITEM
	steamworks.keeper_name = "Dr. Cog"
	steamworks.position = Vector2(22 * TILE_SIZE,6 * TILE_SIZE)
	buildings.add_child(steamworks)

	# === MINER'S TAVERN ===
	var tavern = VillageInnScript.new()
	tavern.inn_name = "Miner's Tavern"
	tavern.position = Vector2(5.5 * TILE_SIZE,14 * TILE_SIZE)
	buildings.add_child(tavern)

	# === STORM WATCHTOWER DOOR ===
	# Drogal's tower on the open eastern side of the village. He
	# foreshadows Voltharion — the last of the four W1 dragons to
	# get an interior NPC.
	spawn_points["watchtower_exit"] = Vector2(20 * TILE_SIZE,14 * TILE_SIZE)
	_add_interior_door("WatchtowerDoor", "ironhaven_watchtower", "Enter Storm Watchtower", Vector2(20 * TILE_SIZE,13 * TILE_SIZE))
	# === STRIKE REGISTRY DOOR ===
	# South face of the MMM building (cols 3-5, rows 11-13) — lightning paperwork.
	spawn_points["registry_exit"] = Vector2(6 * TILE_SIZE,16.5 * TILE_SIZE)
	_add_interior_door("StrikeRegistryDoor", "ironhaven_strike_registry", "Enter Strike Registry", Vector2(6 * TILE_SIZE,15.5 * TILE_SIZE))


func _setup_treasures() -> void:
	# Iron Shield near forge
	var chest1 = TreasureChestScript.new()
	chest1.chest_id = "ironhaven_chest_1"
	chest1.contents_type = "equipment"
	chest1.contents_id = "iron_armor"
	chest1.position = Vector2(12 * TILE_SIZE,4 * TILE_SIZE)
	treasures.add_child(chest1)

	# 3x Hi-Potion in tavern cellar
	var chest2 = TreasureChestScript.new()
	chest2.chest_id = "ironhaven_chest_2"
	chest2.contents_type = "item"
	chest2.contents_id = "hi_potion"
	chest2.contents_amount = 3
	chest2.position = Vector2(3.5 * TILE_SIZE,16 * TILE_SIZE)
	treasures.add_child(chest2)


func _setup_npcs() -> void:
	_place_masterite_curator()

	# Shared post-cave state check for Cog / Bolt / Ember. Same spawn-time
	# pattern as the other four villages; gate = rat_king_defeated.
	# Ironhaven is the automation-philosophy village, so Cog and Bolt's
	# post lines engage the game's actual thesis: neither of them can tell
	# whether the party automated the win or fought it by hand — and the
	# PLAYER knows. The joke lands on the player, not on them.
	# Magda/Pete (dragon-focused), Koss/Stranger (W2 foreshadowing) untouched.
	var _after_cave_gs = get_node_or_null("/root/GameState")
	var _after_cave_done: bool = false
	if _after_cave_gs:
		_after_cave_done = bool(_after_cave_gs.game_constants.get("cutscene_flag_rat_king_defeated", false))

	# Blacksmith Magda (eager)
	var magda = _create_npc("Blacksmith Magda", "villager", Vector2(16 * TILE_SIZE,8 * TILE_SIZE), [
		"Dragon scales, you say?",
		"Oh, I could forge LEGENDARY equipment from those.",
		"Come back with four. Bring receipts.",
		"I don't accept scales of questionable provenance.",
		"Last guy brought me lizard skin. LIZARD. The audacity."
	])
	npcs.add_child(magda)

	# War Veteran Koss (mysterious)
	var koss = _create_npc("War Veteran Koss", "guard", Vector2(20 * TILE_SIZE,12 * TILE_SIZE), [
		"I've seen what lies beyond the southern gate.",
		"Concrete. Streetlights. ...Saxophone music.",
		"The future is WEIRD.",
		"If you go south, bring earplugs.",
		"And maybe a map. The streets don't make sense."
	])
	npcs.add_child(koss)

	# Automation Researcher Dr. Cog (philosophical)
	# Post-cave: he asks the game's actual question and cannot answer it —
	# did the party fight, or did their rules fight? He can't tell about
	# them because he can't tell about himself. Inverts his pre-line's
	# "Hypothesis confirmed."
	var _cog_pre := [
		"What if the NPCs could automate too?",
		"What if I already HAVE and this dialogue is just my script running?",
		"...Hypothesis confirmed.",
		"I've been running my own autobattle scripts for YEARS.",
		"My dialogue tree is fully optimized. You're in the fast path."
	]
	var _cog_post := [
		"You beat the thing in the cave. I have a question and it is not a polite one.",
		"Did YOU fight it, or did your rules fight it? Do you know? Can you tell?",
		"I ask because I have never once been able to tell about myself.",
		"...My script says change the subject here. Watch. How about this weather.",
		"Hypothesis unconfirmed. Hypothesis, in fact, worse."
	]
	var cog = _create_npc("Dr. Cog", "villager", Vector2(23 * TILE_SIZE,8 * TILE_SIZE), _cog_post if _after_cave_done else _cog_pre)
	npcs.add_child(cog)

	# Miner Pete (tired)
	var pete = _create_npc("Miner Pete", "villager", Vector2(8 * TILE_SIZE,12 * TILE_SIZE), [
		"The volcanic caves are brutal.",
		"My pickaxe melted. MY BOOTS melted.",
		"The dragon just laughed.",
		"It breathes fire AND sarcasm.",
		"I'm taking a LONG vacation."
	])
	npcs.add_child(pete)

	# Apprentice Bolt (eager)
	# Post-cave: his thesis lives or dies on how the party won, and they
	# won't say. He counts it anyway, because he needs to. Keeps the gag,
	# lands warmer than it started.
	var _bolt_pre := [
		"I'm building a machine that plays the game FOR you!",
		"...Wait, isn't that just autobattle?",
		"Oh NO.",
		"My entire thesis is redundant.",
		"Well, at least mine has GEARS. That counts for something, right?"
	]
	var _bolt_post := [
		"You did it! Did you use a machine? Please say you used a machine.",
		"...You used RULES. That is sort of a machine. I am counting it. I need to count it.",
		"My thesis is back. Provisionally. Pending an answer you have not actually given me.",
		"It still has gears, though. Nothing you did had gears.",
		"That is what I have. Gears. It is not nothing."
	]
	var bolt = _create_npc("Apprentice Bolt", "villager", Vector2(10 * TILE_SIZE,16 * TILE_SIZE), _bolt_post if _after_cave_done else _bolt_pre)
	npcs.add_child(bolt)

	# Barkeep Ember (warm)
	# Post-cave: the "last inn before" framing means she watches people go
	# and mostly not come back. Her warmth gets a ledger under it — same
	# structure as Boris's gate, opposite temperature.
	var _ember_pre := [
		"Welcome to the last inn before the fire cave.",
		"We serve drinks and existential dread.",
		"Both are on the house.",
		"The special today is 'Lava Lager.' It's... warm.",
		"Like, REALLY warm. We haven't figured out cooling yet."
	]
	var _ember_post := [
		"You came back. Sit. First one's free — so is the second, the sign is a formality.",
		"I keep a list of everyone who walks past here toward a cave. It has two columns.",
		"You moved columns. Most people don't move columns.",
		"I don't like keeping the list. I keep it anyway. Somebody should.",
		"Lava Lager's still warm. Everything here is warm. You're the good kind today."
	]
	var ember = _create_npc("Barkeep Ember", "villager", Vector2(6 * TILE_SIZE,16 * TILE_SIZE), _ember_post if _after_cave_done else _ember_pre)
	npcs.add_child(ember)

	# Mysterious Stranger (foreshadowing)
	var stranger = _create_npc("Mysterious Stranger", "villager", Vector2(22 * TILE_SIZE,18 * TILE_SIZE), [
		"The portal to the south...",
		"It leads to a place where magic runs on coal...",
		"And dreams run on rails.",
		"Are you ready?",
		"...Don't answer that. It was rhetorical. Also, probably no."
	])
	npcs.add_child(stranger)

	# Temple Keeper Sella — flame_speaks_wrong giver, west of the forge temple block.
	var sella = _create_npc("Temple Keeper Sella", "elder", Vector2(12 * TILE_SIZE,6 * TILE_SIZE), [
		"Six hundred years it burned straight up. Three weeks ago it started to lean.",
		"East. Precisely east. Not a draft — a draft wanders. This does not wander.",
		"A flame with a direction has an opinion. I don't know who gave it one.",
		"And there's a woman tending it now. Nobody appointed her. She was simply there.",
	])
	# Without this the quest is UNSTARTABLE — QuestSystem.gd:125 matches npc_id to giver.npc_id.
	sella.npc_id = "temple_keeper_sella"
	npcs.add_child(sella)

	_add_quest_examine_point("w1_ironhaven_flame_speaks_wrong",
		"quest_w1_ironhaven_flame_speaks_wrong_accepted", "[A] Listen to the flame",
		"It leans east, and it SPEAKS — fragments, in a measured beat. Not a flame's cadence. A court's.",
		"Six hundred years it burned straight up. Now it leans, and the lean has a direction.",
		Vector2(16 * TILE_SIZE,4 * TILE_SIZE))


## Curator of the Flame — L8 masterite tending the warped temple flame in
## a duel-of-belief encounter. Placed south of the FFF temple block on the
## approach walkway. Doc: docs/design/w1-progression-expansion.md.
func _place_masterite_curator() -> void:
	var MasteriteScript = load("res://src/exploration/MasteriteEncounter.gd")
	if MasteriteScript == null:
		return
	var curator = MasteriteScript.new()
	curator.archetype = "curator"
	curator.monster_id = "masterite_curator_medieval"
	curator.display_name = "Curator of the Flame"
	curator.quest_flag = "quest_w1_ironhaven_flame_heard"
	curator.position = Vector2(14 * TILE_SIZE,8 * TILE_SIZE)
	npcs.add_child(curator)
