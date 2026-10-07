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
			"MMiiiiiiiiiiiiiiM..M",
			"MMiiiiiLiiUiiiiiM.TM",
			"MMiiiiiiiiiiiiiiM..M",
			"MMiiiiiiiiiiiiiiiMMM",
			"MMMiMMMMMMMMMMMMiMMM",
			"MMMiMMMMMMMMMMMMiMMM",
			"MMMiMMMMMMMMMMMMiMMM",
			"MMiiiiiiiiiiiiiiiiMM",
			"MMiiiiiiiiiiiiiiiiMM",
			"MMiiiiiiiiiiiiiiiiMM",
			"MMiiiDiiiiiiiiiiiiMM",
			"MMiiiiiiiTiiiiiiiiMM",
			"MMiiiiiiiiiiiiiiiiMM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		2: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M..D...........T...M",
			"M...L..............M",
			"M..................M",
			"M..................M",
			"M..................M",
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M..................M",
			"M..............S...M",
			"M..................M",
			"M.U................M",
			"M..................M",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		3: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M..D...........T...M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M..................M",
			"MMMMMMMMMMjMMMMMMMMM",
			"MjjjjjjjjjjjjjjjjjjM",
			"MjjjjjjjjjjjjjjjjjjM",
			"MllllllllllllllllllM",
			"MjjjjjjjjjjjjjjjjjjM",
			"MjjjjjjjjjjjjjjjjjjM",
			"MjUjjjjjjjjjjjjjjjjM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		4: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M..D...........T...M",
			"M..................M",
			"M..................M",
			"M.............Q....M",
			"MMMMMMMMMZMMMMMMMMMM",
			"M..................M",
			"M..................M",
			"M...............b..M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M.U................M",
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
			"MiiiiiiiiiiiiiibiiiM",
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
		"sw1": {"flip": [[10, 7]]},
		"sw2": {"trap": "encounter"},
	}
	forced_item_chests = {
		"ice_dragon_cave_f1_c0": "equipment:ice_blade",
		"ice_dragon_cave_f2_c0": "arctic_wind",
		"ice_dragon_cave_f4_c0": "equipment:barrier_ring",
	}


const _LORE := {
	1: [
		{"pos": Vector2(9, 8), "text": "Glacial Sanctum. The lake is frozen. The dragon is not amused by skating."},
		{"pos": Vector2(4, 1), "text": "A lever, half-buried in frost. Someone clearly meant to come back for it."},
	],
	2: [
		{"pos": Vector2(3, 4), "text": "A lever, half-buried in frost. Someone clearly meant to come back for it."},
	],
	3: [
		{"pos": Vector2(3, 3), "text": "Ice doesn't let you stop. Aim before you push off."},
	],
	4: [
		{"pos": Vector2(3, 3), "text": "A crack in the far wall. Something nearby surely blasts things open."},
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
		sign.position = (entry["pos"] as Vector2) * TILE_SIZE
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
