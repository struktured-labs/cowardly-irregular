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
	total_floors = 3
	overworld_exit_spawn = "glitch_sector"
	overworld_exit_map = "futuristic_overworld"
	unlock_story_flag = "w5_dungeon_cleared"

	floor_layouts = {
		1: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M.MM.MM.MM.MM.MM..TM",
			"M..................M",
			"M..T.............T.M",
			"M..................M",
			"M.MM.MM.MM.MM.MM...M",
			"M..................M",
			"M......MMMMMM......M",
			"M......M....M......M",
			"M......M..U.M......M",
			"M......MMMMMM......M",
			"M..................M",
			"M.......DDDD.......M",
			"M..................M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		2: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M.T....M......M....M",
			"M......M......M....M",
			"M..MMMMM......MMMMMM",
			"M...........T......M",
			"M..MMMMM......MMMMMM",
			"M......M......M....M",
			"M......M......M....M",
			"M..MMMMM..U...MMMMMM",
			"M..................M",
			"M.T................M",
			"M..................M",
			"M.........D........M",
			"M..................M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		3: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M.T................M",
			"M..................M",
			"M...MMMMM..MMMMM...M",
			"M...M..........M...M",
			"M...M..........M...M",
			"M.........B........M",
			"M...M..........M...M",
			"M...M..........M...M",
			"M...MMMMM..MMMMM...M",
			"M................T.M",
			"M..................M",
			"M..................M",
			"M.........D........M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
	}

	floor_spawn_points = {
		1: {"entrance": Vector2(10, 13)},
		2: {"down_stairs": Vector2(10, 13)},
		3: {"down_stairs": Vector2(10, 14)},
	}

	floor_encounter_pools = {
		1: ["rogue_process", "memory_leak"],
		2: ["rogue_process", "memory_leak", "recursive_loop", "data_wraith"],
		3: [],
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
