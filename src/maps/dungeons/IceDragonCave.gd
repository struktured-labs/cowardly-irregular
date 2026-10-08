extends DragonCave
class_name IceDragonCaveScene

## Glacial Sanctum - Ice Dragon Glacius awaits on Floor 5 (struktured 2026-09-06 depth pass; 2026-10-06 maze
## pass; 2026-10-07 required-gate pass). Frozen-lake open floors (i) and a lever shortcut on floor 1. Floors
## 2-4 each gate the stairs down: floor 2 a lever (flip), floor 3 an ice-slide crossing over a lava barrier
## (only crossable while sliding), floor 4 a blast-charge vault (Q/Z).

func _init() -> void:
	cave_name = "Glacial Sanctum"
	cave_id = "ice_dragon_cave"
	boss_id = "ice_dragon"
	boss_flag_key = "ice_dragon_defeated"
	boss_cutscene_id = "world1_glacius_intro"
	total_floors = 5
	overworld_exit_spawn = "ice_cave_entrance"

	floor_layouts = {
		1: [
			"MMMMMMMMMMMMMMMMMMMM",
			"MMibiiiiiiiiibiiM..M",
			"MMiiiiiLiiUiiiiiM.TM",
			"MMiiiiiiiiiiiiiiM..M",
			"MMiiiiiiiiiiiiiiiMMM",
			"MMMiMMMMMMMMMMMMiMMM",
			"MMMiMMMMMMMMMMMMiMMM",
			"MMMiMMMMMMMMMMMMiMMM",
			"MMiiiiiiiiiiiiiiiiMM",
			"MMiiiiiiiSiiiiiiiiMM",
			"MMiiiiiiiiiiiiiiiiMM",
			"MMiiiDiiiiiiiiiiiiMM",
			"MMiiiiiiiTiiiiiiiiMM",
			"MMiiiiiiiiiiiiiiiiMM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		2: [
			"MMMMMMMMMMMMMMMMMMMM",
			"MD....MT......M...MM",
			"M.MMM.MMMMM.M.M.M.MM",
			"M..TM.M.....M.M.M.MM",
			"M.MMM.M.MMMMM.M.M.MM",
			"M...M.M...M.M...M.MM",
			"M.M.M.M.M.M.MMMMM.MM",
			"MLM.M.M.M.M...M...MM",
			"MMM.M.MMM.M.MMM.M.MM",
			"M...M...M.M...M...MM",
			"M.MMMMM.M.M.M.MMM.MM",
			"M.M...M...M.M.M...MM",
			"M.M.M.MMMMM.M.M.MMMM",
			"M...M.......M...MUMM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		3: [
			"MMMMMMMMMMMMMMMMMMMM",
			"MD..........M.....MM",
			"MMMMMMMMMMM.M.MMM.MM",
			"M.....M...M.M.M...MM",
			"M.M.MMM.M.M.M.MMM.MM",
			"M.M.....M...M...M.MM",
			"M.MMMMMMMMMMM.M.M.MM",
			"M.M.............M.MM",
			"M.M.M.MMMMM.MMMMMMMM",
			"M.M.M.......ijjjjjMM",
			"M.M.M.MMMMMMMjjjjjMM",
			"M...M...M...MlllllMM",
			"MMMMMMM.MMM.MjjjjjMM",
			"M...........MjjjjUMM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		4: [
			"MMMMMMMMMMMMMMMMMMMM",
			"MD........MTM.....MM",
			"M.MMMMMMM.M.M.M.MMMM",
			"M..H....M.M...M...MM",
			"M.MMM.M.M.MMMMMMM.MM",
			"M.M...MTM.M.......MM",
			"M.M.MMMMM.M.MMMMM.MM",
			"MQM.....M.M.M...M.MM",
			"MMMMMMM.M.M.M.M.M.MM",
			"M...M...M.M.M.M.M.MM",
			"M.M.M.MMM.M.M.MMM.MM",
			"M.....M...M.M.M...MM",
			"M.MMMMM.MMM.M.M.MMMM",
			"M.......Z...M....UMM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		5: [
			"MMMMMMMMMMMMMMMMMMMM",
			"MiiiiiiiiiiiiiiiiiiM",
			"MiiiiiiiiBiiiiiiiiiM",
			"MiiiiiiiiiiiiiiiiiiM",
			"MiiiiiiiiiiiiiiiiiiM",
			"MiiiiiiiiiiiiiiiiiiM",
			"MiiiiiiiiiiiiiiiiiiM",
			"MiiiiiiiiiiiiiiiiiiM",
			"MiiiiiiiiiiiiiiiiiiM",
			"MiiiiiiiiiiiiiiiiiiM",
			"MiiiiiiiiiiiiiiiiiiM",
			"MiiiiiiiiiiiiiiiiiiM",
			"MiiiTiiiiiiiiiiiiiiM",
			"MiiiiiiiiDiiiiiiiiiM",
			"MiiiiiiiiiiiiiiiiiiM",
			"MMMMMMMMMMMMMMMMMMMM",
		],
	}

	floor_spawn_points = {
		1: {"entrance": Vector2(10, 11)},
	}

	floor_encounter_pools = {
		1: ["ice_wolf", "bat"],
		2: ["ice_wolf", "skeleton", "bat"],
		3: ["ice_wolf", "bat"],
		4: ["ice_wolf", "skeleton", "bat"],
		5: [],
	}

	switch_effects = {
		"sw0": {"flip": [[16, 2]]},
		"sw1": {"trap": "encounter"},
		"sw2": {"flip": [[16, 13]]},
	}
	puzzle_chambers = {
		3: [{"rect": [13, 9, 17, 13], "reason": "the ice-slide-over-lava crossing needs room to slide; the maze touches it at exactly one door"}],
	}
	forced_item_chests = {
		"ice_dragon_cave_f1_c0": "equipment:ice_blade",
		"ice_dragon_cave_f2_c0": "arctic_wind",
		"ice_dragon_cave_f4_c0": "equipment:barrier_ring",
	}


const _LORE := {
	1: [
		{"pos": Vector2(9, 10), "text": "Glacial Sanctum. The lake is frozen. The dragon is not amused by skating."},
		{"pos": Vector2(4, 1), "text": "A lever, half-buried in frost. Someone clearly meant to come back for it."},
	],
	2: [
		{"pos": Vector2(2, 1), "text": "A lever, half-buried in frost. Someone clearly meant to come back for it."},
	],
	3: [
		{"pos": Vector2(2, 1), "text": "Ice doesn't let you stop. Aim before you push off."},
	],
	4: [
		{"pos": Vector2(2, 1), "text": "A crack in the far wall. Something nearby surely blasts things open."},
	],
	5: [
		{"pos": Vector2(9, 11), "text": "The Frozen Throne. Glacius has read every strategy guide ever written about her."},
	],
}


func _setup_transitions_for_floor(floor_num: int) -> void:
	super._setup_transitions_for_floor(floor_num)
	for entry in (_LORE.get(floor_num, []) as Array):
		var sign := Signpost.new()
		sign.sign_text = str(entry["text"])
		sign.position = _sign_position(Vector2i(entry["pos"] as Vector2), floor_num)
		transitions.add_child(sign)


## Each W1 dragon cave has its own SoundManager routing arm; without
## this override they inherited "cave" and all four played the generic
## medieval dungeon bed.
func _get_music_area_id() -> String:
	return "ice_dragon_cave"


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


## blue under the frost
func _get_dungeon_ambient() -> Color:
	return Color(0.28, 0.36, 0.48)


func _get_ambient_fx_theme() -> String:
	return "frost"
