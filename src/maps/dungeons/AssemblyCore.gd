extends DragonCave
class_name AssemblyCoreScene

## Assembly Core — W4 Industrial dungeon.
## A three-floor descent through jammed conveyors, scrap pits, and a
## collapsed production line. The Masterite Warden runs the line and
## refuses to admit quota can ever be "enough".

func _init() -> void:
	cave_name = "Assembly Core"
	cave_id = "assembly_core"
	boss_id = "masterite_warden_industrial"
	boss_flag_key = "assembly_core_cleared"
	boss_cutscene_id = "world4_assembly_boss"
	total_floors = 3
	overworld_exit_spawn = "chemical_zone"
	overworld_exit_map = "industrial_overworld"
	unlock_story_flag = "w4_dungeon_cleared"

	floor_layouts = {
		1: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M.MMMM......MMMM.T.M",
			"M.M..............M.M",
			"M.M..T.....T.....M.M",
			"M.M..............M.M",
			"M.MMMM......MMMM...M",
			"M..................M",
			"M.....MMM..MMM.....M",
			"M.....M......M.....M",
			"M.....M..U...M.....M",
			"M.....MMM..MMM.....M",
			"M..................M",
			"M.......DDDD.......M",
			"M..................M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		2: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M.MMMMMM...MMMMMM..M",
			"M.M................M",
			"M.M.T......T.....M.M",
			"M.M..............M.M",
			"M.MMMMMM...MMMMMM..M",
			"M..................M",
			"M.....MMM..MMM.....M",
			"M.....M....T.M.....M",
			"M.....M..U...M.....M",
			"M.....MMM..MMM.....M",
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
			"M....MMMMM.MMMMM...M",
			"M....M.........M...M",
			"M....M.........M...M",
			"M.........B........M",
			"M....M.........M...M",
			"M....M.........M...M",
			"M....MMMMM.MMMMM...M",
			"M..................M",
			"M................T.M",
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
		1: ["conveyor_gremlin", "toxic_sludge"],
		2: ["conveyor_gremlin", "toxic_sludge", "assembly_line_automaton"],
		3: [],
	}


func _get_boss_intro_dialogue() -> Array:
	return [
		"The conveyor belts grind to a halt. The air smells like burnt oil.",
		"",
		"A man in a dented hardhat steps off the gantry. His clipboard is a",
		"shield. His pen is a stylus. His nametag reads WARDEN.",
		"",
		"Masterite Warden: 'Quota is 5000 units. We're at 4998.'",
		"Masterite Warden: 'You wandered in here during QUALIFYING MINUTES.'",
		"Masterite Warden: 'That is TWO DEFECTIVE UNITS.'",
		"",
		"Hero: 'We're not units.'",
		"",
		"Masterite Warden: 'Everything is a unit. That's the point.'",
		"Masterite Warden: 'Once you accept that, the line never stops.'",
		"Masterite Warden: *unclips a time clock and winds it back*",
		"Masterite Warden: 'We're going to work overtime.'",
	]
