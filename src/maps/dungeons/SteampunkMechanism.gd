extends DragonCave
class_name SteampunkMechanismScene

## Steampunk Mechanism — W3 dungeon.
## Below Brasston, under the industrial district, lies the Grand Mechanism.
## Endless brass cogs and pneumatic arms. The Meta Knight guards the
## central gearwork, convinced the whole apparatus is aware of being watched.

func _init() -> void:
	cave_name = "The Grand Mechanism"
	cave_id = "steampunk_mechanism"
	# Was "meta_knight" — a level-matched placeholder (both L11) never swapped back. Three
	# signals said Tempo the whole time: the intro cutscene below, the defeat flag below, and
	# boss_tempo_steampunk.ogg composed on disk yet unreachable because meta_knight carries no
	# masterite_type, so BattleScene's masterite music branch silently fell through to generic.
	# meta_knight remains a steampunk pool enemy + Castle Harmonia F3 — nothing orphaned.
	boss_id = "masterite_tempo_steampunk"
	boss_flag_key = "steampunk_mechanism_cleared"
	# W3 fights The Grand Schedule; world3_tempo_intro is the INDUSTRIAL Tempo's scene (trigger boss_tempo_industrial).
	boss_cutscene_id = "world3_grand_schedule_intro"
	# (Tick 105: defeat_cutscene removed — see DragonCave for rationale.
	# The W3 tempo defeat plays via the GameLoop gate on
	# cutscene_flag_tempo_steampunk_defeated in steampunk_mechanism.)
	# Bridge to game_constants — GameLoop:1067 gates world3_chapter4 on
	# `cutscene_flag_tempo_steampunk_defeated`. Pre-tick-96 the gate
	# was checking `warden_industrial_defeated` (a W4 flag), so W3
	# chapter4 only triggered AFTER the player beat W4's AssemblyCore
	# boss — skipping the W3 narrative closer entirely.
	defeat_cutscene_flags = ["cutscene_flag_tempo_steampunk_defeated"]
	total_floors = 4
	overworld_exit_spawn = "from_mechanism"
	overworld_exit_map = "steampunk_overworld"
	unlock_story_flag = "w3_dungeon_cleared"

	# struktured 2026-10-07 ("we need more maze complexity"): entrance maze -> gear-cell maze (two lever-vaults) -> catwalk maze with a portal shortcut -> Tempo. Corridors are 1-wide throughout; the old wide-open halls are gone.
	floor_layouts = {
		1: [
			"MMMMMMMMMMMMMMMMMMMM",
			"MT....MTM.........MM",
			"MMMMM.M.M.MMMMM.M.MM",
			"M..DM.M...M.M...M.MM",
			"M..MM.M.MMM.M.MMM.MM",
			"M.M...M.....M.M...MM",
			"M.M.MMM.M.M.M.MMM.MM",
			"M.M.M...M.......M.MM",
			"M.M.M.M.M.MMMMM.M.MM",
			"M.M...M.M...M...MUMM",
			"M.MMMMM.MMM.M.MMMMMM",
			"M.M...M.M...M.....MM",
			"M.M.M.M.MMMMMMMMM.MM",
			"M...M.............MM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		2: [
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMU..MD......M..LMTM",
			"MMMM.MM..MMM.M.M.MMM",
			"MM.M.M.........MLMTM",
			"MM.M.M.MMM.MMM.M.MMM",
			"MM.M.M.........M.MMM",
			"MM.M.MMMMMMMMM.M.MMM",
			"MM.M...M.....M.M.MMM",
			"MM.MMM.M.MMM.MMM.MMM",
			"MM...M.M...M.M...MMM",
			"MM.MMM.MMM.M.M.M.MMM",
			"MM.........M...M.MMM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		3: [
			"MMMMMMMMMMMMMMMMMMMM",
			"MU......M...M.....MM",
			"MMMMMMM.M.M.M.MMM.MM",
			"M...MDM...M...MaM.MM",
			"M.M.M..MMMMMMMM.M.MM",
			"M.M.M...........M.MM",
			"M.M.M.M.MMMMMMM.M.MM",
			"M.M...M.M.......M.MM",
			"M.MMMMM.M.MMMMM.M.MM",
			"M.M...M.M...Ma..M.MM",
			"M.M.M.M.MMM.MMM.M.MM",
			"M.M.M.M...M.M.....MM",
			"M.M.M.M.M.M.M.MMMMMM",
			"M...M.....M.......MM",
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
		1: {"entrance": Vector2(2, 4)},
		2: {"entrance": Vector2(8, 3)},
		3: {"entrance": Vector2(6, 5)},
		4: {"entrance": Vector2(3, 7)},
	}

	floor_encounter_pools = {
		1: ["steam_rat", "cog_swarm"],
		2: ["clockwork_sentinel", "pipe_phantom", "brass_golem"],
		3: ["cog_swarm", "clockwork_sentinel", "brass_golem"],
		4: [],
	}

	# sw0 (lever 16,2 -> door 17,2) and sw1 (lever 16,4 -> door 17,4): optional gear-cell vault detours, neither gates the main route.
	switch_effects = {
		"sw0": {"flip": [[17, 2]]},
		"sw1": {"flip": [[17, 4]]},
	}
	trap_chests = ["steampunk_mechanism_f2_c0"]
	forced_item_chests = {
		"steampunk_mechanism_f1_c1": "gear_cog",
		"steampunk_mechanism_f2_c1": "spring_coil",
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


func _get_music_area_id() -> String:
	return "steampunk_dungeon"


## Phase-4 tileset: brass/rivets/pipes, not the medieval cave look.
func _char_to_tile_type(char: String) -> int:
	return _remap_wall_floor(char, TileGeneratorScript.TileType.STEAMPUNK_WALL, TileGeneratorScript.TileType.STEAMPUNK_FLOOR)


func _get_ambient_fx_theme() -> String:
	return "steam"


const _LORE := {
	1: [
		{"pos": Vector2(2, 1), "text": "A brass plaque: 'THE MECHANISM HAS ALWAYS BEEN RUNNING. NOBODY REMEMBERS STARTING IT.'"},
		{"pos": Vector2(7, 2), "text": "This alcove ticks in 7/8 time. So does your pulse, now."},
	],
	2: [
		{"pos": Vector2(7, 2), "text": "Two levers, two vaults. The Mechanism insists this is a choice, and technically it is."},
	],
	3: [
		{"pos": Vector2(5, 4), "text": "The portal pads skip half the catwalk. Nobody has explained why they were ever installed on a floor with a catwalk."},
	],
}


## world3_before_the_regulator step 2. The authored note puts it ON the main-quest
## dungeon route with no separate unlock, so it rides the existing floor-2 corridor.
func _setup_transitions_for_floor(floor_num: int) -> void:
	super._setup_transitions_for_floor(floor_num)
	for entry in (_LORE.get(floor_num, []) as Array):
		var sign := Signpost.new()
		sign.sign_text = str(entry["text"])
		sign.position = _sign_position(Vector2i(entry["pos"] as Vector2), floor_num)
		transitions.add_child(sign)
	if floor_num != 2:
		return
	var ExamineScript = load("res://src/exploration/QuestExaminePoint.gd")
	if ExamineScript == null:
		return
	var junction = ExamineScript.new()
	junction.quest_id = "world3_before_the_regulator"
	junction.flag = "quest_world3_before_the_regulator_junction_traced"
	junction.indicator_text = "%s Trace the junction" % InputProfileManager.hint_for_action("ui_accept")
	junction.examine_text = "One conduit runs the wrong way — carrying out, not in. The Mechanism is not being controlled from here. It is being LISTENED to, by something that was receiving long before the Regulator was appointed."
	junction.idle_text = "Brass conduit converges at a junction box, humming slightly out of time with the floor."
	junction.position = Vector2(4 * TILE_SIZE, 7 * TILE_SIZE)
	transitions.add_child(junction)
