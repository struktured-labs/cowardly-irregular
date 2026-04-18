extends DragonCave
class_name SuburbanUndergroundScene

## Suburban Underground — W2 dungeon.
## Storm drains and half-collapsed basement passages under Maple Heights.
## Something crawled up from the 32-bit layer and set up shop down there.

func _init() -> void:
	cave_name = "Suburban Underground"
	cave_id = "suburban_underground"
	boss_id = "masterite_warden_suburban"
	boss_flag_key = "suburban_underground_cleared"
	total_floors = 3
	overworld_exit_spawn = "entrance"
	overworld_exit_map = "suburban_overworld"
	unlock_story_flag = "w2_dungeon_cleared"

	floor_layouts = {
		1: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M.MMMM.....MMMM....M",
			"M.M.T........M..T..M",
			"M.M..........M.....M",
			"M.MMMM.....MMMM....M",
			"M..................M",
			"M.....MMM..MMM.....M",
			"M.....M......M.....M",
			"M..T..M..U...M.....M",
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
			"M.MMM.MMM.MMM.MMM..M",
			"M..M...M...M...M...M",
			"M..M.T.M...M.T.M...M",
			"M..MMMMM...MMMMM...M",
			"M..................M",
			"M.....MMMMMMMM.....M",
			"M.....M......M.....M",
			"M.....M..U...M.T...M",
			"M.....MMMMMMMM.....M",
			"M..................M",
			"M..................M",
			"M.........D........M",
			"M..................M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		3: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M.T................M",
			"M..................M",
			"M....MMMM..MMMM....M",
			"M....M........M....M",
			"M....M........M....M",
			"M.........B........M",
			"M....M........M....M",
			"M....M........M....M",
			"M....MMMM..MMMM....M",
			"M..............T...M",
			"M..................M",
			"M..................M",
			"M.........D........M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
	}

	floor_spawn_points = {
		1: {"entrance": Vector2(10, 12)},
		2: {"down_stairs": Vector2(10, 13)},
		3: {"down_stairs": Vector2(10, 14)},
	}

	floor_encounter_pools = {
		1: ["spiteful_crow", "unassuming_dog"],
		2: ["new_age_retro_hippie", "skate_punk", "cranky_lady"],
		3: [],
	}


func _get_boss_intro_dialogue() -> Array:
	return [
		"You pry open the drain cover. Stale lukewarm air breathes up.",
		"Somewhere below, a printer refuses to stop printing.",
		"",
		"At the bottom of the stairs, a man in a quilted vest is arranging",
		"lawn ornaments in a strict grid. His nametag reads WARDEN.",
		"",
		"Masterite Warden: 'HOA meeting is the third Tuesday.'",
		"Masterite Warden: 'You're not on the list.'",
		"",
		"Hero: 'We're just passing through.'",
		"",
		"Masterite Warden: 'That's what SHE said before she put a flamingo",
		"on a lawn zoned for HYDRANGEAS.'",
		"Masterite Warden: *snaps a clipboard in half*",
		"Masterite Warden: 'This is why we have DOCUMENTATION.'",
	]
