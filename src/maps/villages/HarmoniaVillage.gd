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
const MAP_WIDTH: int = 36
const MAP_HEIGHT: int = 30


## ---- BaseVillage hooks ----

func _get_area_id() -> String:
	return "harmonia_village"


func _get_village_display_name() -> String:
	return "Harmonia"


func _get_map_pixel_size() -> Vector2i:
	return Vector2i(MAP_WIDTH * TILE_SIZE, MAP_HEIGHT * TILE_SIZE)


func _get_save_point_position() -> Vector2:
	# Near village fountain
	return Vector2(13 * TILE_SIZE,10 * TILE_SIZE)


func _get_player_spawn_fallback() -> Vector2:
	return Vector2(576, 640)


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
		"WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
		"W..................................W",
		"W..................................W",
		"W...gfgpppppggggggggggpppgfgfggg...W",
		"W...ggHHHgdppgfgAAAgddppgggfgfgg...W",
		"W...gfHHHgdppgggAAAggdppgPPPgfgg...W",
		"W...ggHHHgdppggfAAAggdppgPPPgfgg...W",
		"W...gggggddpppppppppppppppggfggg...W",
		"W...gfgggddppFFFFFFggdppggfgfggg...W",
		"W...ggIIIgdppFFFFFFggdppGGGgfggg...W",
		"W...ggIIIgdppFFFFFFggdppGGGggfgg...W",
		"W...gfIIIgdppFFFFFFggdppGGGgfgfg...W",
		"W...gggggddppFFFFFFggdppgggggfgg...W",
		"W...gfgggddpppppppppppppppgfgfgg...W",
		"W...ggggggdppggggfggggggdppggfgg...W",
		"W...gfHHHgdppgfgfggfggdppgBBBfgg...W",
		"W...ggHHHgdppggggggggfgdppBBBfgg...W",
		"W...ggHHHgdppgfgggggggdppgBBBfgg...W",
		"W...gfggggdpppppppppppppppggfggg...W",
		"W...gggHHHgdppggfggfgggggggfgfgg...W",
		"W...gfgHHHgdppggggggfggfggfgfgfg...W",
		"W...gggHHHgdppgfggggggggggfggfgg...W",
		"W...ggfggggddpppppppppggfgggfggg...W",
		"W...gggfgggddppXXXXXXdppggggfggg...W",
		"W...ggggfggddppXXXXXXdppgfgfgggg...W",
		"W...gfgggggdddddddddddppgggfgggg...W",
		"W..................................W",
		"W..................................W",
		"W..................................W",
		"WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
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
	spawn_points["entrance"] = Vector2(18 * TILE_SIZE,20 * TILE_SIZE)
	spawn_points["default"] = spawn_points["entrance"]
	# Bar exit spawn (in front of The Dancing Tonberry)
	spawn_points["bar_exit"] = Vector2(29 * TILE_SIZE,18 * TILE_SIZE)
	# Chapel exit spawn (in front of the H cluster at columns 3-5, rows 13-15)
	spawn_points["chapel_exit"] = Vector2(7 * TILE_SIZE,18 * TILE_SIZE)
	# Library exit spawn (in front of the top-left H cluster at cols 3-5, rows 2-4)
	spawn_points["library_exit"] = Vector2(7 * TILE_SIZE,7 * TILE_SIZE)
	# Cartographer exit spawn (in front of the top-right PPP cluster at cols 22-24, rows 2-4)
	spawn_points["cartographer_exit"] = Vector2(26 * TILE_SIZE,7 * TILE_SIZE)


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
	exit_trans.position = spawn_points.get("exit", Vector2(576, 768))
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
	forge_entrance.position = Vector2(30 * TILE_SIZE,6 * TILE_SIZE)
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
		suburban_portal.position = Vector2(23 * TILE_SIZE,13 * TILE_SIZE)
		_setup_transition_collision(suburban_portal, Vector2(TILE_SIZE, TILE_SIZE))
		suburban_portal.transition_triggered.connect(_on_transition_triggered)
		transitions.add_child(suburban_portal)


