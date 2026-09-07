extends DragonCave
class_name LightningDragonCaveScene

## Stormspire Cavern — Lightning Dragon Voltharion awaits on Floor 5 (struktured 2026-09-06 depth pass).
## Wide, short storm-lattice floors for a vertical/airy feel; one lever shortcut, one wind-funnel portal, one discharge trap.

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
			"MM..............M..M",
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
			"MMMMMMMMMMMMMMMMMMMM",
			"MM................MM",
			"MM................MM",
			"MM..S.............MM",
			"MM....M......M.T..MM",
			"MM.......M........MM",
			"MM................MM",
			"MM....M......M....MM",
			"MM.........M......MM",
			"MM.............c..MM",
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
			"MM................MM",
			"MM..T.............MM",
			"MM................MM",
			"MM................MM",
			"MM................MM",
			"MM................MM",
			"MM................MM",
			"MM................MM",
			"MM................MM",
			"MM..D.....U.......MM",
			"MM................MM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		4: [
			"MMMMMMMMMMMMMMMMMMMM",
			"MM.....MMMMMMMMMMMMM",
			"MM..T..MMMMMMMMMMMMM",
			"MM.....MMMMMMMMMMMMM",
			"MM.....MMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MM................MM",
			"MM..L.............MM",
			"MM..D...........c.MM",
			"MM................MM",
			"MM........U.......MM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
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
		"sw2": {"flip": [[4, 5]]},
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
		{"pos": Vector2(9, 2), "text": "Tesla Lattice: the pillars aren't decoration, they're insurance."},
		{"pos": Vector2(4, 12), "text": "A wind funnel. It goes up. Whether YOU go up with it is your problem."},
	],
	3: [
		{"pos": Vector2(9, 2), "text": "The Charged Court. Surprisingly calm. Suspiciously calm."},
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
