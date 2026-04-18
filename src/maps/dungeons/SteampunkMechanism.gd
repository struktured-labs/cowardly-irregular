extends DragonCave
class_name SteampunkMechanismScene

## Steampunk Mechanism — W3 dungeon.
## Below Brasston, under the industrial district, lies the Grand Mechanism.
## Endless brass cogs and pneumatic arms. The Meta Knight guards the
## central gearwork, convinced the whole apparatus is aware of being watched.

func _init() -> void:
	cave_name = "The Grand Mechanism"
	cave_id = "steampunk_mechanism"
	boss_id = "meta_knight"
	boss_flag_key = "steampunk_mechanism_cleared"
	total_floors = 3
	overworld_exit_spawn = "plaza"
	overworld_exit_map = "steampunk_overworld"
	unlock_story_flag = "w3_dungeon_cleared"

	floor_layouts = {
		1: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M.MMMM.....MMMM....M",
			"M.M..T.......M..T..M",
			"M.M..........M.....M",
			"M.MMMM.....MMMM....M",
			"M..................M",
			"M......MMMMMM......M",
			"M......M....M......M",
			"M......M..U.M......M",
			"M.T....MMMMMM......M",
			"M..................M",
			"M..................M",
			"M.......DDDD.......M",
			"M..................M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		2: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M.MMMMMM...MMMMMM..M",
			"M.M..............M.M",
			"M.M..T......T....M.M",
			"M.M..............M.M",
			"M.MMMMMM...MMMMMM..M",
			"M..................M",
			"M......MM..MM......M",
			"M......M....M......M",
			"M......M..U.M..T...M",
			"M......MM..MM......M",
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
			"M................T.M",
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
		1: ["steam_rat", "cog_swarm"],
		2: ["clockwork_sentinel", "pipe_phantom", "brass_golem"],
		3: [],
	}


func _get_boss_intro_dialogue() -> Array:
	return [
		"The gears are taller than you are. The noise is so regular it",
		"becomes silence. At the heart of it: a knight in brass plate, polishing",
		"their helmet against a pocketwatch.",
		"",
		"Meta Knight: 'Ah. The party.'",
		"Meta Knight: 'I've been rehearsing this fight for twelve cycles.'",
		"",
		"Hero: 'You've fought us before?'",
		"",
		"Meta Knight: 'Yes. No. I watched the replays.'",
		"Meta Knight: 'Your party always flanks right on turn three.'",
		"Meta Knight: 'I know because the framerate hitches when you do it.'",
		"",
		"Hero: 'How do you know about framerates?'",
		"",
		"Meta Knight: *taps the pocketwatch — it's a frame counter*",
		"Meta Knight: 'I AM the dropped frame. Pleasure to finally fight you.'",
	]
