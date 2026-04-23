extends GutTest

## Regression: SoundManager volume setters must be safe to call before
## _setup_audio_players() has created the AudioStreamPlayer children.
##
## Prior to the fix:
##   SCRIPT ERROR: Invalid assignment of property 'volume_db' ... on a
##   base object of type 'Nil'. at: SoundManagerClass.set_music_volume
##
## SaveSystem.load_settings() runs during SaveSystem._ready() and fires
## set_music_volume / set_sfx_volume. Autoload order can put that
## before SoundManager._ready() has finished creating the players.


func test_set_music_volume_safe_before_players_exist():
	var sm = load("res://src/audio/SoundManager.gd").new()
	# Do NOT call _ready() — we want the pre-ready state where
	# _music_player is still null.
	assert_null(sm.get("_music_player"), "precondition: _music_player should be null")
	# This would have crashed before the null-guard fix.
	sm.set_music_volume(0.5)
	# And the base db should still have been latched.
	assert_ne(sm._music_base_db, -12.0, "base db should have been updated")


func test_set_sfx_volume_safe_before_players_exist():
	var sm = load("res://src/audio/SoundManager.gd").new()
	assert_null(sm.get("_ui_player"), "precondition: _ui_player should be null")
	assert_null(sm.get("_battle_player"), "precondition: _battle_player should be null")
	assert_null(sm.get("_ability_player"), "precondition: _ability_player should be null")
	# Would have crashed before the null-guard fix.
	sm.set_sfx_volume(0.5)
	# No side effects to assert — reaching this line without a crash
	# is the test.
	pass_test("set_sfx_volume did not crash on nil players")


func test_set_music_volume_normal_path_still_works():
	# A ready instance should still apply the db to the player.
	var sm = load("res://src/audio/SoundManager.gd").new()
	add_child_autofree(sm)
	await get_tree().process_frame
	sm.set_music_volume(1.0)
	# 0dB is the loudest the setter emits.
	assert_almost_eq(sm._music_player.volume_db, 0.0, 0.01, "music volume should hit 0dB at 1.0")

	sm.set_music_volume(0.0)
	assert_eq(sm._music_player.volume_db, -80.0, "music volume should hit silence at 0.0")
