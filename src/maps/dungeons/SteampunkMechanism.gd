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


func _get_music_area_id() -> String:
	return "steampunk_dungeon"


## world3_before_the_regulator step 2. The authored note puts it ON the main-quest
## dungeon route with no separate unlock, so it rides the existing floor-2 corridor.
func _setup_transitions_for_floor(floor_num: int) -> void:
	super._setup_transitions_for_floor(floor_num)
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
