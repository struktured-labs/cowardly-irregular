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
	# Chapel exit spawn (in front of the H cluster at columns 3-5, rows 13-15)
	spawn_points["chapel_exit"] = Vector2(4 * TILE_SIZE, 16 * TILE_SIZE)
	# Library exit spawn (in front of the top-left H cluster at cols 3-5, rows 2-4)
	spawn_points["library_exit"] = Vector2(4 * TILE_SIZE, 5 * TILE_SIZE)
	# Cartographer exit spawn (in front of the top-right PPP cluster at cols 22-24, rows 2-4)
	spawn_points["cartographer_exit"] = Vector2(23 * TILE_SIZE, 5 * TILE_SIZE)


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

	# Rear entrance to the working forge behind Ironclad Arms — the
	# atmospheric BlacksmithInterior scene, not the shop buy-menu.
	var forge_entrance = AreaTransitionScript.new()
	forge_entrance.name = "ForgeEntrance"
	forge_entrance.target_map = "blacksmith_interior"
	forge_entrance.target_spawn = "entrance"
	forge_entrance.require_interaction = true
	forge_entrance.indicator_text = "The Forge (rear entrance)"
	forge_entrance.position = Vector2(27 * TILE_SIZE, 4 * TILE_SIZE)
	_setup_transition_collision(forge_entrance, Vector2(TILE_SIZE, TILE_SIZE))
	forge_entrance.transition_triggered.connect(_on_transition_triggered)
	transitions.add_child(forge_entrance)

	# Suburban portal — only spawned after W1 final boss (Mordaine) is defeated.
	var gs = get_node_or_null("/root/GameState")
	# Tick 335: dual-namespace check via is_story_flag_set — same rationale
	# as the OverworldScene Castle Harmonia gate. Pre-fix bare
	# get_story_flag would silently fail to spawn the Suburban portal
	# if w1_boss_defeated lived only in game_constants.
	if gs and gs.has_method("is_story_flag_set") and gs.is_story_flag_set("w1_boss_defeated"):
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

	# === CHAPEL DOOR ===
	# The H cluster at cols 3-5 rows 13-15 is the chapel exterior.
	# Door sits on the south face so the player walks into it from
	# the path at row 16. show_gate_visual draws the archway so the
	# player can SEE there's an interior here.
	_add_interior_door("ChapelDoor", "harmonia_chapel", "Enter Chapel", Vector2(4 * TILE_SIZE, 15.5 * TILE_SIZE))
	# === LIBRARY DOOR ===
	# Top-left H cluster (cols 3-5, rows 2-4). Door on the south face
	# at row 4.5 so the player walking on path row 5 hits it.
	_add_interior_door("LibraryDoor", "harmonia_library", "Enter Library", Vector2(4 * TILE_SIZE, 4.5 * TILE_SIZE))
	# === CARTOGRAPHER DOOR ===
	# Top-right PPP cluster (cols 22-24, rows 2-4), mirroring the library corner.
	_add_interior_door("CartographerDoor", "harmonia_cartographer", "Enter Attic", Vector2(23 * TILE_SIZE, 4.5 * TILE_SIZE))


