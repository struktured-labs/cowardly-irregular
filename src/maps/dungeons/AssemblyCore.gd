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
	# (Tick 105: defeat_cutscene removed. The W4 warden defeat plays via
	# the GameLoop gate on cutscene_flag_warden_industrial_defeated in
	# assembly_core.)
	total_floors = 4
	overworld_exit_spawn = "chemical_zone"
	overworld_exit_map = "industrial_overworld"
	unlock_story_flag = "w4_dungeon_cleared"
	# Bridge to game_constants — GameLoop:876 gates world3_chapter4 on
	# `cutscene_flag_warden_industrial_defeated`. (Same bridge as
	# SuburbanUnderground; see 40c54ae for the underlying class of bug.)
	defeat_cutscene_flags = ["cutscene_flag_warden_industrial_defeated"]

	# struktured 2026-09-06: 4 floors now — sealed D-room forces the plate (encounter) -> lever-vault floor -> portal catwalk -> warden.
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
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MM......MMMMMMMMMMMM",
			"MM..D...MMMMMMMMMMMM",
			"MM......MMMMMMMMMMMM",
			"MMMMSMMMMMMMMMMMMMMM",
			"M..................M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M.............U....M",
			"M..............MMM.M",
			"M............L.MTM.M",
			"M..............MMM.M",
			"M..................M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		3: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M..................M",
			"M..................M",
			"M.............U....M",
			"M..................M",
			"M..................M",
			"M..a............a..M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M...D..............M",
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
		2: {"entrance": Vector2(6, 3)},
		3: {"entrance": Vector2(13, 12)},
		4: {"entrance": Vector2(3, 7)},
	}

	floor_encounter_pools = {
		1: ["conveyor_gremlin", "toxic_sludge"],
		2: ["conveyor_gremlin", "toxic_sludge", "assembly_line_automaton"],
		3: ["conveyor_gremlin", "assembly_line_automaton"],
		4: [],
	}

	# sw0: floor2's plate (4,5), the room's only exit -- unavoidable encounter. sw1: floor2's lever (13,12) -- optional bonus-vault door.
	switch_effects = {
		"sw0": {"trap": "encounter"},
		"sw1": {"flip": [[15, 12]]},
	}
	forced_item_chests = {
		"assembly_core_f1_c1": "scrap_metal",
		"assembly_core_f2_c0": "circuit_board",
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


func _get_music_area_id() -> String:
	return "industrial_dungeon"


const _LORE := {
	1: [
		{"pos": Vector2(3, 6), "text": "QUOTA REMINDER: the line does not stop for lunch. The line does not know what lunch is."},
		{"pos": Vector2(16, 6), "text": "A defective unit was here. Management assures you it has been 'processed'."},
	],
	2: [
		{"pos": Vector2(3, 2), "text": "INSPECTION CHECKPOINT AHEAD. Compliance is not optional. Neither, it turns out, is the corridor."},
	],
	3: [
		{"pos": Vector2(9, 12), "text": "The express portal skips the line. Management would very much like to know how you found it."},
	],
}


func _setup_transitions_for_floor(floor_num: int) -> void:
	super._setup_transitions_for_floor(floor_num)
	for entry in (_LORE.get(floor_num, []) as Array):
		var sign := Signpost.new()
		sign.sign_text = str(entry["text"])
		sign.position = (entry["pos"] as Vector2) * TILE_SIZE
		transitions.add_child(sign)