func _setup_buildings() -> void:
	# === INN ===
	var inn = VillageInnScript.new()
	inn.inn_name = "Sleepy Slime Inn"
	inn.position = Vector2(6.5 * TILE_SIZE,10 * TILE_SIZE)
	buildings.add_child(inn)

	# === BLACKSMITH ===
	var blacksmith = VillageShopScript.new()
	blacksmith.shop_name = "Ironclad Arms"
	blacksmith.shop_type = VillageShopScript.ShopType.BLACKSMITH
	blacksmith.keeper_name = "Brutus"
	blacksmith.position = Vector2(28 * TILE_SIZE,5.5 * TILE_SIZE)
	buildings.add_child(blacksmith)

	# === WHITE MAGIC SHOP ===
	var white_magic_shop = VillageShopScript.new()
	white_magic_shop.shop_name = "Chapel of Light"
	white_magic_shop.shop_type = VillageShopScript.ShopType.WHITE_MAGIC
	white_magic_shop.keeper_name = "Sister Lenora"
	white_magic_shop.position = Vector2(19 * TILE_SIZE,5.5 * TILE_SIZE)
	buildings.add_child(white_magic_shop)

	# === ITEM SHOP ===
	var item_shop = VillageShopScript.new()
	item_shop.shop_name = "Mystic Remedies"
	item_shop.shop_type = VillageShopScript.ShopType.ITEM
	item_shop.keeper_name = "Willow"
	item_shop.position = Vector2(25 * TILE_SIZE,10 * TILE_SIZE)
	buildings.add_child(item_shop)

	# === BLACK MAGIC SHOP ===
	var black_magic_shop = VillageShopScript.new()
	black_magic_shop.shop_name = "Mortimer's Arcana"
	black_magic_shop.shop_type = VillageShopScript.ShopType.BLACK_MAGIC
	black_magic_shop.keeper_name = "Mortimer"
	black_magic_shop.position = Vector2(13 * TILE_SIZE,5.5 * TILE_SIZE)
	buildings.add_child(black_magic_shop)

	# === BAR ===
	var bar = VillageBarScript.new()
	bar.bar_name = "The Dancing Tonberry"
	bar.position = Vector2(29 * TILE_SIZE,16.5 * TILE_SIZE)
	bar.transition_triggered.connect(_on_transition_triggered)
	buildings.add_child(bar)

	# === CHAPEL DOOR ===
	# The H cluster at cols 3-5 rows 13-15 is the chapel exterior.
	# Door sits on the south face so the player walks into it from
	# the path at row 16. show_gate_visual draws the archway so the
	# player can SEE there's an interior here.
	_add_interior_door("ChapelDoor", "harmonia_chapel", "Enter Chapel", Vector2(7 * TILE_SIZE,17.5 * TILE_SIZE))
	# === LIBRARY DOOR ===
	# Top-left H cluster (cols 3-5, rows 2-4). Door on the south face
	# at row 4.5 so the player walking on path row 5 hits it.
	_add_interior_door("LibraryDoor", "harmonia_library", "Enter Library", Vector2(7 * TILE_SIZE,6.5 * TILE_SIZE))
	# === CARTOGRAPHER DOOR ===
	# Top-right PPP cluster (cols 22-24, rows 2-4), mirroring the library corner.
	_add_interior_door("CartographerDoor", "harmonia_cartographer", "Enter Attic", Vector2(26 * TILE_SIZE,6.5 * TILE_SIZE))


## tick 37: _add_interior_door moved up to BaseVillage so every village
## can reuse it. Harmonia's calls are unchanged — inheritance does the
## rest.

	# === FOUNTAIN ===
	var fountain = VillageFountainScript.new()
	fountain.fountain_name = "Harmony Fountain"
	fountain.tree_type = "cherry"
	fountain.position = Vector2(14 * TILE_SIZE,10 * TILE_SIZE)
	buildings.add_child(fountain)


