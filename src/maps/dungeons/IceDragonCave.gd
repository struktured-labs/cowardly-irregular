extends DragonCave
class_name IceDragonCaveScene

## Glacial Sanctum - Ice Dragon Glacius awaits on Floor 5 (struktured 2026-09-06 depth pass).
## Frozen-lake open floors (i) alternate with narrow crevasse corridors; one lever, one portal shortcut, one ambush plate.

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
			"MMMMMMMMMMMMMMMMMMMM",
			"MM................MM",
			"MM.MMMMMMMMMMMMMM.MM",
			"MMSMMMMMMMMMMMMMM.MM",
			"MM.MMMMMMMMMMMMMM.MM",
			"MM.......MMMMMMMM.MM",
			"MM.MMMMM.MMMMMMMM.MM",
			"MM.MMMMM.MMMMMMMM.MM",
			"MM.MMMMM.MMMMMMMM.MM",
			"MM.MMMMM......T...MM",
			"MM.MMMMMMMMMMMMMMMMM",
			"MM.MMMMMMMMMMMMMMMMM",
			"MM..D.....U.......MM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		3: [
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMiiiiiiiiiiiiiiiiMM",
			"MMiiiiiiiiiiiiiiiiMM",
			"MMiiTiiiiiiiiiiiiiMM",
			"MMiiiiiiiiiiiiiiiiMM",
			"MMiiiiiiiiiiiiiiiiMM",
			"MMiiiiiiiiiiiiiiiiMM",
			"MMiiiiiiiiiiiiiiiiMM",
			"MMiiiiiiiiiiiiiiiiMM",
			"MMiiiiiiiiiiiiibiiMM",
			"MMiiiiiiiiiiiiiiiiMM",
			"MMiiDiiiiiUiiiiiiiMM",
			"MMiiiiiiiiiiiiiiiiMM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		4: [
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MM..D...........MMMM",
			"MM..............MMMM",
			"MM........H.....MMMM",
			"MMMMMMMMM.MMMMMMMMMM",
			"MMMMMMMMM.MMMMMMMMMM",
			"MM..............MMMM",
			"MM..............MMMM",
			"MM..............MMMM",
			"MMMMMMMMMMMMMM.MMMMM",
			"MM..............M..M",
			"MM..L...........M.TM",
			"MM........U.....M..M",
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
		"sw1": {"trap": "encounter"},
		"sw2": {"flip": [[16, 12]]},
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
		{"pos": Vector2(9, 2), "text": "The Crevasse: mind the gap. The gap does not mind you."},
	],
	3: [
		{"pos": Vector2(9, 2), "text": "The lake widens here. So does the dragon's patience, allegedly."},
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
