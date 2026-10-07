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
			"MM.d.........d..M..M",
			"MM.....L..U.....M.TM",
			"MM..............M..M",
			"MM...............MMM",
			"MMM.MMMMMMMMMMMM.MMM",
			"MMM.MMMMMMMMMMMM.MMM",
			"MMM.MMMMMMMMMMMM.MMM",
			"MMM.MMMMMMMMMMMM.MMM",
			"MMM.MMMMMMMMMMMM.MMM",
			"MM.......S........MM",
			"MM................MM",
			"MM...D...T........MM",
			"MM................MM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		2: [
			"MMMMMMMMMMMMMMMMMMMM",
			"MD.....TM.........MM",
			"M.MMM.MMM.MMMMM.M.MM",
			"M...M.....M...M...MM",
			"MMM.MMMMMMM.M.MMM.MM",
			"M...M.......M.....MM",
			"M.MMM.MMMMMMMMMMMMMM",
			"M.M...M.......M...MM",
			"M.M.M.M.MMMMM.M.MMMM",
			"M.MTM...M.M...M...MM",
			"M.MMM.MMM.M.MMMMM.MM",
			"M...M.....M.M.....MM",
			"MMM.MMMMMMM.M.MMMMMM",
			"MR..........M....UMM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		3: [
			"MMMMMMMMMMMMMMMMMMMM",
			"MD......M.....Z...MM",
			"M.MMMMM.M.MMM.MMM.MM",
			"M...M...M.M...M...MM",
			"MMM.M.MMM.M.MMM.MMMM",
			"M...M.....M.M...M.MM",
			"M.MMM.MMMMM.MMM.M.MM",
			"M.MT..M...M...M.M.MM",
			"M.MMM.M.M.M.M.M.M.MM",
			"M...MTM.M.M.M.M.M.MM",
			"MMM.MMM.M.M.M.M.M.MM",
			"MQM...M.M...M.M.M.MM",
			"M.MMM.M.M.MMM.M.M.MM",
			"M.......M.....M..UMM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		4: [
			"MMMMMMMMMMMMMMMMMMMM",
			"MD..M.M...M.......MM",
			"M.M.M.M.M.M.MMMMM.MM",
			"M.M.M...M.M.M.....MM",
			"M.M.MMMMM.MMM.MMM.MM",
			"M.M...MT..M...M...MM",
			"M.MMM.MMM.M.MMM.MMMM",
			"M...M...M.M...M...MM",
			"MMM.M.M.M.MMM.MMM.MM",
			"M...M...M.....M...MM",
			"M.MMM.M.MMMMMMM.MMMM",
			"M...MTM.M.....M...MM",
			"MMM.MMM.M.M.MMMMM.MM",
			"ML......M.M......UMM",
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
		"sw2": {"flip": [[4, 1]]},
	}
	mirror_effects = {
		"mr0": {"a": [[3, 8]], "b": [[17, 6]]},
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
		{"pos": Vector2(2, 1), "text": "Pull the lever and the walls remember differently. Pull it again and they forget."},
	],
	3: [
		{"pos": Vector2(2, 1), "text": "That chest looks too easy. Everything down here looks too easy."},
	],
	4: [
		{"pos": Vector2(2, 1), "text": "A lever, conveniently unlabeled. What could possibly go wrong."},
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
## Brightened from (0.20, 0.19, 0.28) -- the darkest W1 ambient read as barely
## visible even with lamps lit; still the dimmest cave, now actually readable.
func _get_dungeon_ambient() -> Color:
	return Color(0.26, 0.25, 0.34)


func _get_ambient_fx_theme() -> String:
	return "shadow"