func _setup_treasures() -> void:
	# Hidden treasure behind house 1 (top left)
	var chest1 = TreasureChestScript.new()
	chest1.chest_id = "harmonia_chest_1"
	chest1.contents_type = "item"
	chest1.contents_id = "potion"
	chest1.contents_amount = 3
	chest1.position = Vector2(4.5 * TILE_SIZE,6 * TILE_SIZE)
	treasures.add_child(chest1)

	# Treasure near bar
	var chest2 = TreasureChestScript.new()
	chest2.chest_id = "harmonia_chest_2"
	chest2.contents_type = "gold"
	chest2.gold_amount = 150
	chest2.position = Vector2(31 * TILE_SIZE,15 * TILE_SIZE)
	treasures.add_child(chest2)

	# Treasure behind bottom left house
	var chest3 = TreasureChestScript.new()
	chest3.chest_id = "harmonia_chest_3"
	chest3.contents_type = "item"
	chest3.contents_id = "ether"
	chest3.contents_amount = 2
	chest3.position = Vector2(4.5 * TILE_SIZE,22 * TILE_SIZE)
	treasures.add_child(chest3)

	# Equipment treasure (hidden corner)
	var chest4 = TreasureChestScript.new()
	chest4.chest_id = "harmonia_chest_4"
	chest4.contents_type = "equipment"
	chest4.contents_id = "lucky_charm"
	chest4.position = Vector2(31 * TILE_SIZE,3.5 * TILE_SIZE)
	treasures.add_child(chest4)


