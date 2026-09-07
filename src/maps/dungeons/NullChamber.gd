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
	boss_cutscene_id = "world6_null_chamber_boss"
	# Its three sibling masterite dungeons all declare this; without it world5_curator_defeat is unreachable.
	defeat_cutscene_flags = ["cutscene_flag_curator_abstract_defeated"]
	total_floors = 3
	overworld_exit_spawn = "catalog"
	overworld_exit_map = "abstract_overworld"
	unlock_story_flag = "w6_dungeon_cleared"

	# struktured 2026-09-06: stays modest by design (Vertex Apex is the true minimalist finale) -- a portal pair, a lever, a maybe-chest.
	floor_layouts = {
		1: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..a............a..M",
			"M..................M",
			"M..T...............M",
			"M..................M",
			"M..................M",
			"M.......M.M........M",
			"M.......MUM........M",
			"M.......M.M........M",
			"M.......M.M........M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M.........D........M",
			"M..................M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		2: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M..................M",
			"M..T......D........M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M.............MMM..M",
			"M...........L.MTM..M",
			"M........U....MMM..M",
			"M..................M",
			"M..................M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		3: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M.........B........M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M.........D........M",
			"M..................M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
	}

	floor_spawn_points = {
		1: {"entrance": Vector2(10, 12)},
		2: {"entrance": Vector2(5, 7)},
		3: {"entrance": Vector2(3, 7)},
	}

	floor_encounter_pools = {
		1: ["null_entity", "forgotten_variable"],
		2: ["null_entity", "forgotten_variable", "empty_set", "the_absence"],
		3: [],
	}

	# sw0: floor2's lever (12,11) -- flips open the door at (14,11) to an uncatalogued chest. Entirely optional.
	switch_effects = {"sw0": {"flip": [[14, 11]]}}
	trap_chests = ["null_chamber_f2_c1"]
	forced_item_chests = {
		"null_chamber_f1_c0": "void_dust",
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


func _get_music_area_id() -> String:
	return "abstract_dungeon"


const _LORE := {
	1: [
		{"pos": Vector2(10, 3), "text": "Two doors that lead to the same nowhere. Take whichever one you already took."},
	],
	2: [
		{"pos": Vector2(9, 8), "text": "A locked door implies a locked thing. The Curator finds this reasoning charming."},
	],
	3: [
		{"pos": Vector2(4, 7), "text": "You are the only thing in this room still being rendered."},
	],
}


func _setup_transitions_for_floor(floor_num: int) -> void:
	super._setup_transitions_for_floor(floor_num)
	for entry in (_LORE.get(floor_num, []) as Array):
		var sign := Signpost.new()
		sign.sign_text = str(entry["text"])
		sign.position = (entry["pos"] as Vector2) * TILE_SIZE
		transitions.add_child(sign)
