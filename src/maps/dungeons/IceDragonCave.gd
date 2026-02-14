extends DragonCave
class_name IceDragonCaveScene

## Glacial Sanctum - Ice Dragon Glacius awaits on Floor 3
## Frozen tunnels with increasing cold-themed enemies

func _init() -> void:
	cave_name = "Glacial Sanctum"
	cave_id = "ice_dragon_cave"
	boss_id = "ice_dragon"
	boss_flag_key = "ice_dragon_defeated"
	total_floors = 3
	overworld_exit_spawn = "ice_cave_entrance"

	floor_layouts = {
		1: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M..MMMM....MMMM....M",
			"M..M..........M....M",
			"M..M....T.....M....M",
			"M..MMMMMMMMMMMM....M",
			"M..................M",
			"M.....MM...MM......M",
			"M.....M.....M......M",
			"M.....M..U..M......M",
			"M.....MM...MM......M",
			"M..................M",
			"M..................M",
			"M.......DDDD.......M",
			"M..................M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		2: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M.MMMMM......MMMMM.M",
			"M.M..........T.M...M",
			"M.M............M...M",
			"M.MMMMM......MMMMM.M",
			"M..................M",
			"M..................M",
			"M......MM.MM.......M",
			"M.......M..M.......M",
			"M.......M.UM.......M",
			"M......MM.MM.......M",
			"M..................M",
			"M..................M",
			"M.........D........M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		3: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M..................M",
			"M..................M",
			"M....MMMM..MMMM....M",
			"M....M..........M..M",
			"M....M..........M..M",
			"M.........B........M",
			"M....M..........M..M",
			"M....M..........M..M",
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
		2: {"down_stairs": Vector2(10, 14)},
		3: {"down_stairs": Vector2(10, 14)},
	}

	floor_encounter_pools = {
		1: ["ice_wolf", "bat"],
		2: ["ice_wolf", "skeleton", "bat"],
		3: [],
	}


func _get_boss_intro_dialogue() -> Array:
	return [
		"The air turns to frost. Ice crystals hang motionless in the dark.",
		"",
		"A massive dragon of living ice unfurls from the cavern wall.",
		"",
		"Glacius: 'You know what I've been waiting for?'",
		"Glacius: 'Three save files. THREE.'",
		"Glacius: 'One for each difficulty. One for each \"perfect\" run.'",
		"Glacius: 'And every single one of you does the same thing.'",
		"",
		"Hero: 'How do you know about save files?'",
		"",
		"Glacius: 'I've been frozen here since the TUTORIAL.'",
		"Glacius: 'I've had time to read the documentation.'",
		"Glacius: *exhales a cloud of absolute zero*",
		"Glacius: 'Let's see how your autobattle handles THIS.'",
	]
