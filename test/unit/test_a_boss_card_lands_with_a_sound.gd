extends GutTest

## 29 of the 35 boss cards slammed in silently: only the scenes that authored a play_sfx just before the card had a sound.
## The card now plays the shipped boss stinger itself, unless the step before it was the scene's own cue.

const DirectorScript = preload("res://src/cutscene/CutsceneDirector.gd")
const CARD := {"type": "boss_intro", "name": "Quiet Boss", "title": "No cue authored"}

var _d: Node


func before_each() -> void:
	SoundManager.stop_cutscene_sfx()
	for k in [DirectorScript.BOSS_CARD_CUE, "sword_draw_heavy"]:  # the per-key cooldown would swallow a cue the arm before just played
		SoundManager._sfx_cooldowns.erase(k)
	_d = DirectorScript.new()
	add_child_autofree(_d)
	_d._skipping = false


func after_each() -> void:
	SoundManager.stop_cutscene_sfx()


func _start(step: Dictionary) -> void:
	var runner := func() -> void:
		await _d._execute_step(step)
	runner.call()


func _cue_path(key: String) -> String:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sfx_manifest.json"))
	return "res://" + str((((parsed as Dictionary).get("sfx", {}) as Dictionary).get(key, {}) as Dictionary).get("file", ""))


func _playing_path() -> String:
	var p: AudioStreamPlayer = SoundManager._cutscene_player
	return p.stream.resource_path if p.playing and p.stream != null else ""


func test_a_card_with_no_cue_before_it_plays_the_stinger() -> void:
	var player: AudioStreamPlayer = SoundManager._cutscene_player
	assert_not_null(player, "PREMISE: the cutscene voice exists")
	assert_true(ResourceLoader.exists(_cue_path(DirectorScript.BOSS_CARD_CUE)), "PREMISE: the stinger is a shipped cue that loads")
	assert_false(player.playing, "CONTROL: nothing sounding before the card")
	await _d._execute_step({"type": "wait", "duration": 0.0})
	assert_false(player.playing, "CONTROL: an ordinary step plays nothing")
	_start(CARD)
	assert_eq(_playing_path(), _cue_path(DirectorScript.BOSS_CARD_CUE), "the card lands with the boss stinger")


func test_a_scene_that_scores_its_own_card_keeps_its_cue() -> void:
	await _d._execute_step({"type": "play_sfx", "sfx": "sword_draw_heavy"})
	assert_eq(_playing_path(), _cue_path("sword_draw_heavy"), "CONTROL: the scene's own cue is sounding")
	_start(CARD)
	assert_eq(_playing_path(), _cue_path("sword_draw_heavy"), "the card does not replace the cue its scene chose")


func test_a_skipped_card_is_silent() -> void:
	_d._skipping = true
	await _d._execute_step(CARD)
	assert_false(SoundManager._cutscene_player.playing, "a skipped card plays nothing")


## The data half: every boss card in the game is either scored by its scene or reached with no cue before it.
func test_no_shipped_card_doubles_its_stinger() -> void:
	var cards := 0
	var own := 0
	for f in DirAccess.get_files_at("res://data/cutscenes"):
		if not f.ends_with(".json"):
			continue
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/cutscenes/" + f))
		if not (d is Dictionary):
			continue
		var steps: Array = (d as Dictionary).get("steps", [])
		for i in steps.size():
			if str((steps[i] as Dictionary).get("type", "")) != "boss_intro":
				continue
			cards += 1
			if i > 0 and str((steps[i - 1] as Dictionary).get("type", "")) == "play_sfx":
				own += 1
			elif i > 1 and str((steps[i - 2] as Dictionary).get("sfx", "")) == DirectorScript.BOSS_CARD_CUE:
				fail_test("%s authors the stinger two steps before its card, so the card would play it again" % f)
	assert_gt(cards, 30, "CONTROL: the boss cards were found (%d)" % cards)
	assert_gt(own, 0, "CONTROL: some scenes score their own card (%d)" % own)
	assert_lt(own, cards, "and some rely on the card's own stinger (%d of %d)" % [cards - own, cards])
