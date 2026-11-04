extends GutTest

## struktured 2026-11-02 at 6c52c19aa: "didn't hear an accept quest ditty". The accept chime was wired but went
## to the shared _ui_player at -16 dB, where the giver's accept lines' menu_select replaced it. It now plays on
## its own player, ducks the bed briefly, and releases.


func test_accepting_a_quest_plays_the_jingle_on_its_own_player_and_ducks() -> void:
	var host := Node.new()
	add_child_autofree(host)
	var tracker := QuestTracker.new()
	host.add_child(tracker)
	tracker.setup(host)
	await get_tree().process_frame
	SoundManager._sfx_cooldowns.erase("quest_accept")
	assert_eq(SoundManager.get_jingle_duck_db(), 0.0, "PREMISE: the bed starts unducked")
	tracker._on_quest_progress("some_quest", "active")
	var jp: AudioStreamPlayer = SoundManager._jingle_player
	assert_not_null(jp.stream, "the accept ditty loaded onto the jingle player")
	assert_true(str(jp.stream.resource_path).ends_with("quest_accept.ogg"), "it is quest_accept: %s" % jp.stream.resource_path)
	assert_true(jp.playing, "the ditty is playing")
	SoundManager.play_ui("menu_select")
	assert_true(jp.playing, "a menu blip right after (the accept lines) no longer cuts it")
	await get_tree().create_timer(0.3).timeout
	assert_lt(SoundManager.get_jingle_duck_db(), -6.0, "the bed is ducked under the ditty")
	await get_tree().create_timer(2.0).timeout
	assert_almost_eq(SoundManager.get_jingle_duck_db(), 0.0, 0.01, "the duck releases back to unity")
