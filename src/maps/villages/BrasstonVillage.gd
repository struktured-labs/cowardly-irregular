extends BaseVillage
class_name BrasstonVillageScene

const SteampunkTileGeneratorScript = preload("res://src/exploration/SteampunkTileGenerator.gd")

## BrasstonVillage - Clockwork market town with brass pipes, gas lamps, and gear-shaped fountains
## Features: The Cog & Pillow (Inn), Gearwright's Forge (Blacksmith), Tinkerers, Steam Merchant

const VillageInnScript = preload("res://src/exploration/VillageInn.gd")
const VillageShopScript = preload("res://src/exploration/VillageShop.gd")
const TreasureChestScript = preload("res://src/exploration/TreasureChest.gd")
const VillageElevatorScript = preload("res://src/exploration/VillageElevator.gd")

## Map dimensions
const MAP_WIDTH: int = 26
const MAP_HEIGHT: int = 22


## ---- BaseVillage hooks ----

func _get_area_id() -> String:
	return "brasston_village"


func _get_village_display_name() -> String:
	return "Brasston"


func _get_music_area_id() -> String:
	return "brasston_village"


func _get_map_pixel_size() -> Vector2i:
	return Vector2i(MAP_WIDTH * TILE_SIZE, MAP_HEIGHT * TILE_SIZE)


func _get_save_point_position() -> Vector2:
	return Vector2(10 * TILE_SIZE,10 * TILE_SIZE)


func _get_player_spawn_fallback() -> Vector2:
	return Vector2(416, 480)


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
		"WWWWWWWWWWWWWWWWWWWWWWWWWW",
		"W........................W",
		"W............^^..........W",
		"W..ppfpppppppppppppfppp..W",
		"W..pHHHppdgggdpBBBppfpp..W",
		"W..pHHHppdgFgdpBBBppppp..W",
		"W..pHHHppdgFgdpBBBppfpp..W",
		"W..ppppppdgggdppppppepp..W",
		"W..ppfpppddddddppppeepp..W",
		"W..pppIIIpppppppppeeepW..W",
		"W..pppIIIpppppppppepppp..W",
		"W..pppIIIppfppppppepppp..W",
		"W..pppppppppppppppppfpp..W",
		"W..pfpppHHHpppppHHHpppp..W",
		"W..ppppHHHpppppHHHppfpp..W",
		"W..pppppppppppppppppepp..W",
		"W..ppfpppppppppppppeppp..W",
		"W..pppppppppppppppppfpp..W",
		"W..ppfpppXXXXXXpppppppp..W",
		"W........................W",
		"W........................W",
		"WWWWWWWWWWWWWWWWWWWWWWWWWW",
	]
	# Elevation (CrossCode pass, 2026-09-06): tier 1 is row 1, the Work Deck, a brass catwalk over the market; row 0 matches row 1's digit so the outer wall doesn't paint a spurious lip; row 2 on is tier 0, the mostly-blocked boundary except the '^' stair.
	var height_data: Array[String] = [
		"11111111111111111111111111",
		"11111111111111111111111111",
		"00000000000000000000000000",
		"00000000000000000000000000",
		"00000000000000000000000000",
		"00000000000000000000000000",
		"00000000000000000000000000",
		"00000000000000000000000000",
		"00000000000000000000000000",
		"00000000000000000000000000",
		"00000000000000000000000000",
		"00000000000000000000000000",
		"00000000000000000000000000",
		"00000000000000000000000000",
		"00000000000000000000000000",
		"00000000000000000000000000",
		"00000000000000000000000000",
		"00000000000000000000000000",
		"00000000000000000000000000",
		"00000000000000000000000000",
		"00000000000000000000000000",
		"00000000000000000000000000",
	]

	for y in range(MAP_HEIGHT):
		var row = map_data[y] if y < map_data.size() else ""
		for x in range(MAP_WIDTH):
			var char = row[x] if x < row.length() else "W"
			var tile_type = _char_to_tile_type(char)
			var atlas_coords = _atlas_for(tile_type, Vector2i(x, y))
			tile_map.set_cell(Vector2i(x, y), 0, atlas_coords)

			if char == "X" and not spawn_points.has("exit"):
				spawn_points["exit"] = Vector2(x * TILE_SIZE + TILE_SIZE / 2, y * TILE_SIZE + TILE_SIZE / 2)

	_build_derived_layers(map_data, height_data)

	spawn_points["entrance"] = Vector2(13 * TILE_SIZE,15 * TILE_SIZE)
	spawn_points["default"] = spawn_points["entrance"]
	spawn_points["brasston_entrance"] = spawn_points["entrance"]
	spawn_points["work_deck"] = Vector2(9 * TILE_SIZE + TILE_SIZE / 2, 1 * TILE_SIZE + TILE_SIZE / 2)


