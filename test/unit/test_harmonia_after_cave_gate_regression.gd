extends GutTest

## Task #27 (struktured 2026-07-15): "when I go back to village, I want
## another puppet style cutscene after defeating the rat king."
## cowir-story authored world1_harmonia_after_cave (75 steps, staged);
## this pins the engine-side gate wiring.

const GAME_LOOP := "res://src/GameLoop.gd"


func _detached_loop():
	var gl = load(GAME_LOOP).new()
	autofree(gl)
	return gl


func before_each() -> void:
	GameState.game_constants.clear()


func after_each() -> void:
	GameState.game_constants.clear()


func test_scene_fires_on_first_harmonia_entry_post_rat_king() -> void:
	var gl = _detached_loop()
	gl._current_map_id = "harmonia_village"
	GameState.game_constants["cutscene_flag_prologue_complete"] = true
	GameState.game_constants["talked_to_theron"] = true
	GameState.game_constants["cutscene_flag_chapter1_complete"] = true
	GameState.game_constants["cutscene_flag_spotlight_unlocked_cleric"] = true
	GameState.game_constants["cutscene_flag_chapter2_complete"] = true
	GameState.game_constants["cutscene_flag_chapter3_complete"] = true
	GameState.game_constants["cutscene_flag_spotlight_unlocked_rogue"] = true
	GameState.game_constants["cutscene_flag_spotlight_unlocked_mage"] = true
	GameState.game_constants["cutscene_flag_spotlight_unlocked_fighter"] = true
	GameState.game_constants["cutscene_flag_rat_king_defeated"] = true
	GameState.game_constants["cutscene_flag_world1_rat_king_defeat_complete"] = true
	GameState.game_constants["cutscene_flag_chapter4_complete"] = true
	assert_eq(gl._get_pending_story_cutscene(), "world1_harmonia_after_cave",
		"village-reaction scene must win the FIRST Harmonia entry post-Rat-King (above the Bard gate)")
	# After the scene completes, Bard's spotlight takes the next entry.
	GameState.game_constants["cutscene_flag_world1_harmonia_after_cave_complete"] = true
	assert_eq(gl._get_pending_story_cutscene(), "world1_spotlight_bard_ch7",
		"Bard spotlight follows on the next Harmonia visit")


func test_completion_flag_mapped() -> void:
	var gl = _detached_loop()
	assert_eq(str(gl._CUTSCENE_COMPLETION_FLAGS.get("world1_harmonia_after_cave", "")),
		"cutscene_flag_world1_harmonia_after_cave_complete",
		"missing completion-flag mapping = the infinite-replay loop bug class (Elder Theron)")


func test_json_exists_staged_and_uses_real_archetypes() -> void:
	var raw := FileAccess.get_file_as_string("res://data/cutscenes/world1_harmonia_after_cave.json")
	assert_true(raw.length() > 0, "cutscene JSON must ship")
	var d: Dictionary = JSON.parse_string(raw)
	assert_eq(str(d.get("presentation", "")), "staged", "must be a staged (puppet) scene per the ask")
	for s in d.get("steps", []):
		if s.get("type", "") == "spawn_actor" and s.get("kind", "") == "npc":
			var arc: String = str(s.get("archetype", ""))
			assert_true(DirAccess.dir_exists_absolute("res://assets/sprites/npcs/" + arc),
				"archetype '%s' must exist on disk — a missing sheet falls back to the cursed proc-gen chibi" % arc)
