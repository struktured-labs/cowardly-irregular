extends BaseVillage
class_name SandriftVillageScene

## SandriftVillage - Nomad camp/oasis in the southwestern desert
## Features: Oasis Inn, Bazaar (items+weapons), Nomad Elder's Tent

const VillageInnScript = preload("res://src/exploration/VillageInn.gd")
const VillageShopScript = preload("res://src/exploration/VillageShop.gd")
const TreasureChestScript = preload("res://src/exploration/TreasureChest.gd")

## Map dimensions (24x18 desert oasis)
const MAP_WIDTH: int = 30
const MAP_HEIGHT: int = 22


## ---- BaseVillage hooks ----

func _get_area_id() -> String:
	return "sandrift_village"


func _get_village_display_name() -> String:
	return "Sandrift"


func _get_map_pixel_size() -> Vector2i:
	return Vector2i(MAP_WIDTH * TILE_SIZE, MAP_HEIGHT * TILE_SIZE)


func _get_save_point_position() -> Vector2:
	return Vector2(13 * TILE_SIZE,10 * TILE_SIZE)


func _get_player_spawn_fallback() -> Vector2:
	return Vector2(480, 480)


func _generate_map() -> void:
	# Sandrift layout: desert oasis with tents and bazaar
	# W = wall, . = floor (sand base), O = oasis water, I = oasis inn, B = bazaar, E = elder tent
	# T = hidden tent, X = exit
	var map_data: Array[String] = [
		"WWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
		"W............................W",
		"W............................W",
		"W............................W",
		"W.....III.......BBB..........W",
		"W.....III.......BBB..........W",
		"W.....III.......BBB..........W",
		"W............................W",
		"W..........OOOO..............W",
		"W..........OOOO...EEE........W",
		"W..........OOOO...EEE........W",
		"W..........OOOO...EEE........W",
		"W............................W",
		"W.....TT.....................W",
		"W.....TT.....................W",
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

	spawn_points["entrance"] = Vector2(15 * TILE_SIZE,15 * TILE_SIZE)
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
	exit_trans.position = spawn_points.get("exit", Vector2(448, 576))
	_setup_transition_collision(exit_trans, Vector2(TILE_SIZE * 6, TILE_SIZE))
	exit_trans.transition_triggered.connect(_on_transition_triggered)
	transitions.add_child(exit_trans)


func _setup_buildings() -> void:
	# === OASIS INN ===
	var inn = VillageInnScript.new()
	inn.inn_name = "Oasis Inn"
	inn.position = Vector2(6.5 * TILE_SIZE,5 * TILE_SIZE)
	buildings.add_child(inn)

	# === BAZAAR (Item + Weapon Shop) ===
	var bazaar_items = VillageShopScript.new()
	bazaar_items.shop_name = "Desert Bazaar"
	bazaar_items.shop_type = VillageShopScript.ShopType.ITEM
	bazaar_items.keeper_name = "Shifty"
	bazaar_items.position = Vector2(17 * TILE_SIZE,5 * TILE_SIZE)
	buildings.add_child(bazaar_items)

	var bazaar_weapons = VillageShopScript.new()
	bazaar_weapons.shop_name = "Bazaar Arms"
	bazaar_weapons.shop_type = VillageShopScript.ShopType.BLACKSMITH
	bazaar_weapons.keeper_name = "Dune"
	bazaar_weapons.position = Vector2(17 * TILE_SIZE,7.5 * TILE_SIZE)
	buildings.add_child(bazaar_weapons)

	# === GLASSMAKER'S WORKSHOP DOOR ===
	# Senga's hut on the open south-east tundra of the village map.
	# She foreshadows Pyrroth (W1 fire dragon) through the desert
	# glass she collects from sand fused by the dragon's breath.
	spawn_points["glassmaker_exit"] = Vector2(11 * TILE_SIZE,13 * TILE_SIZE)
	_add_interior_door("GlassmakerDoor", "sandrift_glassmaker", "Enter Glassmaker's Workshop", Vector2(11 * TILE_SIZE,12 * TILE_SIZE))
	# === RAIN LEDGER DOOR ===
	# South face of the BBB building (cols 13-15, rows 2-4) — four centuries of hope, one entry.
	spawn_points["ledger_exit"] = Vector2(17 * TILE_SIZE,7.5 * TILE_SIZE)
	_add_interior_door("RainLedgerDoor", "sandrift_rain_ledger", "Enter Rain Ledger", Vector2(17 * TILE_SIZE,6.5 * TILE_SIZE))


func _setup_treasures() -> void:
	# 500 Gold in hidden tent
	var chest1 = TreasureChestScript.new()
	chest1.chest_id = "sandrift_chest_1"
	chest1.contents_type = "gold"
	chest1.gold_amount = 500
	chest1.position = Vector2(5 * TILE_SIZE,14 * TILE_SIZE)
	treasures.add_child(chest1)

	# Speed Boots in bazaar back room
	var chest2 = TreasureChestScript.new()
	chest2.chest_id = "sandrift_chest_2"
	chest2.contents_type = "equipment"
	chest2.contents_id = "speed_boots"
	chest2.position = Vector2(20 * TILE_SIZE,4 * TILE_SIZE)
	treasures.add_child(chest2)


func _setup_npcs() -> void:
	_place_masterite_warden()

	# Shared post-cave state check for Gramps / Dune / Kit branches.
	# Gate = cutscene_flag_rat_king_defeated (set the moment the cave
	# boss falls, before the party leaves the cave). Remote villages
	# hear via travelers/dust-borne rumor — the delay is diegetic. Same
	# spawn-time pattern as Harmonia; village re-instances on entry so
	# state refreshes on next visit. Rex/Shifty/Mirage untouched — their
	# voices are timeless comedy or dragon-lore focused.
	var _after_cave_gs = get_node_or_null("/root/GameState")
	var _after_cave_done: bool = false
	if _after_cave_gs:
		_after_cave_done = bool(_after_cave_gs.game_constants.get("cutscene_flag_rat_king_defeated", false))

	# Conspiracy Theorist Rex (paranoid) — timeless, no cave hook.
	var rex = _create_npc("Conspiracy Theorist Rex", "villager", Vector2(9 * TILE_SIZE,8 * TILE_SIZE), [
		"The encounter rate is RIGGED!",
		"I've done the math. It's supposed to be 5%...",
		"But I SWEAR it's higher when you're low on potions!",
		"It's a CONSPIRACY by the random number generator!",
		"...Don't look at me like that. The RNG has EYES."
	])
	npcs.add_child(rex)

	# Retired Hero Gramps (nostalgic)
	# Post-cave: brief recognition, then reasserts grumpy nostalgia. He
	# still has his grudges. And his badge.
	var _gramps_pre := [
		"Back in MY game, we walked BOTH ways through the dungeon.",
		"Uphill. In 8-bit. And we LIKED it.",
		"No autobattle, no save states, no 'quality of life.'",
		"We had QUALITY OF DEATH and we were GRATEFUL.",
		"Kids these days with their scripts and their 'fun'..."
	]
	var _gramps_post := [
		"You came out of a cave I would not have entered. That's data. I don't like data.",
		"In my day we would have called that reckless. In my day I would have been wrong.",
		"You'll pardon me if I don't hand you the badge. I still have my grudges. And my badge.",
		"Kids these days with their scripts and their... audacity. Fine. Audacity.",
		"Now go do it again. I want to see if it was luck. In my day we needed a second data point."
	]
	var gramps = _create_npc("Retired Hero Gramps", "elder", Vector2(21 * TILE_SIZE,10 * TILE_SIZE), _gramps_post if _after_cave_done else _gramps_pre)
	npcs.add_child(gramps)

	# Script Dealer Shifty (shady) — timeless comedic voice, no branch.
	var shifty = _create_npc("Script Dealer Shifty", "villager", Vector2(19 * TILE_SIZE,8 * TILE_SIZE), [
		"Psst. Got some premium autogrind configs.",
		"One-shot setups. Very efficient.",
		"...Totally not stolen from the dev console.",
		"50 gold each. No refunds. No questions.",
		"And definitely don't tell the Scriptweaver Guild."
	])
	npcs.add_child(shifty)

	# Caravan Leader Dune (practical)
	# Post-cave: the wind on the road has changed. Practical man notices
	# practical shifts. Doesn't overinterpret — but records the data.
	var _dune_pre := [
		"The desert teaches patience.",
		"Also, bring water. Lots of water.",
		"The game doesn't have a thirst mechanic yet, but still.",
		"Better safe than sorry. Or dehydrated."
	]
	var _dune_post := [
		"The road east is quieter. Everything is quieter. I don't know if that means safer or the opposite.",
		"The desert taught me patience. Whatever you did taught the desert. The wind is different this week.",
		"Bring water. Bring some for the road ahead of you and some for what's behind you now.",
		"News moves faster than caravans. It got here two days before it should have. Somebody's carrying it fast."
	]
	var dune = _create_npc("Caravan Leader Dune", "villager", Vector2(13 * TILE_SIZE,12 * TILE_SIZE), _dune_post if _after_cave_done else _dune_pre)
	npcs.add_child(dune)

	# Sand Sage Mirage (cryptic) — dragon-lore focused, no cave branch.
	var mirage = _create_npc("Sand Sage Mirage", "elder", Vector2(8 * TILE_SIZE,16 * TILE_SIZE), [
		"The lightning dragon moves at the speed of thought.",
		"Which, if your thoughts are anything like mine...",
		"...isn't that fast.",
		"It guards the Storm Scale in the desert caves.",
		"Bring rubber boots. Trust me."
	])
	npcs.add_child(mirage)

	# Young Adventurer Kit (enthusiastic)
	# Post-cave: awe + reverent questions. Loops back to Rex ("Did the
	# RNG actually have EYES?") — small cross-NPC comedic thread.
	var _kit_pre := [
		"I'm gonna be the very best!",
		"Like no one ever-- wait, wrong franchise.",
		"I mean, I'm gonna automate the very best!",
		"My autobattle scripts are gonna be LEGENDARY!",
		"...As soon as I figure out how conditions work."
	]
	var _kit_post := [
		"YOU came from the cave? THE CAVE? The one Gramps talks about?",
		"What was it like? Was it like the songs? Were there SIX kinds of skeleton?",
		"I'm gonna write scripts as good as yours someday. My conditions section is getting better. It's still mostly IF-THEN-TRUE though.",
		"Wait. Wait. Did the RNG actually have EYES? I need to go talk to Rex.",
		"Sign my journal? I don't have a journal. Sign my arm. My mom won't mind."
	]
	var kit = _create_npc("Young Adventurer Kit", "villager", Vector2(23 * TILE_SIZE,14 * TILE_SIZE), _kit_post if _after_cave_done else _kit_pre)
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
	warden.position = Vector2(14 * TILE_SIZE,16 * TILE_SIZE)
	npcs.add_child(warden)