## W3 paints with its own world's generator — CrossCode phase 4
func _get_tile_generator() -> Node:
	return SteampunkTileGeneratorScript.new()


func _get_fringe_ground_types() -> Array:
	return [SteampunkTileGeneratorScript.TileType.PARK_GRASS]


## Work Deck cliffs read as riveted brass platform sides, not rock — brass/copper/dark-wood palette.
func _get_cliff_palette() -> Dictionary:
	return {
		"face_dark": Color(0.22, 0.15, 0.09), "face_mid": Color(0.52, 0.36, 0.16), "face_light": Color(0.76, 0.58, 0.28),
		"lip": Color(0.85, 0.68, 0.32), "lip_shadow": Color(0.16, 0.11, 0.06, 0.85),
		"stair_tread": Color(0.62, 0.47, 0.22), "stair_riser": Color(0.30, 0.20, 0.10),
	}


func _char_to_tile_type(char: String) -> int:
	match char:
		"W": return SteampunkTileGeneratorScript.TileType.BUILDING_WALL
		"H", "I", "B": return SteampunkTileGeneratorScript.TileType.BUILDING_WALL
		"p": return SteampunkTileGeneratorScript.TileType.CONCRETE
		"d": return SteampunkTileGeneratorScript.TileType.ASPHALT
		"f": return SteampunkTileGeneratorScript.TileType.PARK_GRASS
		"e": return SteampunkTileGeneratorScript.TileType.FENCE
		"F": return SteampunkTileGeneratorScript.TileType.WATER_FEATURE
		"g": return SteampunkTileGeneratorScript.TileType.PARK_GRASS
		"X": return SteampunkTileGeneratorScript.TileType.CONCRETE
		_: return SteampunkTileGeneratorScript.TileType.CONCRETE


func _setup_transitions() -> void:
	var exit_trans = AreaTransitionScript.new()
	exit_trans.name = "Exit"
	exit_trans.target_map = "steampunk_overworld"
	exit_trans.target_spawn = "brasston_entrance"
	exit_trans.require_interaction = false
	exit_trans.position = spawn_points.get("exit", Vector2(384, 608))
	_setup_transition_collision(exit_trans, Vector2(TILE_SIZE * 6, TILE_SIZE))
	exit_trans.transition_triggered.connect(_on_transition_triggered)
	transitions.add_child(exit_trans)


