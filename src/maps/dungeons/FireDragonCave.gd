extends DragonCave
class_name FireDragonCaveScene

## Infernal Grotto - Fire Dragon Pyrroth awaits on Floor 5 (struktured 2026-09-06 depth pass).
## Lava chokepoints (l), a caldera boss arena, one lever shortcut, one portal shortcut, one ambush plate.

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
			"MM..............M..M",
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
			"MMMMMMMMMMMMMMMMMMMM",
			"MM................MM",
			"MM................MM",
			"MM..T..........a..MM",
			"MM................MM",
			"MM....llllllll....MM",
			"MM....llllllll....MM",
			"MM....llllllll....MM",
			"MM....llllllll....MM",
			"MM...........T....MM",
			"MM................MM",
			"MM..D.....U.......MM",
			"MM................MM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		3: [
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MM................MM",
			"MM.MMM.MMMMMMMMMM.MM",
			"MM.MMM.MMMMMMMMMM.MM",
			"MM.M............M.MM",
			"MM.M.MMM.S..MMM.M.MM",
			"MM.M.MMM.T..MMM.M.MM",
			"MM.M.MMM....MMM.M.MM",
			"MM.M.MMM....MMM.M.MM",
			"MM.M............M.MM",
			"MM.MMMMMMMMMM.MMM.MM",
			"MM.MMMMMMMMMM.MMM.MM",
			"MM..D.....U.......MM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		4: [
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MM................MM",
			"MM................MM",
			"MM..D...........a.MM",
			"MM................MM",
			"MM.......T........MM",
			"MM................MM",
			"MM........U.......MM",
			"MM................MM",
			"MM................MM",
			"MMMMMMMMMMMMMMMMMMMM",
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
		{"pos": Vector2(9, 3), "text": "The chest by the door is bait. The one across the vent isn't. Probably."},
	],
	3: [
		{"pos": Vector2(9, 2), "text": "The Slag Maze: designed by a dragon with a grudge against cartography."},
		{"pos": Vector2(9, 12), "text": "Something ahead is guarding treasure. Something behind you is louder."},
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
