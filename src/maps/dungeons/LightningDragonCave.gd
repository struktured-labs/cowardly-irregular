extends DragonCave
class_name LightningDragonCaveScene

## Stormspire Cavern — Lightning Dragon Voltharion awaits on Floor 5 (struktured 2026-09-06 depth pass; 2026-10-06
## maze pass; 2026-10-07 required-gate pass). Wide, short storm-lattice floors; one lever shortcut on floor 1,
## one wind-funnel portal. Floors 2-4 each gate the stairs down: floor 2 a conductor pylon powered by pushing a
## block onto it, floor 3 a small-key vault (K/G), floor 4 a lever (flip).

func _init() -> void:
	cave_name = "Stormspire Cavern"
	cave_id = "lightning_dragon_cave"
	boss_id = "lightning_dragon"
	boss_flag_key = "lightning_dragon_defeated"
	boss_cutscene_id = "world1_voltharion_intro"
	total_floors = 5
	overworld_exit_spawn = "lightning_cave_entrance"

	floor_layouts = {
		1: [
			"MMMMMMMMMMMMMMMMMMMM",
			"MM.c.........c..M..M",
			"MM.....L..U.....M.TM",
			"MM..............M..M",
			"MM..............MMMM",
			"MMM.MMMMMMMMMMMM.MMM",
			"MMM.MMMMMMMMMMMM.MMM",
			"MMM.MMMMMMMMMMMM.MMM",
			"MMM.MMMMMMMMMMMM.MMM",
			"MM................MM",
			"MM................MM",
			"MM...D............MM",
			"MM.......T........MM",
			"MM................MM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		2: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M..D...........T...M",
			"M..................M",
			"M....MJM...........M",
			"M....MXM...........M",
			"M..................M",
			"MMMMMMMMMMOMMMMMMMMM",
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
			"M.............K....M",
			"MMMMMMMMMGMMMMMMMMMM",
			"M..................M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M.U................M",
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
			"M..................M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M...T..............M",
			"M........D.........M",
			"M..................M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
	}

	floor_spawn_points = {
		1: {"entrance": Vector2(10, 11)},
	}

	floor_encounter_pools = {
		1: ["goblin", "bat", "skeleton"],
		2: ["goblin", "bat", "skeleton"],
		3: ["goblin", "bat"],
		4: ["goblin", "bat", "skeleton"],
		5: [],
	}

	switch_effects = {
		"sw0": {"flip": [[16, 2]]},
		"sw1": {"trap": "encounter"},
		"sw2": {"flip": [[10, 7]]},
	}
	forced_item_chests = {
		"lightning_dragon_cave_f1_c0": "equipment:thunder_rod",
		"lightning_dragon_cave_f2_c0": "energy_drink",
		"lightning_dragon_cave_f4_c0": "equipment:power_ring",
	}


const _LORE := {
	1: [
		{"pos": Vector2(9, 1), "text": "Stormspire Cavern. The lever hums. So does everything else, unfortunately."},
	],
	2: [
		{"pos": Vector2(3, 3), "text": "The pylon needs weight on it. There's a block for that."},
	],
	3: [
		{"pos": Vector2(3, 3), "text": "The door south is locked. The key is somewhere you can already reach."},
	],
	4: [
		{"pos": Vector2(3, 4), "text": "A lever, conveniently unlabeled. What could possibly go wrong."},
	],
	5: [
		{"pos": Vector2(9, 11), "text": "Spire Summit. Voltharion has been counting the milliseconds until you arrived."},
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
	return "lightning_dragon_cave"


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


## storm-violet
func _get_dungeon_ambient() -> Color:
	return Color(0.32, 0.30, 0.46)