## tick 37: _add_interior_door moved up to BaseVillage so every village
## can reuse it. Harmonia's calls are unchanged — inheritance does the
## rest.

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
	# Wave D showcase NPC #1 — lore-load-bearing elder (already gates the
	# W1 prologue via talked_to_theron). Persona text + fallback lines
	# live in data/cutscenes/npc_showcase_personas.json and are hydrated
	# at _ready() via OverworldNPC._setup_persona_data().
	var elder = _create_npc("Elder Theron", "elder", Vector2(8 * TILE_SIZE, 6 * TILE_SIZE), [
		"Welcome to Harmonia Village, young adventurer.",
		"Our peaceful village has stood for generations...",
		"But dark rumors spread from the Whispering Cave to the north.",
		"Many brave souls have ventured there... few return.",
		"If you seek glory, be warned: the cave adapts to those who challenge it.",
		"May the light guide your path."
	])
	elder.dynamic = true
	npcs.add_child(elder)

	# === AUTOBATTLE HINT NPCs ===

	# Scholar (hints about automation)
	# Wave D showcase NPC #2 — fourth-wall-aware autobattle townie.
	# Persona text + fallback lines hydrated from the same JSON cache.
	var scholar = _create_npc("Scholar Milo", "villager", Vector2(16 * TILE_SIZE, 6 * TILE_SIZE), [
		"Ah, a fellow seeker of knowledge!",
		"I've been studying an ancient art called 'AUTOBATTLE'.",
		"Press F5 or START to open the Autobattle Editor!",
		"You can create rules like 'If HP < 25%, use Potion'.",
		"The system executes your script when it's your turn.",
		"It's not cheating - it's ENLIGHTENMENT!"
	])
	scholar.dynamic = true
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
	# Wave D showcase NPC #3 — gruff skeptic guard at the south gate
	# (foreshadows the Whispering Cave). Persona text + fallback lines
	# hydrated from npc_showcase_personas.json.
	var guard = _create_npc("Guard Boris", "guard", Vector2(8 * TILE_SIZE, 21 * TILE_SIZE), [
		"Halt! ...Oh, you're heading OUT? Carry on then.",
		"I'm here to keep monsters from getting IN.",
		"The overworld isn't too dangerous...",
		"Slimes, bats, goblins - nothing you can't handle.",
		"But the cave... *shudder* ...don't ask."
	])
	guard.dynamic = true
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

	# === SIDE-QUEST GIVERS (dialogue owned by QuestSystem when quest business exists) ===

	# Farmer Aldwick — one_chicken_problem giver, north fence
	var aldwick = _create_npc("Farmer Aldwick", "farmer", Vector2(7 * TILE_SIZE, 2 * TILE_SIZE), [
		"Seven chickens. Seven names. One mistake per name.",
	])
	npcs.add_child(aldwick)

	# one_chicken_problem step-2 puzzle: 5 of the 7 hens roost in Harmonia.
	# (cave approach + Inn kitchen carry the other two.) The guild hen is
	# temp-placed here until the Scriptura scene lands, per its wiring note.
	_place_chicken("chicken_harmonia_market", Vector2(15 * TILE_SIZE, 12 * TILE_SIZE))
	_place_chicken("chicken_harmonia_flowerbed", Vector2(26 * TILE_SIZE, 2 * TILE_SIZE))
	_place_chicken("chicken_harmonia_backlot", Vector2(3 * TILE_SIZE, 19 * TILE_SIZE))
	_place_chicken("chicken_guild", Vector2(5 * TILE_SIZE, 8 * TILE_SIZE))
	# The unnamed seventh — beside Phil the Lost at the well. Phil's line lands
	# on catch (the hen keeps returning to him, mirroring Phil to Harmonia).
	_place_chicken("chicken_phil_well", Vector2(21 * TILE_SIZE, 16 * TILE_SIZE),
		"Phil: \"It keeps coming back to me. Maybe it knows something.\"")

	# Bram the smith's apprentice — untested_edge giver, by Ironclad Arms
	var bram = _create_npc("Bram Smith", "blacksmith", Vector2(24 * TILE_SIZE, 6 * TILE_SIZE), [
		"Master Brutus forges them. I catalogue them. One came BACK.",
	])
	bram.npc_id = "bram_smith"
	npcs.add_child(bram)

	# The Returned Sword on its rack beside Bram (untested_edge step-2
	# emitter, Mage light-spell path; the Guild-scholar path is the alt).
	var SwordScript = load("res://src/exploration/SwordInscription.gd")
	if SwordScript:
		var sword = SwordScript.new()
		sword.position = Vector2(26 * TILE_SIZE, 6 * TILE_SIZE)
		npcs.add_child(sword)

	# Rowan the courier — word_from_capital giver, by the fountain square
	var rowan = _create_npc("Rowan", "traveler", Vector2(13 * TILE_SIZE, 7 * TILE_SIZE), [
		"A letter for Scriptura. No stamp, no seal, no sender. Typical.",
	])
	rowan.npc_id = "rowan_harmonia"
	npcs.add_child(rowan)

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

	# Dr. Temporal (near suburban portal) — uses dedicated sprite_archetype
	# rather than the generic "mysterious" NPC type so other mysterious NPCs
	# (if any) keep their procedural fallback.
	var temporal = _create_npc("Dr. Temporal", "mysterious", Vector2(18 * TILE_SIZE, 11 * TILE_SIZE), [
		"This device materialized overnight... it hums with a '16-bit' frequency.",
		"My instruments detect suburban housing developments on the other side.",
		"Strip malls. Parking lots. The horror.",
		"Step on the pad and press A to activate. If you dare."
	])
	temporal.sprite_archetype = "dr_temporal"
	npcs.add_child(temporal)

	# === WANDERING VILLAGERS ===
	# Three ambient NPCs walk short loops to make the village feel lived-in.
	# Each uses a 4-frame walk-cycle archetype shipped in bb60068 (head-locked).
	# Patrol paths chosen to stay on cobblestone rows 5/11/16/20 which are
	# clear of buildings (W/H/I/A/P/G/B/F tiles); WanderingNPC has no
	# collision check, so a path that crosses a wall looks like the NPC
	# is phasing through it. Fixed 2026-05-03 after audit.

	# Wandering merchant — short horizontal patrol on the row-11 path,
	# between the fountain and the right-side path junction.
	var market_loop: Array[Vector2] = [
		Vector2(13 * TILE_SIZE, 11 * TILE_SIZE),
		Vector2(20 * TILE_SIZE, 11 * TILE_SIZE),
	]
	var merchant = _create_wandering_npc(
		"Wandering Merchant",
		"merchant",
		"Wares! Wonders! Wholly unwise purchases!",
		market_loop,
		"merchant",
		"merchant"
	)
	npcs.add_child(merchant)

	# Patrolling guard — north horizontal path at row 5 (clear from x=10
	# through x=20 between the magic / armor shops and the weapon shop).
	var patrol_loop: Array[Vector2] = [
		Vector2(11 * TILE_SIZE, 5 * TILE_SIZE),
		Vector2(20 * TILE_SIZE, 5 * TILE_SIZE),
	]
	var patroller = _create_wandering_npc(
		"Patroller Sven",
		"guard",
		"Eyes peeled, traveler. The world isn't getting safer.",
		patrol_loop,
		"guard",
		"guard"
	)
	npcs.add_child(patroller)

	# Wandering scholar — south horizontal path at row 16, between the
	# bottom-row buildings. Clear path from x=10 through x=22.
	var scholar_loop: Array[Vector2] = [
		Vector2(13 * TILE_SIZE, 16 * TILE_SIZE),
		Vector2(20 * TILE_SIZE, 16 * TILE_SIZE),
	]
	var wandering_scholar = _create_wandering_npc(
		"Apprentice Vex",
		"scholar",
		"Lost my notes again. Have you seen any loose parchment?",
		scholar_loop,
		"scholar",
		"scholar"
	)
	npcs.add_child(wandering_scholar)


## Spawn a QuestChicken for the one_chicken_problem 7-catch puzzle.
func _place_chicken(chicken_id: String, pos: Vector2, catch_line: String = "") -> void:
	var ChickenScript = load("res://src/exploration/QuestChicken.gd")
	if ChickenScript == null:
		return
	var hen = ChickenScript.new()
	hen.chicken_id = chicken_id
	hen.catch_line = catch_line
	hen.position = pos
	npcs.add_child(hen)
