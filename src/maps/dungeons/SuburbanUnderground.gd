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
	boss_cutscene_id = "world2_warden_routine"
	# (Tick 105: legacy defeat_cutscene field removed. The W2 warden defeat
	# cutscene now plays via GameLoop._get_pending_story_cutscene's gate
	# on cutscene_flag_warden_suburban_defeated in suburban_underground.)
	# Bridge to game_constants — GameLoop:840 gates world2_chapter3 on
	# `cutscene_flag_warden_suburban_defeated`. Without this declaration
	# the cutscene never triggers post-victory (same class as the Mordaine
	# scaffold bug fixed in 40c54ae).
	defeat_cutscene_flags = ["cutscene_flag_warden_suburban_defeated"]
	total_floors = 4
	overworld_exit_spawn = "from_underground"
	overworld_exit_map = "suburban_overworld"
	unlock_story_flag = "w2_dungeon_cleared"

	# struktured 2026-10-07 ("we need more maze complexity"): entrance maze -> drain-junction maze (portal pair, mimic) -> lever-gated vault maze -> warden. Corridors are 1-wide throughout; the old wrap-floor/open-hall shape is gone.
	floor_layouts = {
		1: [
			"MMMMMMMMMMMMMMMMMMMM",
			"MU..MT........MT..MM",
			"MMM.MMMMM.MMM.MMM.MM",
			"M...M.....M.......MM",
			"M.M.M.MMMMM.MMM.M.MM",
			"M...M.M.M...M...M.MM",
			"MMM.M.M.M.M.MMM.M.MM",
			"M...M.M...M.....M.MM",
			"M.MMM.M.MMM.M.MMMMMM",
			"M.....M.M...M.M...MM",
			"MMMMMMM.M.MMM.M.M.MM",
			"M.....M.M...M...M.MM",
			"M...MMM.MMMMMMMMM.MM",
			"MDM...............MM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		2: [
			"MMMMMMMMMMMMMMMMMMMM",
			"MUM.......Ma......MM",
			"M.M.M.MMM.MMM.MMM.MM",
			"M.M...........M...MM",
			"M.MMM.M.MMMMMMM.MMMM",
			"M...M.M.......M.MDMM",
			"MMM.M.MMMMM.M.M.M..M",
			"MaM.M.M.....M...M..M",
			"M.M.M.M.MMMMM.MMM.MM",
			"M...M.M.....M...M.MM",
			"M.MMM.MMMMM.MMM.M.MM",
			"M.MT..M.....M.M.M.MM",
			"M.MMMMM.MMMMM.M.M.MM",
			"M.......M.........MM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		3: [
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MM...M..........LMTM",
			"MM.M.M.MMMMMMM.M.MMM",
			"MM.M.....M...M.M.MMM",
			"MM.MMMMM.MMM.M.M.MMM",
			"MM...M.......M.M.MMM",
			"MMMM.MMMMMMM.M.MMMMM",
			"MM.M...M.....M...MMM",
			"MM.MMM.M.MMMMMMM.MMM",
			"MM.M...M..UM.....MMM",
			"MM.M.MMMMMMM.M.M.MMM",
			"MM...........MD..MMM",
			"MMMMMMMMMMMMMMM..MMM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		4: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M..................M",
			"M..................M",
			"M....MMMM..MMMM....M",
			"M....M........M....M",
			"M....M........M....M",
			"M.........B........M",
			"M....M........M....M",
			"M....M........M....M",
			"M....MMMM..MMMM....M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M.........D........M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
	}

	floor_spawn_points = {
		1: {"entrance": Vector2(2, 12)},
		2: {"entrance": Vector2(18, 7)},
		3: {"entrance": Vector2(16, 13)},
		4: {"entrance": Vector2(3, 7)},
	}

	floor_encounter_pools = {
		1: ["spiteful_crow", "unassuming_dog"],
		2: ["new_age_retro_hippie", "skate_punk", "cranky_lady"],
		3: ["unassuming_dog", "skate_punk", "cranky_lady"],
		4: [],
	}

	# sw0 is floor3's lever (16,2) -- it flips open the vault door at (17,2).
	switch_effects = {"sw0": {"flip": [[17, 2]]}}
	trap_chests = ["suburban_underground_f2_c0"]
	forced_item_chests = {
		"suburban_underground_f1_c1": "expired_coupon",
		"suburban_underground_f3_c0": "energy_drink",
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


func _get_music_area_id() -> String:
	return "suburban_dungeon"


## Phase-4 tileset: storm-drain concrete, not the medieval cave look.
func _char_to_tile_type(char: String) -> int:
	return _remap_wall_floor(char, TileGeneratorScript.TileType.SUBURBAN_WALL, TileGeneratorScript.TileType.SUBURBAN_FLOOR)


const _LORE := {
	1: [
		{"pos": Vector2(6, 1), "text": "STORM DRAIN ACCESS — Property of the Maple Heights HOA. Trespassers will be documented."},
		{"pos": Vector2(16, 1), "text": "This alcove smells like a decade of unopened mail."},
	],
	2: [
		{"pos": Vector2(17, 6), "text": "The pipes fork, double back, and fork again. Somewhere down here is the HOA's missing architect."},
	],
	3: [
		{"pos": Vector2(15, 12), "text": "The lever is labeled 'DO NOT PULL' in handwriting that is unmistakably your own."},
	],
}


func _setup_transitions_for_floor(floor_num: int) -> void:
	super._setup_transitions_for_floor(floor_num)
	for entry in (_LORE.get(floor_num, []) as Array):
		var sign := Signpost.new()
		sign.sign_text = str(entry["text"])
		sign.position = _sign_position(Vector2i(entry["pos"] as Vector2), floor_num)
		transitions.add_child(sign)
