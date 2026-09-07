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
	overworld_exit_spawn = "entrance"
	overworld_exit_map = "suburban_overworld"
	unlock_story_flag = "w2_dungeon_cleared"

	# struktured 2026-09-06: 4 floors now — entrance -> endless parking (wrap, portal, mimic) -> lever-gated vault maze -> warden.
	floor_layouts = {
		1: [
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MM...MMMMMMMMMM...MM",
			"MM.T.MMMMMMMMMM.T.MM",
			"MM...MMMMMMMMMM...MM",
			"MMM.MMMMMMMMMMMM.MMM",
			"M..................M",
			"M..................M",
			"MMMMMMMMM..MMMMMMMMM",
			"MMMMMMMMM.U.MMMMMMMM",
			"MMMMMMMMM...MMMMMMMM",
			"MMMMMMMMM..MMMMMMMMM",
			"M..................M",
			"M.........D........M",
			"M..................M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		2: [
			"....................",
			"....................",
			"..M..............M..",
			".....D..........a...",
			"....................",
			"...M.....M.M........",
			"....................",
			".....M....T...M.....",
			"....................",
			".....M........M.....",
			"....................",
			".........M.M....M...",
			"...a..........U.....",
			"..M...............M.",
			"....................",
			"....................",
		],
		3: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M..................M",
			"MMMM...............M",
			"MMTM.L.............M",
			"MM.M...M..MM.......M",
			"MMMM...M.U.M.......M",
			"M......M...M.......M",
			"M......M..MM.......M",
			"M....D.............M",
			"M..................M",
			"M..................M",
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
		1: {"entrance": Vector2(10, 12)},
		2: {"entrance": Vector2(10, 10)},
		3: {"entrance": Vector2(9, 12)},
		4: {"entrance": Vector2(3, 7)},
	}

	floor_encounter_pools = {
		1: ["spiteful_crow", "unassuming_dog"],
		2: ["new_age_retro_hippie", "skate_punk", "cranky_lady"],
		3: ["unassuming_dog", "skate_punk", "cranky_lady"],
		4: [],
	}

	# Floor 2, "Level P-Infinity": edge-wraps; two 'a' decals auto-pair as a shortcut.
	wrap_floors = [2]
	# sw0 is floor3's lever (5,7) -- it flips open the vault door at (3,7).
	switch_effects = {"sw0": {"flip": [[3, 7]]}}
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


const _LORE := {
	1: [
		{"pos": Vector2(3, 6), "text": "STORM DRAIN ACCESS — Property of the Maple Heights HOA. Trespassers will be documented."},
		{"pos": Vector2(16, 6), "text": "This alcove smells like a decade of unopened mail."},
	],
	2: [
		{"pos": Vector2(10, 10), "text": "LEVEL P-INFINITY. Your car is not here. Your car was never here."},
	],
	3: [
		{"pos": Vector2(5, 6), "text": "The lever is labeled 'DO NOT PULL' in handwriting that is unmistakably your own."},
	],
}


func _setup_transitions_for_floor(floor_num: int) -> void:
	super._setup_transitions_for_floor(floor_num)
	for entry in (_LORE.get(floor_num, []) as Array):
		var sign := Signpost.new()
		sign.sign_text = str(entry["text"])
		sign.position = (entry["pos"] as Vector2) * TILE_SIZE
		transitions.add_child(sign)
