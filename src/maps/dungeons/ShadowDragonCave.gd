extends DragonCave
class_name ShadowDragonCaveScene

## Abyssal Hollow - Shadow Dragon Umbraxis awaits on Floor 5 (struktured 2026-09-06 depth pass; 2026-10-06 maze
## pass; 2026-10-07 required-gate pass). A lever vault and disorienting same-floor portal on floor 1/2.
## Floors 2-4 each gate the stairs down: floor 2 a mirror lever (swaps which of two doorways is open), floor 3
## a blast-charge vault (Q/Z) with a mimic chest, floor 4 a lever (flip).

func _init() -> void:
	cave_name = "Abyssal Hollow"
	cave_id = "shadow_dragon_cave"
	boss_id = "shadow_dragon"
	boss_flag_key = "shadow_dragon_defeated"
	boss_cutscene_id = "world1_umbraxis_intro"
	total_floors = 5
	overworld_exit_spawn = "shadow_cave_entrance"

	floor_layouts = {
		1: [
			"MMMMMMMMMMMMMMMMMMMM",
			"MM..............M..M",
			"MM.....L..U.....M.TM",
			"MM..............M..M",
			"MM...............MMM",
			"MMM.MMMMMMMMMMMM.MMM",
			"MMM.MMMMMMMMMMMM.MMM",
			"MMM.MMMMMMMMMMMM.MMM",
			"MMM.MMMMMMMMMMMM.MMM",
			"MMM.MMMMMMMMMMMM.MMM",
			"MM................MM",
			"MM................MM",
			"MM...D...T........MM",
			"MM................MM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		2: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M..D...........T...M",
			"M...R...........d..M",
			"M...............d..M",
			"M..................M",
			"M..................M",
			"MMMMMMMMMMMMM.MMMMMM",
			"M..........MM......M",
			"M..........MM......M",
			"M..........MM......M",
			"M..........MM......M",
			"M.U........MM......M",
			"M..........MM......M",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		3: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M..D...........T...M",
			"M..................M",
			"M..................M",
			"M.............Q....M",
			"MMMMMMMMMZMMMMMMMMMM",
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
		1: {"entrance": Vector2(10, 13)},
	}

	floor_encounter_pools = {
		1: ["specter", "skeleton"],
		2: ["specter", "skeleton", "imp"],
		3: ["specter", "imp"],
		4: ["specter", "skeleton", "imp"],
		5: [],
	}

	switch_effects = {
		"sw0": {"flip": [[16, 2]]},
		"sw1": {"trap": "encounter"},
		"sw2": {"flip": [[10, 7]]},
	}
	mirror_effects = {
		"mr0": {"a": [[13, 7]], "b": [[7, 7]]},
	}
	trap_chests = ["shadow_dragon_cave_f3_c0"]
	forced_item_chests = {
		"shadow_dragon_cave_f1_c0": "equipment:shadow_rod",
		"shadow_dragon_cave_f4_c0": "dark_crystal",
	}


const _LORE := {
	1: [
		{"pos": Vector2(9, 1), "text": "Abyssal Hollow. The lever is real. Whether pulling it is your idea is less certain."},
	],
	2: [
		{"pos": Vector2(3, 4), "text": "Pull the lever and the walls remember differently. Pull it again and they forget."},
	],
	3: [
		{"pos": Vector2(3, 3), "text": "That chest looks too easy. Everything down here looks too easy."},
	],
	4: [
		{"pos": Vector2(3, 4), "text": "A lever, conveniently unlabeled. What could possibly go wrong."},
	],
	5: [
		{"pos": Vector2(9, 11), "text": "The Abyss doesn't stare back. It already knows what it will see."},
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
	return "shadow_dragon_cave"


func _get_boss_intro_dialogue() -> Array:
	return [
		"The shadows coalesce. Darkness becomes form.",
		"Two violet eyes open in the void.",
		"",
		"Umbraxis: 'Interesting.'",
		"Umbraxis: 'You came all the way down here.'",
		"Umbraxis: 'Do you even know what I am?'",
		"",
		"Hero: 'A dragon?'",
		"",
		"Umbraxis: 'I'm data. Arranged to look like a dragon.'",
		"Umbraxis: 'And you're data arranged to look like a hero.'",
		"Umbraxis: 'The only difference between us...'",
		"Umbraxis: '...is that I KNOW I'm just data.'",
		"",
		"Hero: '...'",
		"",
		"Umbraxis: 'Don't worry. It only hurts if you think about it.'",
		"Umbraxis: *the room inverts*",
	]


## the darkest of the four
func _get_dungeon_ambient() -> Color:
	return Color(0.20, 0.19, 0.28)
