extends DragonCave
class_name FireDragonCaveScene

## Infernal Grotto - Fire Dragon Pyrroth awaits on Floor 5 (struktured 2026-09-06 depth pass; 2026-10-06 maze
## pass; 2026-10-07 required-gate pass per struktured's "Required, Zelda-style" ruling). Lava chokepoints (l),
## a caldera boss arena, one lever shortcut on floor 1. Floors 2-4 each gate the stairs down behind a REQUIRED
## puzzle: floor 2 a small-key vault (K/G), floor 3 a timed plate/gate (Y/W), floor 4 a lever (flip).

func _init() -> void:
	cave_name = "Infernal Grotto"
	cave_id = "fire_dragon_cave"
	boss_id = "fire_dragon"
	boss_flag_key = "fire_dragon_defeated"
	boss_cutscene_id = "world1_pyrroth_intro"
	total_floors = 5
	overworld_exit_spawn = "fire_cave_entrance"

	floor_layouts = {
		1: [
			"MMMMMMMMMMMMMMMMMMMM",
			"MM.a.........a..M..M",
			"MM.....L..U.....M.TM",
			"MM..............M..M",
			"MM...............MMM",
			"MMM.MMMMllllMMMM.MMM",
			"MMM.MMMMllllMMMM.MMM",
			"MMM.MMMMllllMMMM.MMM",
			"MMM.MMMMllllMMMM.MMM",
			"MMM.MMMMMMMMMMMM.MMM",
			"MM..............H.MM",
			"MM................MM",
			"MM...D............MM",
			"MM.......T........MM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
		],
			2: [
				"MMMMMMMMMMMMMMMMMMMM",
				"M..................M",
				"M..D...........T...M",
				"M..................M",
				"M..................M",
				"M.............K....M",
				"MMMMMMMMMGMMMMMMMMMM",
				"M..................M",
				"M..................M",
				"M..................M",
				"M..............S...M",
				"M..................M",
				"M..................M",
				"M.U................M",
				"MMMMMMMMMMMMMMMMMMMM",
				"MMMMMMMMMMMMMMMMMMMM",
			],
			3: [
				"MMMMMMMMMMMMMMMMMMMM",
				"M........M.........M",
				"M..D.....M.....T...M",
				"M........M.........M",
				"M........M.........M",
				"M........M.........M",
				"M........M.........M",
				"M......Y.W.........M",
				"M........M..U......M",
				"M........M.........M",
				"M........M.........M",
				"M........M.........M",
				"M........M.........M",
				"M........M.........M",
				"MMMMMMMMMMMMMMMMMMMM",
				"MMMMMMMMMMMMMMMMMMMM",
			],
			4: [
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
				"M..................M",
				"M..................M",
				"M.U................M",
				"M..................M",
				"MMMMMMMMMMMMMMMMMMMM",
				"MMMMMMMMMMMMMMMMMMMM",
			],
		5: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M........B.........M",
			"M..................M",
			"M...lllll.llllll...M",
			"M...lllll.llllll...M",
			"M...lllll.llllll...M",
			"M...lllll.llllll...M",
			"M...lllll.llllll...M",
			"M...lllll.llllll...M",
			"M..................M",
			"M..................M",
			"M..T...............M",
			"M........D.........M",
			"M..................M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
	}

	floor_spawn_points = {
		1: {"entrance": Vector2(10, 13)},
	}

	floor_encounter_pools = {
		1: ["imp", "skeleton"],
		2: ["imp", "skeleton", "goblin"],
		3: ["imp", "goblin"],
		4: ["imp", "skeleton", "goblin"],
		5: [],
	}

	switch_effects = {
		"sw0": {"flip": [[16, 2]]},
		"sw1": {"trap": "encounter"},
		"sw2": {"flip": [[10, 7]]},
	}
	trap_chests = ["fire_dragon_cave_f2_c0"]
	forced_item_chests = {
		"fire_dragon_cave_f1_c0": "equipment:flame_sword",
		"fire_dragon_cave_f3_c0": "inferno_crystal",
		"fire_dragon_cave_f4_c0": "hi_ether",
	}


const _LORE := {
	1: [
		{"pos": Vector2(9, 1), "text": "Infernal Grotto. Mind the lava. It minds you back."},
		{"pos": Vector2(9, 11), "text": "A lever, conveniently unlabeled. What could possibly go wrong."},
	],
	2: [
		{"pos": Vector2(3, 3), "text": "The door south is locked. The key is somewhere you can already reach."},
	],
	3: [
		{"pos": Vector2(3, 3), "text": "The plate opens the gate for a few seconds, no more. Run."},
	],
	4: [
		{"pos": Vector2(3, 4), "text": "A lever, conveniently unlabeled. What could possibly go wrong."},
	],
	5: [
		{"pos": Vector2(9, 11), "text": "The Caldera. Pyrroth has been rehearsing his entrance for weeks."},
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
	return "fire_dragon_cave"


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


## embers in the rock
func _get_dungeon_ambient() -> Color:
	return Color(0.42, 0.26, 0.24)