func _setup_buildings() -> void:
	# === INN (The Cog & Pillow) ===
	var inn = VillageInnScript.new()
	inn.inn_name = "The Cog & Pillow"
	inn.position = Vector2(6.5 * TILE_SIZE,10 * TILE_SIZE)
	buildings.add_child(inn)

	# === BLACKSMITH (Gearwright's Forge) ===
	var forge = VillageShopScript.new()
	forge.shop_name = "Gearwright's Forge"
	forge.shop_type = VillageShopScript.ShopType.BLACKSMITH
	forge.keeper_name = "Vesper"
	forge.position = Vector2(16 * TILE_SIZE,5 * TILE_SIZE)
	buildings.add_child(forge)

	# === ITEM SHOP (Brasston Provisions) ===
	var provisions = VillageShopScript.new()
	provisions.shop_name = "Brasston Provisions"
	provisions.shop_type = VillageShopScript.ShopType.ITEM
	provisions.keeper_name = "Ratchet"
	provisions.position = Vector2(11 * TILE_SIZE,5 * TILE_SIZE)
	buildings.add_child(provisions)

	# === MAGIC (The Whistling Kettle) ===
	var magic = VillageShopScript.new()
	magic.shop_name = "The Whistling Kettle"
	magic.shop_type = VillageShopScript.ShopType.BLACK_MAGIC
	magic.keeper_name = "Alembic"
	magic.position = Vector2(13 * TILE_SIZE,10 * TILE_SIZE)
	buildings.add_child(magic)

	# === CLOCKWORK LOFT DOOR ===
	# Magister Clavis's retired-clockmaker workshop. Foreshadows the
	# SteampunkMechanism dungeon (W3).
	# (7,11) was inside the house block below the door — player spawned in a wall.
	spawn_points["clockwork_loft_exit"] = Vector2(9 * TILE_SIZE + TILE_SIZE / 2, 11 * TILE_SIZE + TILE_SIZE / 2)
	_add_interior_door("ClockworkLoftDoor", "brasston_clockwork_loft", "Enter Clockwork Loft", Vector2(9 * TILE_SIZE,12 * TILE_SIZE))
	# === REDUNDANCY ARCHIVE DOOR ===
	# South face of the BBB building (cols 13-15, rows 2-5) — where Brasston keeps the spares.
	spawn_points["archive_exit"] = Vector2(16 * TILE_SIZE,8.5 * TILE_SIZE)
	_add_interior_door("RedundancyArchiveDoor", "brasston_redundancy_archive", "Enter Redundancy Archive", Vector2(16 * TILE_SIZE,7.5 * TILE_SIZE))

	# === WORK DECK LIFT === brass elevator up to the Work Deck, an alternative to the row2 stair.
	var lift = VillageElevatorScript.create(VillageElevatorScript.Style.BRASS,
		Vector2(9 * TILE_SIZE,3 * TILE_SIZE), Vector2(9 * TILE_SIZE,1 * TILE_SIZE), "steam_hiss")
	lift.name = "WorkDeckLift"
	buildings.add_child(lift)

	# === WORK DECK DRESSING === lamp + crate atop the catwalk, clear of the stair (cols12-13) and lift (col9)
	# Row 1 is the upper ledge and it is ONE tile tall, so a prop there is a wall across it
	_add_lamp_post(Vector2i(5, 2))
	_add_prop(VillagePropScript.Kind.CRATE, Vector2i(20, 2))


func _setup_treasures() -> void:
	# Locked gear-box behind the inn — clockwork trinket
	var chest1 = TreasureChestScript.new()
	chest1.chest_id = "brasston_chest_1"
	chest1.contents_type = "item"
	chest1.contents_id = "ether"
	chest1.contents_amount = 2
	chest1.position = Vector2(3.5 * TILE_SIZE,10 * TILE_SIZE)
	treasures.add_child(chest1)

	# Hidden under market stall corner — merchant's emergency fund
	var chest2 = TreasureChestScript.new()
	chest2.chest_id = "brasston_chest_2"
	chest2.contents_type = "gold"
	chest2.gold_amount = 200
	chest2.position = Vector2(21 * TILE_SIZE,4 * TILE_SIZE)
	treasures.add_child(chest2)

	# Tucked in the alley behind the clockwork buildings
	var chest3 = TreasureChestScript.new()
	chest3.chest_id = "brasston_chest_3"
	chest3.contents_type = "equipment"
	chest3.contents_id = "lucky_charm"
	chest3.position = Vector2(21 * TILE_SIZE,14 * TILE_SIZE)
	treasures.add_child(chest3)


	# End of the upper walkway -- the reward for noticing the stair at all
	var ledge_chest = TreasureChestScript.new()
	ledge_chest.chest_id = "brasston_chest_4"
	ledge_chest.contents_type = "item"
	ledge_chest.contents_id = "elixir"
	ledge_chest.contents_amount = 1
	ledge_chest.position = Vector2(2 * TILE_SIZE,1 * TILE_SIZE)
	treasures.add_child(ledge_chest)

