extends DragonCave
class_name NullChamberScene

## Null Chamber — W6 Abstract dungeon.
## Three rooms that dispute their own existence. The Curator archives
## what's been removed; you are the only thing still being rendered.

func _init() -> void:
	cave_name = "Null Chamber"
	cave_id = "null_chamber"
	boss_id = "masterite_curator_abstract"
	boss_flag_key = "null_chamber_cleared"
	total_floors = 3
	overworld_exit_spawn = "catalog"
	overworld_exit_map = "abstract_overworld"
	unlock_story_flag = "w6_dungeon_cleared"

	floor_layouts = {
		1: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M..................M",
			"M..T............T..M",
			"M..................M",
			"M..................M",
			"M....MMM....MMM....M",
			"M....M........M....M",
			"M....M...U....M....M",
			"M....MMM....MMM....M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M.......DDDD.......M",
			"M..................M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		2: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M.T..............T.M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M......MMMMMM......M",
			"M......M....M......M",
			"M......M..U.M......M",
			"M......MMMMMM......M",
			"M.....T............M",
			"M..................M",
			"M..................M",
			"M.........D........M",
			"M..................M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		3: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M.T..............T.M",
			"M..................M",
			"M....MMM....MMM....M",
			"M....M........M....M",
			"M....M........M....M",
			"M.........B........M",
			"M....M........M....M",
			"M....M........M....M",
			"M....MMM....MMM....M",
			"M..................M",
			"M.T..............T.M",
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
		1: ["null_entity", "forgotten_variable"],
		2: ["null_entity", "forgotten_variable", "empty_set", "the_absence"],
		3: [],
	}


func _get_boss_intro_dialogue() -> Array:
	return [
		"The room does not exist. You are standing in the citation of a",
		"room that used to exist. The walls are parenthetical.",
		"",
		"A figure steps out of a footnote. They are holding a label maker.",
		"",
		"Masterite Curator: 'Everything you've collected — I removed from",
		"the registry. You're welcome.'",
		"",
		"Hero: 'Why?'",
		"",
		"Masterite Curator: 'Inventory shrinkage. No surface area. Clean.'",
		"Masterite Curator: 'You are the last unoptimized thing.'",
		"Masterite Curator: *raises the label maker*",
		"Masterite Curator: 'Hold still. This won't take.'",
	]
