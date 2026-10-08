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
	# gate fires this boss's aftermath after victory return to root_process.
	# 2026-09-11: that scene is world4_arbiter_defeat ("Arbiter of the Benchmark —
	# Aftermath"), not world5_arbiter_defeat — the masterite aftermath scenes are
	# filed one world below the boss they belong to, and the gate was wired by
	# filename, so this dungeon played the ABSTRACT Arbiter's scene.
	# (The legacy defeat_cutscene field — read only by the now-removed
	# DragonCave._on_boss_defeated — was deleted in tick 105.)
	defeat_cutscene_flags = ["cutscene_flag_arbiter_futuristic_defeated"]
	total_floors = 4
	overworld_exit_spawn = "from_root"
	overworld_exit_map = "futuristic_overworld"
	unlock_story_flag = "w5_dungeon_cleared"

	# struktured 2026-10-07 ("we need more maze complexity"): entrance maze -> branching kernel-page maze (portal pair + mimic) -> lever-gated vault maze -> arbiter. Corridors are 1-wide throughout; the old wrap-floor/open-hall shape is gone.
	floor_layouts = {
		1: [
			"MMMMMMMMMMMMMMMMMMMM",
			"MU....M.......M....M",
			"MMMMM.M.MMMMM.M.M..M",
			"M.....M...MT....MDMM",
			"M.MMMMM.M.MMM.MMMMMM",
			"M.MTM...M...M.M...MM",
			"M.M.M.MMMMM.MMM.M.MM",
			"M.M.......M.....M.MM",
			"M.MMM.MMM.MMMMMMM.MM",
			"M...M.....M...M...MM",
			"MMM.MMMMM.M.M.M.MMMM",
			"M...M.......M.M...MM",
			"M.MMM.M.MMMMMMMMM.MM",
			"M.................MM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		2: [
			"MMMMMMMMMMMMMMMMMMMM",
			"MU....Mb..........MM",
			"MMMMM.MMM.MMMMM.M.MM",
			"M...M...MbM...MTM.MM",
			"M.M.MMM.MMM.M.MMM.MM",
			"M.M.M...M...M.....MM",
			"MMM.M.MMM.MMMMMMM.MM",
			"M.....M...M...M...MM",
			"M.MMM.M.MMM.M.M.MMMM",
			"M.....M.M.....M.M.MM",
			"M.MMMMM.M.MMM.M.M.MM",
			"M.M.....M.M...M...MM",
			"M.M.MMMMM.M.M.MMM.MM",
			"M...MD......M.....MM",
			"MMMMMM..MMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		3: [
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMUM...........MDMMM",
			"MM.M.MMMMM.MMM..LMTM",
			"MM.M.M.....M.M...MMM",
			"MM.MMM.MMM.M.M.M.MMM",
			"MM.M...M.....M...MMM",
			"MM.M.MMM.M.MMMMM.MMM",
			"MM.M...M.M...M...MMM",
			"MM.MMM.M.MMM.M.MMMMM",
			"MM.M...M...M...M.MMM",
			"MM.M.MMMMM.MMMMM.MMM",
			"MM...............MMM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
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
		1: {"entrance": Vector2(18, 2)},
		2: {"entrance": Vector2(7, 14)},
		3: {"entrance": Vector2(16, 4)},
		4: {"entrance": Vector2(3, 7)},
	}

	floor_encounter_pools = {
		1: ["rogue_process", "memory_leak"],
		2: ["rogue_process", "memory_leak", "recursive_loop", "data_wraith"],
		3: ["memory_leak", "recursive_loop", "data_wraith"],
		4: [],
	}

	# Floor 2's 'b' pair connects two branches of the page maze -- a pointer into the wrong page.
	# sw0 is floor3's lever (16,3) -- flips open the vault door at (17,3). Optional.
	switch_effects = {"sw0": {"flip": [[17, 3]]}}
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


## Phase-4 tileset: grid/circuit, not the medieval cave look.
func _char_to_tile_type(char: String) -> int:
	return _remap_wall_floor(char, TileGeneratorScript.TileType.DIGITAL_WALL, TileGeneratorScript.TileType.DIGITAL_FLOOR)


func _get_dungeon_ambient() -> Color:
	return Color(0.20, 0.26, 0.34)


func _get_ambient_fx_theme() -> String:
	return "storm"


const _LORE := {
	1: [
		{"pos": Vector2(12, 3), "text": "SEGMENTATION FAULT (core dumped somewhere behind you, probably)."},
		{"pos": Vector2(3, 6), "text": "This memory page was freed and reused. You are standing in someone else's variable."},
	],
	2: [
		{"pos": Vector2(6, 13), "text": "0xDEAD0002 -- the portal pair on this page dereferences somewhere it was never told to."},
	],
	3: [
		{"pos": Vector2(16, 3), "text": "The lever's label has been garbage-collected. Pull anyway."},
	],
}


func _setup_transitions_for_floor(floor_num: int) -> void:
	super._setup_transitions_for_floor(floor_num)
	for entry in (_LORE.get(floor_num, []) as Array):
		var sign := Signpost.new()
		sign.sign_text = str(entry["text"])
		sign.position = _sign_position(Vector2i(entry["pos"] as Vector2), floor_num)
		transitions.add_child(sign)
