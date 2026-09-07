extends DragonCave
class_name ContrarianDepthsScene

## The Backwards Warren -- W1 optional side dungeon showcasing every DungeonPuzzleLayer mechanic (struktured 2026-09-06).
## Portal 'b' (floor3 deep <-> floor1 sealed wing, "down to go up"), portal 'c' (sealed wing <-> floor4, gated by sw0's reveal).
## Floor2 wraps (infinite field) and hides sw1, a plate that warps randomly; floor3's sw2 lever opens portal b's wall, sw3 plate is a decoy trap.
## portal_links stays empty here (both portals auto-pair on 2 occurrences); the override table is exercised by the regression test instead.

func _init() -> void:
	cave_name = "The Backwards Warren"
	cave_id = "backwards_warren"
	boss_id = "cartographer_wraith"
	boss_flag_key = "cartographer_wraith_defeated"
	boss_cutscene_id = "world1_cartographer_wraith_intro"
	total_floors = 4
	overworld_exit_spawn = "backwards_warren_cave"

	floor_layouts = {
		1: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M.............MMMMMM",
			"M.............Mb..LM",
			"M.....T.......M.T..M",
			"M.............M...cM",
			"M.............MMMMMM",
			"M.............MMMMMM",
			"M.............MMMMMM",
			"M.............MMMMMM",
			"M.............MMMMMM",
			"M.............MMMMMM",
			"M.............MMMMMM",
			"M.............MMMMMM",
			"M..D........U.MMMMMM",
			"M.............MMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		2: [
			"....................",
			"....................",
			"..........D.........",
			"...T................",
			"....................",
			"....................",
			"....................",
			"....................",
			"....................",
			"....................",
			"....................",
			"....................",
			"............S.......",
			"..........U.........",
			"....................",
			"....................",
		],
		3: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M.............M....M",
			"M.............M....M",
			"M.............M..b.M",
			"M.............M....M",
			"M.............M....M",
			"M.............M....M",
			"M......L......M....M",
			"M.............M....M",
			"M...........M.M....M",
			"M...........S.M.T..M",
			"M.............M....M",
			"M.............M....M",
			"M..D..........M....M",
			"M.............M....M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		4: [
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M..................M",
			"M..c............B..M",
			"M..................M",
			"M..................M",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
		],
	}

	floor_spawn_points = {
		1: {"entrance": Vector2(6, 13)},
		2: {"entrance": Vector2(10, 7)},
		3: {"entrance": Vector2(6, 13)},
		4: {"entrance": Vector2(3, 8)},
	}

	floor_encounter_pools = {
		1: ["bat", "goblin"],
		2: ["bat", "goblin", "skeleton"],
		3: ["skeleton", "goblin"],
		4: [],
	}

	# sw0=floor1 lever(18,2) sw1=floor2 plate(16,12) sw2=floor3 lever(7,7) sw3=floor3 plate(12,10) -- scan_switches' positional order.
	switch_effects = {
		"sw0": {"reveal": "portal_c"},
		"sw1": {"trap": "warp"},
		"sw2": {"flip": [[14, 3], [14, 4]]},
		"sw3": {"flip": [[12, 9]], "trap": "encounter"},
	}

	trap_chests = ["backwards_warren_f1_c1"]
	forced_item_chests = {
		"backwards_warren_f1_c0": "ether",
		"backwards_warren_f2_c0": "elixir",
		"backwards_warren_f3_c0": "hi_potion",
	}
	wrap_floors = [2]


const _LORE := {
	1: [
		{"pos": Vector2(6, 10), "text": "The Backwards Warren: mapped in reverse by a cartographer fired for accuracy."},
		{"pos": Vector2(13, 3), "text": "Sealed wing. The keys are also in the sealed wing. Efficient, everyone agreed, before agreeing to seal it."},
	],
	2: [
		{"pos": Vector2(6, 6), "text": "You have left the map. The map, for its part, does not miss you."},
	],
	3: [
		{"pos": Vector2(9, 7), "text": "Pull. Or don't. The warren has never once cared what you decide."},
		{"pos": Vector2(10, 10), "text": "This plate looks load-bearing. It is bearing a grudge."},
	],
	4: [
		{"pos": Vector2(9, 8), "text": "The cartographer's final note, underlined twice: 'the exit is through the entrance.' They fired her for it. She was right."},
	],
}


func _setup_transitions_for_floor(floor_num: int) -> void:
	super._setup_transitions_for_floor(floor_num)
	for entry in (_LORE.get(floor_num, []) as Array):
		var sign := Signpost.new()
		sign.sign_text = str(entry["text"])
		sign.position = (entry["pos"] as Vector2) * TILE_SIZE
		transitions.add_child(sign)


## Explicit "cave" -- W1 medieval dungeons must say so, per test_non_medieval_dungeons_must_override_the_music_key.
func _get_music_area_id() -> String:
	return "cave"


func _get_boss_intro_dialogue() -> Array:
	return [
		"The corridor behind you seals. Ink-stained ribbons drift in a wind that isn't there.",
		"The Lost Cartographer: 'You found the shortcut. Nobody finds the shortcut.'",
		"The Lost Cartographer: 'I drew it in on my last day, out of spite. The only honest line in the whole warren.'",
		"",
		"Hero: 'So none of this was supposed to connect?'",
		"",
		"The Lost Cartographer: 'None of it was supposed to be BUILT. I was a cartographer, not an architect. They made me draw it anyway.'",
		"The Lost Cartographer: 'Let's see if you read the map better than they did.'",
	]
