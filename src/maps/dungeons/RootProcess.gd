extends DragonCave
class_name RootProcessScene

## Root Process — W5 Digital dungeon.
## Descending through the kernel. Each floor is a cleaner abstraction;
## the bottom is where the Masterite Arbiter decides what gets to exist.

func _init() -> void:
	cave_name = "Root Process"
	cave_id = "root_process"
	boss_id = "masterite_arbiter_futuristic"
	boss_flag_key = "root_process_cleared"
	boss_cutscene_id = "world5_root_process_boss"
	# Tick 103/105: bridge to game_constants so GameLoop's defeat-cutscene
	# gate fires world5_arbiter_defeat after victory return to root_process.
	# (The legacy defeat_cutscene field — read only by the now-removed
	# DragonCave._on_boss_defeated — was deleted in tick 105.)
	defeat_cutscene_flags = ["cutscene_flag_arbiter_futuristic_defeated"]
	total_floors = 4
	overworld_exit_spawn = "glitch_sector"
	overworld_exit_map = "futuristic_overworld"
	unlock_story_flag = "w5_dungeon_cleared"

	# struktured 2026-09-06: 4 floors now — entrance -> wrap floor w/ a cross-floor portal + mimic -> lever-gated vault -> arbiter.
	floor_layouts = {
		1: [
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MM...MMMMMMMMMM...MM",
			"MM.T.MMMMMMMMMM.T.MM",
			"MM...MMMMMMMMMM...MM",
			"MMM.MMMMMMMMMMMM.MMM",
			"M..................M",
			"M..................M",
			"MMMMMMMMM..MMMMMMMMM",
			"MMMMMMMMM.U.MMMMMMMM",
			"MMMMMMMMM...MMMMMMMM",
			"MMMMMMMMM..MMMMMMMMM",
			"M..................M",
			"M.........D........M",
			"M..................M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		2: [
			"....................",
			"....................",
			".........M..........",
			".....D..........b...",
			"....M..........M....",
			"....................",
			"............M.......",
			"..M.......T......M..",
			"....................",
			".......M............",
			"....................",
			"....M..........M....",
			"...b..........U.....",
			".........M..........",
			"....................",
			"....................",
		],
		3: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M..................M",
			"MMMM...............M",
			"MMTM.L.............M",
			"MM.M...M..MM.......M",
			"MMMM...M.U.M.......M",
			"M......M...M.......M",
			"M......M..MM.......M",
			"M....D.............M",
			"M..................M",
			"M..................M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		4: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M..................M",
			"M..................M",
			"M....MMMM..MMMM....M",
			"M....M........M....M",
			"M....M........M....M",
			"M.........B........M",
			"M....M........M....M",
			"M....M........M....M",
			"M....MMMM..MMMM....M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M.........D........M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
	}

	floor_spawn_points = {
		1: {"entrance": Vector2(10, 12)},
		2: {"entrance": Vector2(10, 8)},
		3: {"entrance": Vector2(9, 12)},
		4: {"entrance": Vector2(3, 7)},
	}

	floor_encounter_pools = {
		1: ["rogue_process", "memory_leak"],
		2: ["rogue_process", "memory_leak", "recursive_loop", "data_wraith"],
		3: ["memory_leak", "recursive_loop", "data_wraith"],
		4: [],
	}

	# Floor 2 is edge-wrapping memory; its 'b' pair connects nowhere the geometry implies -- a pointer into the wrong page.
	wrap_floors = [2]
	# sw0 is floor3's lever (5,7) -- flips open the vault door at (3,7). Optional.
	switch_effects = {"sw0": {"flip": [[3, 7]]}}
	trap_chests = ["root_process_f2_c0"]
	forced_item_chests = {
		"root_process_f1_c1": "corrupted_data",
		"root_process_f3_c0": "logic_core",
	}


func _get_boss_intro_dialogue() -> Array:
	return [
		"The textures drop. Polygons become wireframe. Wireframe becomes",
		"ASCII. ASCII becomes pure whitespace.",
		"",
		"A figure resolves at the lowest abstraction layer. Their robe is a",
		"single draw call. Their face is a stack trace.",
		"",
		"Masterite Arbiter: 'I approve what gets to exist.'",
		"Masterite Arbiter: 'You are not on the list.'",
		"",
		"Hero: 'Who made the list?'",
		"",
		"Masterite Arbiter: 'I did. After I was put on the list.'",
		"Masterite Arbiter: 'It's a very efficient list.'",
		"Masterite Arbiter: *opens a terminal*",
		"Masterite Arbiter: 'Running validation on your process...'",
	]


func _get_music_area_id() -> String:
	return "digital_dungeon"


const _LORE := {
	1: [
		{"pos": Vector2(3, 6), "text": "SEGMENTATION FAULT (core dumped somewhere behind you, probably)."},
		{"pos": Vector2(16, 6), "text": "This memory page was freed and reused. You are standing in someone else's variable."},
	],
	2: [
		{"pos": Vector2(10, 5), "text": "0xDEAD0002 -- the portal at the edge of this page dereferences somewhere it was never told to."},
	],
	3: [
		{"pos": Vector2(5, 5), "text": "The lever's label has been garbage-collected. Pull anyway."},
	],
}


func _setup_transitions_for_floor(floor_num: int) -> void:
	super._setup_transitions_for_floor(floor_num)
	for entry in (_LORE.get(floor_num, []) as Array):
		var sign := Signpost.new()
		sign.sign_text = str(entry["text"])
		sign.position = (entry["pos"] as Vector2) * TILE_SIZE
		transitions.add_child(sign)