func _setup_npcs() -> void:
	# Shared post-cave state check — consumed by the Greta / Pip / Flora
	# pre/post branches below. Single lookup so all three read the same
	# GameState at spawn time. Village re-instances on entry, so state
	# refreshes on the next Harmonia visit after world1_harmonia_after_cave
	# has fired. Theron uses his own chapter1 gate (see his block).
	var _after_cave_gs = get_node_or_null("/root/GameState")
	var _after_cave_done: bool = false
	if _after_cave_gs:
		_after_cave_done = bool(_after_cave_gs.game_constants.get("cutscene_flag_world1_harmonia_after_cave_complete", false))

	# === STORY/LORE NPCs ===

	# Village Elder (near fountain)
	# Wave D showcase NPC #1 — lore-load-bearing elder (already gates the
	# W1 prologue via talked_to_theron). Persona text + fallback lines
	# live in data/cutscenes/npc_showcase_personas.json and are hydrated
	# at _ready() via OverworldNPC._setup_persona_data().
	# Pre-chapter1: anticipation hook — no reveals, plant a question the
	# cutscene pays off. The rehearsed-sentence line is the tell; when
	# chapter1's briefing lands ("you'll do" + the changed-monsters beat),
	# the player recognizes it AS the rehearsed thing. Post-chapter1:
	# quiet ambient, no reruns of the briefing, tired-curmudgeon warmth.
	# Branch selects at NPC creation; village scene re-instances on entry
	# so the flag is picked up on the next visit after chapter1 lands.
	var _theron_pre := [
		"Hm. Wait by the square.",
		"There's a thing that needs saying.",
		"I've been rehearsing it, and it only works once."
	]
	var _theron_post := [
		"You've heard the once. I don't do second versions.",
		"Come back when there's something. I'll be sitting."
	]
	var _theron_chapter1_done: bool = false
	var _theron_gs = get_node_or_null("/root/GameState")
	if _theron_gs:
		_theron_chapter1_done = bool(_theron_gs.game_constants.get("cutscene_flag_chapter1_complete", false))
	var elder = _create_npc("Elder Theron", "elder", Vector2(11 * TILE_SIZE,8 * TILE_SIZE), _theron_post if _theron_chapter1_done else _theron_pre)
	elder.dynamic = true
	# Named canon sheet (2fd985bb); must match his staged-cutscene puppet (HARMONIA_NPC_CANON).
	elder.sprite_archetype = "elder_theron"
	npcs.add_child(elder)

	# === AUTOBATTLE HINT NPCs ===

	# Scholar (hints about automation)
	# Wave D showcase NPC #2 — fourth-wall-aware autobattle townie.
	# Persona text + fallback lines hydrated from the same JSON cache.
	var scholar = _create_npc("Scholar Milo", "villager", Vector2(19 * TILE_SIZE,8 * TILE_SIZE), [
		"Ah, a fellow seeker of knowledge!",
		"I've been studying an ancient art called 'AUTOBATTLE'.",
		"Press F5 or START to open the Autobattle Editor!",
		"You can create rules like 'If HP < 25%, use Potion'.",
		"The system executes your script when it's your turn.",
		"It's not cheating - it's ENLIGHTENMENT!"
	])
	scholar.dynamic = true
	# Named canon sheet (2fd985bb); must match his staged-cutscene puppet (HARMONIA_NPC_CANON).
	scholar.sprite_archetype = "scholar_milo"
	npcs.add_child(scholar)

	# Retired Adventurer (autogrind hints)
	# Post-cave: her "be careful, it adapts" pre-warning reads stale after
	# the party has clearly out-adapted it. Post lines carry retired-
	# adventurer respect + a hook to come back for her stashed cave-story.
	var _greta_pre := [
		"*cough* In my day, we ground levels by HAND!",
		"But these young folk... they let the game PLAY ITSELF.",
		"Press F6 or Select to toggle autobattle for everyone!",
		"Some say it's lazy. I say it's WISDOM.",
		"Why waste time when monsters await?",
		"Just... be careful in that cave. It... adapts."
	]
	var _greta_post := [
		"*cough* So it did adapt. And you adapted back. That's not many people's answer to a cave.",
		"In my day we would have said you got lucky. In my day we would have been jealous.",
		"I'm going to sit here with my cough and hope you keep doing what you're doing.",
		"Come back later. I have a story about the cave from *my* year. Now I finally know whether to tell it."
	]
	var retired = _create_npc("Greta the Grey", "elder", Vector2(5 * TILE_SIZE,18 * TILE_SIZE), _greta_post if _after_cave_done else _greta_pre)
	npcs.add_child(retired)

	# === HUMOROUS NPCs ===

	# Existential Villager
	var existential = _create_npc("Phil the Lost", "villager", Vector2(23 * TILE_SIZE,18 * TILE_SIZE), [
		"Do you ever wonder if we're just... NPCs?",
		"Standing here... saying the same things...",
		"Waiting for someone to talk to us...",
		"What if there's someone CONTROLLING us?!",
		"...",
		"Nah, that's ridiculous. Carry on!"
	])
	# Named canon sheet (2fd985bb); must match his staged-cutscene puppet (HARMONIA_NPC_CANON).
	existential.sprite_archetype = "phil"
	npcs.add_child(existential)

	# Chicken Chaser wannabe
	var chicken = _create_npc("Cluck Norris", "villager", Vector2(11 * TILE_SIZE,21 * TILE_SIZE), [
		"HAVE YOU SEEN MY CHICKENS?!",
		"They escaped during the last monster attack!",
		"I had SEVENTEEN of them!",
		"...What do you mean 'wrong game'?",
		"Every game needs a chicken guy!",
		"*bawk bawk*"
	])
	npcs.add_child(chicken)

	# Fourth Wall Breaker
	var meta = _create_npc("???", "villager", Vector2(28 * TILE_SIZE,22 * TILE_SIZE), [
		"Psst... hey... over here...",
		"I know things. SECRET things.",
		"Like how the save file is just JSON.",
		"Or how the monsters in the cave scale with you.",
		"The more you fight, the STRONGER they get.",
		"But also... so do YOU. Funny how that works."
	])
	npcs.add_child(meta)

	# Sleeping NPC
	var sleepy = _create_npc("Zzz...", "villager", Vector2(5 * TILE_SIZE,7 * TILE_SIZE), [
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
	# (foreshadows the Whispering Cave). Persona text hydrated from
	# npc_showcase_personas.json; his `fallbacks[]` was deleted alongside
	# this branching commit (Theron precedent — silent shadow bug: the
	# JSON's fallbacks array unconditionally overrides the constructor's
	# dialogue_lines at _ready). Constructor lines are the sole static
	# source now, LLM-off falls through to them.
	# Post-cave: he shares the "paying attention" theory he refused to
	# share pre-cave (persona: "will not share unless directly pressed").
	# Running-joke update on the running "not paid in eight weeks" —
	# nine weeks now, and it's the vehicle for his gruff thanks.
	var _boris_pre := [
		"Halt! ...Oh, you're heading OUT? Carry on then.",
		"I'm here to keep monsters from getting IN.",
		"The overworld isn't too dangerous...",
		"Slimes, bats, goblins - nothing you can't handle.",
		"But the cave... *shudder* ...don't ask."
	]
	var _boris_post := [
		"You're back. That's not what I expected. It's not what I've been expecting for nineteen years.",
		"The cave was paying attention. It has stopped paying attention to you. I don't know what that means. I don't want to.",
		"Someone should write down what you did in there. That someone will not be me. My hand hurts.",
		"I have not been paid in nine weeks now. But you have my thanks anyway. Which is worth about eight weeks of my back pay.",
		"Halt when you leave next. Just for the ceremony of it."
	]
	var guard = _create_npc("Guard Boris", "guard", Vector2(11 * TILE_SIZE,23 * TILE_SIZE), _boris_post if _after_cave_done else _boris_pre)
	guard.dynamic = true
	npcs.add_child(guard)

	# Kid by fountain
	# Post-cave: child logic of a world-updating claim — his mom's
	# Tuesday quote will have to be revised. The unfinished imaginary
	# swing lands the awe as a body motion, not a sentence.
	var _pip_pre := [
		"Wow! A real adventurer!",
		"I'm gonna be just like you when I grow up!",
		"I practice swinging my stick every day!",
		"Mom says I can't go near the cave though.",
		"Something about 'infinite loops'?",
		"Whatever that means!"
	]
	var _pip_post := [
		"You did it. You actually went in there.",
		"Mom said nobody had ever come out. She said that on TUESDAY. She'll have to change what she says.",
		"Can I see your sword? *pause* Just the handle. The handle-part. I'm not allowed to touch swords.",
		"I'm gonna go to the cave when I'm older. Just to look at where you were.",
		"Not IN. Just at.",
		"*swings imaginary sword, one time, at nothing*"
	]
	var kid = _create_npc("Young Pip", "villager", Vector2(19 * TILE_SIZE,12 * TILE_SIZE), _pip_post if _after_cave_done else _pip_pre)
	npcs.add_child(kid)

	# === SIDE-QUEST GIVERS (dialogue owned by QuestSystem when quest business exists) ===

	# Farmer Aldwick — one_chicken_problem giver, north fence
	var aldwick = _create_npc("Farmer Aldwick", "farmer", Vector2(10 * TILE_SIZE,4 * TILE_SIZE), [
		"Seven chickens. Seven names. One mistake per name.",
	])
	npcs.add_child(aldwick)

	# one_chicken_problem step-2 puzzle: 4 of the 7 hens roost in Harmonia.
	# (Cave approach + Inn kitchen + the Scriptura Guild carry the other
	# three — the guild hen moved home 2026-07-11; its temp spot here sat
	# inside the Inn wall block and was uncatchable, live playtest find.)
	_place_chicken("chicken_harmonia_market", Vector2(18 * TILE_SIZE,14 * TILE_SIZE))
	_place_chicken("chicken_harmonia_flowerbed", Vector2(29 * TILE_SIZE,4 * TILE_SIZE))
	_place_chicken("chicken_harmonia_backlot", Vector2(6 * TILE_SIZE,21 * TILE_SIZE))
	# The unnamed seventh — beside Phil the Lost at the well. Phil's line lands
	# on catch (the hen keeps returning to him, mirroring Phil to Harmonia).
	_place_chicken("chicken_phil_well", Vector2(24 * TILE_SIZE,18 * TILE_SIZE),
		"Phil: \"It keeps coming back to me. Maybe it knows something.\"")

	# Bram the smith's apprentice — untested_edge giver, by Ironclad Arms
	var bram = _create_npc("Bram Smith", "blacksmith", Vector2(27 * TILE_SIZE,8 * TILE_SIZE), [
		"Master Brutus forges them. I catalogue them. One came BACK.",
	])
	bram.npc_id = "bram_smith"
	# Named canon sheet (2fd985bb); must match his staged-cutscene puppet (HARMONIA_NPC_CANON).
	bram.sprite_archetype = "bram"
	npcs.add_child(bram)

	# The Returned Sword on its rack beside Bram (untested_edge step-2
	# emitter, Mage light-spell path; the Guild-scholar path is the alt).
	var SwordScript = load("res://src/exploration/SwordInscription.gd")
	if SwordScript:
		var sword = SwordScript.new()
		sword.position = Vector2(29 * TILE_SIZE,8 * TILE_SIZE)
		npcs.add_child(sword)

	# Rowan the courier — word_from_capital giver, by the fountain square
	var rowan = _create_npc("Rowan", "traveler", Vector2(16 * TILE_SIZE,7 * TILE_SIZE), [
		"A letter for Scriptura. No stamp, no seal, no sender. Typical.",
	])
	rowan.npc_id = "rowan_harmonia"
	npcs.add_child(rowan)

	# Flower Lady
	# Post-cave: the world REACTS. Her flowers opened for the first time
	# in weeks. Object-doing-exposition beat that echoes leaning_ember
	# (Ironhaven) — small things in Harmonia start reacting to the
	# resolution the party made in the cave.
	var _flora_pre := [
		"*humming* La la la~",
		"Oh! Would you like to buy some flowers?",
		"...I don't actually sell them. Just ask.",
		"They remind me of the old days.",
		"Before the cave started... changing.",
		"Take care of yourself out there."
	]
	var _flora_post := [
		"Oh — you're back! *the humming trails off, then picks back up softly*",
		"The cave changed. Whatever you did, the cave changed *again*.",
		"I picked these ones this morning. They opened. They haven't opened in weeks.",
		"You can have one. They mean more when they cost nothing.",
		"Take care of yourself. The story isn't finished."
	]
	var flower = _create_npc("Flora", "villager", Vector2(20 * TILE_SIZE,14 * TILE_SIZE), _flora_post if _after_cave_done else _flora_pre)
	npcs.add_child(flower)

	# === PORTAL GUIDE ===

	# Dr. Temporal (near suburban portal) — uses dedicated sprite_archetype
	# rather than the generic "mysterious" NPC type so other mysterious NPCs
	# (if any) keep their procedural fallback.
	var temporal = _create_npc("Dr. Temporal", "mysterious", Vector2(21 * TILE_SIZE,13 * TILE_SIZE), [
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
		Vector2(16 * TILE_SIZE,13 * TILE_SIZE),
		Vector2(23 * TILE_SIZE,13 * TILE_SIZE),
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
		Vector2(14 * TILE_SIZE,7 * TILE_SIZE),
		Vector2(23 * TILE_SIZE,7 * TILE_SIZE),
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
		Vector2(16 * TILE_SIZE,18 * TILE_SIZE),
		Vector2(23 * TILE_SIZE,18 * TILE_SIZE),
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
