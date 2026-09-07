extends GutTest

## W1 quest-wiring PR3 (2026-07-08): the last two custom-flag emitters.
## - TallyWall (thirty_seven): interactable giver in WhisperingCave floor 5;
##   first approach plays the Warden encounter cutscene (which had NO trigger
##   anywhere — the quest prereq could never fire), then offers the quest;
##   accepting emits the step-1 tally_examined flag; post-completion 38th-mark
##   ritual choice.
## - SwordInscription (untested_edge path A): Mage light-spell at Bram's rack.
## - DIALOGUE_EMITTERS (untested_edge path B): guild scholar translation.
## - untested_edge prereq restored (temp gate lifted).
## With these, ALL 6 W1 side quests are playable (chapter_three's telemetry
## shipped earlier in BattleManager — confirmed msgs 2291/2293/2294/2295).

const TallyWallScript := preload("res://src/exploration/TallyWall.gd")
const SwordScript := preload("res://src/exploration/SwordInscription.gd")

var _qs: Node


func before_each() -> void:
	_qs = get_tree().root.get_node_or_null("QuestSystem")
	GameState.quests.clear()
	for f in ["world1_warden_encounter_complete",
			"quest_world1_thirty_seven_tally_examined",
			"quest_world1_thirty_seven_mark_added",
			"quest_world1_untested_edge_inscription_read",
			"quest_world1_untested_edge_accepted",
			"cutscene_flag_rat_king_defeated"]:
		GameState.set_story_flag(f, false)
	if "cutscene_flag_world1_warden_encounter_complete" in GameState.game_constants:
		GameState.game_constants.erase("cutscene_flag_world1_warden_encounter_complete")


func after_each() -> void:
	before_each()


func test_untested_edge_prereq_restored() -> void:
	var q: Dictionary = _qs.get_quest("world1_untested_edge")
	assert_eq(q.get("prereq_flag", ""), "cutscene_flag_rat_king_defeated",
		"temp gate quest_wiring_light_spell_ready must be lifted — both emitters now exist")
	GameState.set_story_flag("cutscene_flag_rat_king_defeated")
	assert_true(_qs.is_offerable("world1_untested_edge"))


func test_thirty_seven_prereq_satisfiable_via_wall_cutscene() -> void:
	# The Warden encounter cutscene sets world1_warden_encounter_complete
	# (mirrored to cutscene_flag_*). Pre-PR3 nothing triggered that cutscene —
	# TallyWall's first-approach examine is now the trigger. Simulate the
	# cutscene's flag write and confirm the quest becomes offerable.
	assert_false(_qs.is_offerable("world1_thirty_seven"), "gated before the encounter")
	GameState.set_story_flag("cutscene_flag_world1_warden_encounter_complete")
	assert_true(_qs.is_offerable("world1_thirty_seven"), "offerable after the encounter beat")


func test_tally_wall_is_the_cutscene_trigger() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/exploration/TallyWall.gd")
	assert_true(src.contains("world1_warden_encounter"),
		"TallyWall must play the warden encounter cutscene on first approach — it had no other trigger")
	var cave: String = FileAccess.get_file_as_string("res://src/maps/dungeons/WhisperingCave.gd")
	assert_true(cave.contains("TallyWall"), "WhisperingCave must place the wall (floor 5)")


func test_tally_wall_giver_identity_matches_quest() -> void:
	var wall = TallyWallScript.new()
	assert_eq(wall.npc_id, "warden_tally_wall",
		"wall giver id must match thirty_seven's giver.npc_id")
	wall.free()
	var q: Dictionary = _qs.get_quest("world1_thirty_seven")
	assert_eq(q.get("giver", {}).get("npc_id", ""), "warden_tally_wall")


func test_sword_mage_path_emits_and_advances() -> void:
	GameState.set_story_flag("cutscene_flag_rat_king_defeated")
	_qs.accept("world1_untested_edge")
	# accept auto-completes step 1 (talk-to-giver bram) → custom step (idx 1)
	assert_eq(_qs.get_objective_index("world1_untested_edge"), 1)
	# The rack emits (simulating a successful Mage examine: flag + notify)
	GameState.set_story_flag("quest_world1_untested_edge_inscription_read")
	_qs.notify_flag("quest_world1_untested_edge_inscription_read")
	assert_eq(_qs.get_objective_index("world1_untested_edge"), 2,
		"inscription flag completes step 2 → turn-in step")


func test_scholar_dialogue_emitter_path() -> void:
	GameState.set_story_flag("cutscene_flag_rat_king_defeated")
	_qs.accept("world1_untested_edge")
	assert_eq(_qs.get_objective_index("world1_untested_edge"), 1)
	# Path B: simply TALKING to the guild scholar mid-quest satisfies step 2.
	_qs.notify_talk("guild_scholar_scriptura")
	assert_true(GameState.get_story_flag("quest_world1_untested_edge_inscription_read"),
		"scholar dialogue-emitter must set the inscription flag")
	assert_eq(_qs.get_objective_index("world1_untested_edge"), 2)


func test_dialogue_emitter_inert_when_quest_inactive() -> void:
	# Talking to the scholar with no active quest must NOT set the flag.
	_qs.notify_talk("guild_scholar_scriptura")
	assert_false(GameState.get_story_flag("quest_world1_untested_edge_inscription_read"),
		"emitter only fires while the quest is active at its custom step")


func test_sword_placement_and_cues() -> void:
	var harmonia: String = FileAccess.get_file_as_string("res://src/maps/villages/HarmoniaVillage.gd")
	assert_true(harmonia.contains("SwordInscription"), "Harmonia places the sword rack by Bram")
	var sword: String = FileAccess.get_file_as_string("res://src/exploration/SwordInscription.gd")
	assert_true(sword.contains("magic_surge"), "Mage light path uses the magic_surge cue")
	var wall: String = FileAccess.get_file_as_string("res://src/exploration/TallyWall.gd")
	assert_true(wall.contains("chalk_tap"), "38th mark uses the chalk_tap cue")
