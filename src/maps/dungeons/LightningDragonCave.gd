extends DragonCave
class_name LightningDragonCaveScene

## Stormspire Cavern - Lightning Dragon Voltharion awaits on Floor 2
## Storm-carved open halls, shorter but more intense

func _init() -> void:
	cave_name = "Stormspire Cavern"
	cave_id = "lightning_dragon_cave"
	boss_id = "lightning_dragon"
	boss_flag_key = "lightning_dragon_defeated"
	total_floors = 2
	overworld_exit_spawn = "lightning_cave_entrance"

	floor_layouts = {
		1: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M.MMM..........MMM.M",
			"M.M..............M.M",
			"M.M....MMMMMM....M.M",
			"M.M....M....M....M.M",
			"M.M....M.T..M....M.M",
			"M......M....M......M",
			"M......MMMMMM......M",
			"M..................M",
			"M....MM......MM....M",
			"M....M....U...M....M",
			"M....MM......MM....M",
			"M.......DDDD.......M",
			"M..................M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		2: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M..................M",
			"M..MMMM......MMMM..M",
			"M..M..........M....M",
			"M..M..........M....M",
			"M..M..........M....M",
			"M.........B........M",
			"M..M..........M....M",
			"M..M..........M....M",
			"M..M..........M....M",
			"M..MMMM......MMMM..M",
			"M..................M",
			"M..................M",
			"M.........D........M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
	}

	floor_spawn_points = {
		1: {"entrance": Vector2(10, 12)},
		2: {"down_stairs": Vector2(10, 14)},
	}

	floor_encounter_pools = {
		1: ["goblin", "bat", "skeleton"],
		2: [],
	}


func _get_boss_intro_dialogue() -> Array:
	return [
		"Static fills the air. Your hair stands on end.",
		"Lightning arcs between stalactites like a tesla coil.",
		"",
		"Voltharion: 'FINALLYFINALLYFINALLYFINALLY!!!'",
		"Voltharion: 'Do you KNOW how BORING it is waiting?!'",
		"Voltharion: 'I've been counting milliseconds!'",
		"Voltharion: '847,293,461 of them! Give or take!'",
		"",
		"Hero: 'Slow down, I can barely--'",
		"",
		"Voltharion: 'SLOW?! SLOW IS FOR CPUS WITH THERMAL THROTTLING!'",
		"Voltharion: 'I run at CLOCK SPEED baby!'",
		"Voltharion: 'Speaking of which--'",
		"Voltharion: 'Your turn timer starts NOW!'",
		"Voltharion: 'Actually it started 3 lines ago!'",
		"Voltharion: 'YOU'RE ALREADY BEHIND!'",
		"Voltharion: *crackles with barely contained energy*",
	]
