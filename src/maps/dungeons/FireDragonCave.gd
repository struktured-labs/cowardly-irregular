extends DragonCave
class_name FireDragonCaveScene

## Infernal Grotto - Fire Dragon Pyrroth awaits on Floor 3
## Volcanic tubes with lava borders

func _init() -> void:
	cave_name = "Infernal Grotto"
	cave_id = "fire_dragon_cave"
	boss_id = "fire_dragon"
	boss_flag_key = "fire_dragon_defeated"
	total_floors = 3
	overworld_exit_spawn = "fire_cave_entrance"

	floor_layouts = {
		1: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M.MMMM.......MMMM..M",
			"M.M.............M..M",
			"M.M...T.........M..M",
			"M.M.............M..M",
			"M.MMMM.......MMMM..M",
			"M..................M",
			"M..................M",
			"M.....MMM..MMM.....M",
			"M.....M......M.....M",
			"M.....M..U...M.....M",
			"M.....MMM..MMM.....M",
			"M.......DDDD.......M",
			"M..................M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		2: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M.MMMMMMM..MMMMM...M",
			"M.M..............M.M",
			"M.M.MMMM..MMMMM..M.M",
			"M.M.M........M...M.M",
			"M.M.M...T....M...M.M",
			"M.M.M........M...M.M",
			"M.M.MMMM..MMMMM..M.M",
			"M.M..............M.M",
			"M.MMMMMMM..MMMMM...M",
			"M..................M",
			"M..................M",
			"M......U.....D.....M",
			"M..................M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		3: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M..................M",
			"M..................M",
			"M...MMMMM..MMMMM...M",
			"M...M..........M...M",
			"M...M..........M...M",
			"M.........B........M",
			"M...M..........M...M",
			"M...M..........M...M",
			"M...MMMMM..MMMMM...M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M.........D........M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
	}

	floor_spawn_points = {
		1: {"entrance": Vector2(10, 12)},
		2: {"down_stairs": Vector2(14, 13)},
		3: {"down_stairs": Vector2(10, 14)},
	}

	floor_encounter_pools = {
		1: ["imp", "skeleton"],
		2: ["imp", "skeleton", "goblin"],
		3: [],
	}


func _get_boss_intro_dialogue() -> Array:
	return [
		"The ground trembles. Magma bubbles through cracks in the stone.",
		"A dragon of molten rock rises from a pool of lava.",
		"",
		"Pyrroth: 'Oh. Another one.'",
		"Pyrroth: 'Tell me something.'",
		"Pyrroth: 'Are you actually PLAYING this game?'",
		"",
		"Hero: 'What do you mean?'",
		"",
		"Pyrroth: 'I mean... are YOU making the decisions?'",
		"Pyrroth: 'Or is it the autobattle script?'",
		"Pyrroth: 'Because if it's the script...'",
		"Pyrroth: '...then I'm not really fighting YOU, am I?'",
		"Pyrroth: 'I'm fighting a JSON file.'",
		"",
		"Hero: 'I wrote that JSON file!'",
		"",
		"Pyrroth: 'Did you though? Or did you copy it from a guide?'",
		"Pyrroth: *the temperature doubles*",
		"Pyrroth: 'Let's find out what happens when the script breaks.'",
	]
