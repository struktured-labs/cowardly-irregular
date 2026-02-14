extends DragonCave
class_name ShadowDragonCaveScene

## Abyssal Hollow - Shadow Dragon Umbraxis awaits on Floor 3
## Dark maze corridors with spectral enemies

func _init() -> void:
	cave_name = "Abyssal Hollow"
	cave_id = "shadow_dragon_cave"
	boss_id = "shadow_dragon"
	boss_flag_key = "shadow_dragon_defeated"
	total_floors = 3
	overworld_exit_spawn = "shadow_cave_entrance"

	floor_layouts = {
		1: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M.MMM.MMM..MMM.MM..M",
			"M...M...M..M...M...M",
			"M...M.T.M..M...M...M",
			"M...MMMMM..MMMMM...M",
			"M..................M",
			"M.....MMM..MMM.....M",
			"M.....M......M.....M",
			"M.....M..U...M.....M",
			"M.....MMM..MMM.....M",
			"M..................M",
			"M..................M",
			"M.......DDDD.......M",
			"M..................M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		2: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M.MM.MMMMMMMMMM..M.M",
			"M..M.M.........M.M.M",
			"M..M.M.MMMMMMM.M.M.M",
			"M..M.M.M.....M.M.M.M",
			"M..M.M.M.T...M.M...M",
			"M..M...M.....M.M...M",
			"M..MMMMM.....M.M...M",
			"M..........U.M.M...M",
			"M..MMMMMMMMMM..M...M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M.........D........M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		3: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M..................M",
			"M...MMMMM..MMMMM...M",
			"M...M..........M...M",
			"M...M..........M...M",
			"M...M..........M...M",
			"M.........B........M",
			"M...M..........M...M",
			"M...M..........M...M",
			"M...M..........M...M",
			"M...MMMMM..MMMMM...M",
			"M..................M",
			"M..................M",
			"M.........D........M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
	}

	floor_spawn_points = {
		1: {"entrance": Vector2(10, 12)},
		2: {"down_stairs": Vector2(10, 14)},
		3: {"down_stairs": Vector2(10, 14)},
	}

	floor_encounter_pools = {
		1: ["specter", "skeleton"],
		2: ["specter", "skeleton", "imp"],
		3: [],
	}


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
