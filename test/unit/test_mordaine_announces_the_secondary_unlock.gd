extends GutTest

## #763: the secondary-job unlock is announced by Mordaine (unnamed, voiced), not a system popup.
## Pins: the gate fires once, in the cave, after the Rat King scene; saves already past chapter4
## skip it; it is above the demo boundary; every line she says resolves to a recorded clip.

const GAME_LOOP := "res://src/GameLoop.gd"
const SCENE := "res://data/cutscenes/world1_mordaine_secondary_unlock.json"
const SoundManagerScript := preload("res://src/audio/SoundManager.gd")


func _body() -> String:
	var src: String = FileAccess.get_file_as_string(GAME_LOOP)
	var idx: int = src.find("func _get_pending_story_cutscene")
	assert_gt(idx, -1)
	var nxt: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, nxt - idx)


func test_gate_once_after_rat_king_scene_and_skipped_for_old_saves() -> void:
	var body := _body()
	var gate: String = ("if flags.get(\"cutscene_flag_world1_rat_king_defeat_complete\", false) "
		+ "and not flags.get(\"cutscene_flag_world1_mordaine_secondary_unlock_complete\", false) "
				+ "and not flags.get(\"cutscene_flag_demo_end_complete\", false):")
	assert_true(body.contains(gate), "gate must follow the Rat King scene, close on its own flag, and skip post-chapter4 saves")
	var ret: int = body.find("return \"world1_mordaine_secondary_unlock\"")
	assert_gt(ret, -1)
	assert_true(body.substr(max(0, ret - 120), 120).contains("_current_map_id == \"whispering_cave\""))
	assert_lt(body.find("return \"world1_rat_king_defeat\""), ret, "plays after the Rat King's own scene")
	assert_lt(ret, body.find("return \"demo_end\""), "the demo, which ends at this fight, still hears it")


func test_completion_flag_registered() -> void:
	var src: String = FileAccess.get_file_as_string(GAME_LOOP)
	assert_true(src.contains("\"world1_mordaine_secondary_unlock\": \"cutscene_flag_world1_mordaine_secondary_unlock_complete\""),
		"a missing completion entry replays the beat on every cave entry")


func test_every_line_is_voiced_in_mordaines_voice() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(SCENE))
	assert_true(data is Dictionary, "scene JSON parses")
	var spoken := 0
	for step in data["steps"]:
		if str(step.get("type", "")) != "dialogue":
			continue
		for line in step["lines"]:
			var key: String = SoundManagerScript.voiced_line_clip(str(line["speaker"]), str(line["text"]))
			assert_ne(key, "", "unvoiced line: %s" % line["text"])
			assert_true(key.begins_with("boss_line_mordaine_unlock_"), "voiced by her clip, not another speaker's: %s" % key)
			assert_true(FileAccess.file_exists("res://assets/audio/sfx/%s.ogg" % key), "clip on disk: %s" % key)
			spoken += 1
	assert_between(spoken, 3, 6, "3-6 lines")


func test_old_saves_past_chapter4_retire_the_beat_at_load() -> void:
	var src: String = FileAccess.get_file_as_string(GAME_LOOP)
	var r: int = src.find("func _restore_party_from_save_data")
	assert_gt(r, -1)
	assert_true(src.substr(r, src.find("\nfunc ", r + 1) - r).contains("_retire_secondary_unlock_beat_for_old_saves()"), "every load path restores through here")
	var gs = get_node_or_null("/root/GameState")
	assert_not_null(gs)
	var saved: Dictionary = gs.game_constants.duplicate(true)
	var gl = load(GAME_LOOP).new()
	gs.game_constants = {"cutscene_flag_chapter4_complete": true}
	gl._retire_secondary_unlock_beat_for_old_saves()
	assert_true(gs.game_constants.get("cutscene_flag_world1_mordaine_secondary_unlock_complete", false), "old save past chapter4: beat closed")
	gs.game_constants = {"cutscene_flag_world1_rat_king_defeat_complete": true}
	gl._retire_secondary_unlock_beat_for_old_saves()
	assert_false(gs.game_constants.get("cutscene_flag_world1_mordaine_secondary_unlock_complete", false), "save still in the cave: beat stays pending")
	gs.game_constants = saved
	gl.free()