func _setup_npcs() -> void:
	# Sprocket the Tinkerer (upgrade hints)
	var sprocket = _create_npc("Sprocket", "villager", Vector2(10 * TILE_SIZE,7 * TILE_SIZE), [
		"Ahh, a newcomer! Welcome to BRASSTON, city of perpetual motion!",
		"Everything here runs on steam, gears, and sheer stubbornness.",
		"You know, your equipment could be AUGMENTED.",
		"A few modifications and that sword of yours could hum like a turbine.",
		"Vesper at the Forge does excellent work. Tell her Sprocket sent you.",
		"She'll still overcharge you, but at least she'll be polite about it.",
		"You're seven seconds late, by the way. My fault — I didn't allow for the crossing.",
		"Everything here runs on the Grand Schedule. The Regulator set it up. Years ago, or always.",
		"I've spent three years asking who wrote its first rule. The Schedule simply has one."
	])
	# Without this the quest is UNSTARTABLE — QuestSystem matches npc_id to giver.npc_id.
	sprocket.npc_id = "sprocket_brasston"
	npcs.add_child(sprocket)

	# Lamplighter (night-shift, shadows in the pipes)
	var lamplighter = _create_npc("Clem the Lamplighter", "guard", Vector2(19 * TILE_SIZE,12 * TILE_SIZE), [
		"I work the night shift. Keeps the gas lamps burning.",
		"Most folk don't notice me. That's fine.",
		"But I notice THINGS. Things in the pipes.",
		"Movements. Echoes. Shadows that go the wrong way.",
		"The engineers say it's 'pressure differentials'.",
		"I say something LIVES down there. Been there since the gears were new.",
		"I was late once. Seven seconds. The Mechanism compensated — I still don't know how.",
		"Been exactly on time since. Not because I have to be.",
		"Because I want to know whether it's me keeping the Schedule, or the Schedule keeping me."
	])
	# Without this the quest is UNSTARTABLE — QuestSystem matches npc_id to giver.npc_id.
	lamplighter.npc_id = "clem_lamplighter"
	npcs.add_child(lamplighter)

	# Steam Merchant (exotic goods)
	var merchant = _create_npc("Madame Orrery", "mysterious", Vector2(12 * TILE_SIZE,13 * TILE_SIZE), [
		"You have the look of someone who travels between worlds.",
		"Interesting. Most people don't even know there ARE other worlds.",
		"I sell goods from all of them. Steampunk. Suburban. Medieval.",
		"The trick is knowing what a thing is WORTH across realities.",
		"A potion here might be called 'Gatorade' somewhere else.",
		"Same effect, different branding."
	])
	# Without this the quest is UNSTARTABLE — QuestSystem matches npc_id to giver.npc_id.
	merchant.npc_id = "madame_orrery_w3"
	npcs.add_child(merchant)

	# Cornelius Hartwick — before_the_regulator step-3 emitter AND its step-4 turn-in.
	# Alias display name: the notebook's last page is what identifies him, not a puzzle.
	var repairman = _create_npc("Clock Repairman", "villager", Vector2(4 * TILE_SIZE,16 * TILE_SIZE), [
		"Small things only. Clocks, mostly. Nothing that runs the city.",
		"I used to work on something larger. It stopped being mine.",
		"No, I don't take commissions. I fix what people bring me and I don't ask where it came from.",
	])
	repairman.npc_id = "cornelius_hartwick"
	npcs.add_child(repairman)

	_add_quest_examine_point("world3_delay_in_everything",
		"quest_world3_delay_in_everything_gear_examined", "[A] Examine the gear cluster",
		"The replacement gear is one unit too large. Exactly one gear-tooth of lag per cycle — seven seconds, every cycle, for six months. Too precise to be an accident.",
		"A maintenance panel stands open at Sprocket's shoulder. The cluster inside turns a half-beat behind the rest.",
		Vector2(11 * TILE_SIZE,7 * TILE_SIZE))
	_add_quest_examine_point("world3_delay_in_everything",
		"quest_world3_delay_in_everything_record_found", "[A] Read the depot record",
		"The entry is there, in the margin, in a clerk's hand: 'substituted — standard gauge unavailable. Approved: Calibrant Logistics.' The order date precedes the maintenance incident.",
		"The supply depot's ledger, open to a page of part numbers nobody has needed to read in six months.",
		Vector2(13 * TILE_SIZE,14 * TILE_SIZE))

	# Clem's route: 5 stops on the map's own `f` gas-lamp tiles, at the landmarks his offer names
	# (mill, Copper Street twice, skip the arcade, bridge, back to the arcade). Each reads as a
	# local oddity; only Brigadier Flux at step 3 names the shape they make.
	var _lamp_idle := "A gas lamp on Clem's route, unlit at this hour. Its base is grated at the foot."
	_add_quest_route_point("world3_lamplighters_logic",
		"quest_world3_lamplighters_logic_route_documented", 1, 5, "[A] Document the mill lamp",
		"The mill lamp. Its base is warm — warmer than burning gas explains, and warmest on the side facing AWAY from the flame.",
		_lamp_idle, Vector2(5 * TILE_SIZE,3 * TILE_SIZE))
	_add_quest_route_point("world3_lamplighters_logic",
		"quest_world3_lamplighters_logic_route_documented", 2, 5, "[A] Document the Copper Street lamp",
		"Copper Street, east side. The grate at the lamp's foot exhales on a slow count, like something upstream of it is breathing.",
		_lamp_idle, Vector2(20 * TILE_SIZE,4 * TILE_SIZE))
	_add_quest_route_point("world3_lamplighters_logic",
		"quest_world3_lamplighters_logic_route_documented", 3, 5, "[A] Document the second Copper Street lamp",
		"Copper Street again, further down, on the side you started from. The same slow count — offset by exactly the walk between the two.",
		_lamp_idle, Vector2(20 * TILE_SIZE,17 * TILE_SIZE))
	_add_quest_route_point("world3_lamplighters_logic",
		"quest_world3_lamplighters_logic_route_documented", 4, 5, "[A] Document the bridge lamp",
		"The bridge lamp, reached after the arcade is skipped entirely. This base is cold. Cold enough to bead water out of dry air.",
		_lamp_idle, Vector2(5 * TILE_SIZE,8 * TILE_SIZE))
	_add_quest_route_point("world3_lamplighters_logic",
		"quest_world3_lamplighters_logic_route_documented", 5, 5, "[A] Document the arcade lamp",
		"The arcade lamp, come back to last, exactly as Clem said. Warm again — the same warmth as the mill, at the opposite end of town.",
		_lamp_idle, Vector2(5 * TILE_SIZE,18 * TILE_SIZE))

	# Clockwork Cat (mechanical pet, responds with sound effects)
	var clockcat = _create_npc("Cogsworth", "villager", Vector2(7 * TILE_SIZE,15 * TILE_SIZE), [
		"*whirr*",
		"*click click*",
		"*purr-tick-purr-tick*",
		"*CLUNK*",
		"*whirr click click whirr*",
		"*settles into idle stance and blinks with a soft ding*"
	])
	npcs.add_child(clockcat)

	# Retired Engineer (city history / exposition)
	var engineer = _create_npc("Brigadier Flux", "elder", Vector2(19 * TILE_SIZE,7 * TILE_SIZE), [
		"Fifty-three years I served the Brasston Steam Authority.",
		"I BUILT the Great Gear Fountain in the square. By hand. With my own wrenches.",
		"This city was wilderness when I arrived. Mud and shadows.",
		"Now look at it. Pipes and brass as far as the eye can see.",
		"Of course, the pipes have been... making sounds lately.",
		"But I'm retired. That's someone else's problem now."
	])
	npcs.add_child(engineer)
