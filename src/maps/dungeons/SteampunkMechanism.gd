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
	boss_cutscene_id = "world3_tempo_intro"
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
	overworld_exit_spawn = "plaza"
	overworld_exit_map = "steampunk_overworld"
	unlock_story_flag = "w3_dungeon_cleared"

	# struktured 2026-09-06: 4 floors now — entrance -> Gear Room (two lever-vaults) -> catwalk with a portal shortcut -> Tempo.
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
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M..................M",
			"M...D..............M",
			"M..................M",
			"M..................M",
			"MMMM...............M",
			"MMTM.L.............M",
			"MMMM...............M",
			"M..................M",
			"M.............U....M",
			"M..............MMM.M",
			"M............L.MTM.M",
			"M..............MMM.M",
			"M..................M",
			"MMMMMMMMMMMMMMMMMMMM",
		],
		3: [
			"MMMMMMMMMMMMMMMMMMMM",
			"M..................M",
			"M..................M",
			"M..................M",
			"M.............U....M",
			"M..................M",
			"M..................M",
			"M..a............a..M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M..................M",
			"M...D..............M",
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
		2: {"entrance": Vector2(13, 12)},
		3: {"entrance": Vector2(13, 12)},
		4: {"entrance": Vector2(3, 7)},
	}

	floor_encounter_pools = {
		1: ["steam_rat", "cog_swarm"],
		2: ["clockwork_sentinel", "pipe_phantom", "brass_golem"],
		3: ["cog_swarm", "clockwork_sentinel", "brass_golem"],
		4: [],
	}

	# sw0 (lever 5,7 -> door 3,7) and sw1 (lever 13,12 -> door 15,12): optional walkway-vault detours, neither gates the main route.
	switch_effects = {
		"sw0": {"flip": [[3, 7]]},
		"sw1": {"flip": [[15, 12]]},
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


const _LORE := {
	1: [
		{"pos": Vector2(3, 6), "text": "A brass plaque: 'THE MECHANISM HAS ALWAYS BEEN RUNNING. NOBODY REMEMBERS STARTING IT.'"},
		{"pos": Vector2(16, 6), "text": "This alcove ticks in 7/8 time. So does your pulse, now."},
	],
	2: [
		{"pos": Vector2(6, 10), "text": "Two levers, two vaults. The Mechanism insists this is a choice, and technically it is."},
	],
	3: [
		{"pos": Vector2(9, 10), "text": "The portal pads skip half the catwalk. Nobody has explained why they were ever installed on a floor with a catwalk."},
	],
}


## world3_before_the_regulator step 2. The authored note puts it ON the main-quest
## dungeon route with no separate unlock, so it rides the existing floor-2 corridor.
func _setup_transitions_for_floor(floor_num: int) -> void:
	super._setup_transitions_for_floor(floor_num)
	for entry in (_LORE.get(floor_num, []) as Array):
		var sign := Signpost.new()
		sign.sign_text = str(entry["text"])
		sign.position = (entry["pos"] as Vector2) * TILE_SIZE
		transitions.add_child(sign)
	if floor_num != 2:
		return
	var ExamineScript = load("res://src/exploration/QuestExaminePoint.gd")
	if ExamineScript == null:
		return
	var junction = ExamineScript.new()
	junction.quest_id = "world3_before_the_regulator"
	junction.flag = "quest_world3_before_the_regulator_junction_traced"
	junction.indicator_text = "[A] Trace the junction"
	junction.examine_text = "One conduit runs the wrong way — carrying out, not in. The Mechanism is not being controlled from here. It is being LISTENED to, by something that was receiving long before the Regulator was appointed."
	junction.idle_text = "Brass conduit converges at a junction box, humming slightly out of time with the floor."
	junction.position = Vector2(4 * TILE_SIZE, 7 * TILE_SIZE)
	transitions.add_child(junction)
