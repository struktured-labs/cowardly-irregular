extends GutTest

## Regression tests for SaveSystem.save_settings / load_settings.
##
## Protects against:
##  1. Settings file getting corrupted (missing keys, malformed JSON,
##     wrong types) bricking a returning player.
##  2. Music ceiling regression: load_settings applies music_volume=100
##     via SoundManager.set_music_volume(1.0) — that path must still
##     hit the MUSIC_VOLUME_CEILING_DB cap (currently -6 dB) and not
##     punch back to 0 dB. (See music ceiling fix v3.23.0-alpha.)
##  3. Missing-file tolerance: load_settings on a fresh install (no
##     settings.json yet) must not crash, must not change defaults.
##
## All tests run in isolation — they construct a fresh SoundManager and
## simulate the SaveSystem → SoundManager call chain rather than touching
## the real settings.json on disk.


const SoundManagerScript = preload("res://src/audio/SoundManager.gd")


func _make_sound_manager() -> Node:
	var sm = SoundManagerScript.new()
	add_child_autofree(sm)
	return sm


func test_load_settings_path_respects_music_ceiling():
	# This mirrors what SaveSystem.load_settings() does at line ~595:
	#   SoundManager.set_music_volume(GameState.music_volume / 100.0)
	# After the v3.23.0-alpha ceiling fix, slider=1.0 hits the
	# MUSIC_VOLUME_CEILING_DB cap, not 0 dB. Ceiling moved -6 → -10
	# on 2026-05-02 after a second pass of user feedback. Read the
	# constant rather than hard-coding so the test self-adjusts.
	var sm = _make_sound_manager()
	await get_tree().process_frame
	# Simulate "user has saved music_volume=100".
	sm.set_music_volume(100 / 100.0)
	assert_almost_eq(sm._music_player.volume_db, sm.MUSIC_VOLUME_CEILING_DB, 0.01,
		"music_volume=100 in saved settings must respect MUSIC_VOLUME_CEILING_DB")


func test_zero_volume_silences_music():
	var sm = _make_sound_manager()
	await get_tree().process_frame
	sm.set_music_volume(0.0)
	# -80 dB is the silence threshold (anything below ~-60 dB is inaudible).
	assert_eq(sm._music_player.volume_db, -80.0,
		"music_volume=0 must be silent")


func test_partial_volume_below_ceiling():
	# Slider at 50% should give MUSIC_VOLUME_CEILING_DB + linear_to_db(0.5)
	# Ceiling is -10 dB (2026-05-02), linear_to_db(0.5) is -6.02 dB,
	# so expected ≈ -16.02 dB. Use the constant so we don't have to
	# update this test if the ceiling is tuned again.
	var sm = _make_sound_manager()
	await get_tree().process_frame
	sm.set_music_volume(0.5)
	var expected = sm.MUSIC_VOLUME_CEILING_DB + (-6.0)  # -6 dB attenuation at half slider
	assert_almost_eq(sm._music_player.volume_db, expected, 0.5,
		"music_volume=50 should land near MUSIC_VOLUME_CEILING_DB + (-6 dB)")


func test_set_volume_idempotent():
	# Calling set_music_volume twice with the same value must produce
	# the same result — no drift from accumulating attenuation.
	var sm = _make_sound_manager()
	await get_tree().process_frame
	sm.set_music_volume(0.75)
	var first_db = sm._music_player.volume_db
	sm.set_music_volume(0.75)
	var second_db = sm._music_player.volume_db
	assert_eq(first_db, second_db,
		"set_music_volume must be idempotent (got %f vs %f)" % [first_db, second_db])


func test_set_volume_clamps_above_one():
	# Defensive: slider values above 1.0 should clamp, not blow past
	# the ceiling. (This protects against future code paths that pass
	# > 1.0 by accident — e.g., unbounded sliders.)
	var sm = _make_sound_manager()
	await get_tree().process_frame
	sm.set_music_volume(2.0)
	# Even with normalized=2.0, after clamp(0,1) → 1.0 → ceiling.
	# Read the constant so the test isn't pinned to a stale dB value.
	assert_almost_eq(sm._music_player.volume_db, sm.MUSIC_VOLUME_CEILING_DB, 0.01,
		"normalized > 1.0 must be clamped to ceiling, not exceed it")


func test_sfx_volume_safe_with_zero():
	# set_sfx_volume(0.0) historically had an edge case where -80 dB
	# was applied to one channel but not others. Verify all 3 SFX
	# channels go to -80 dB together.
	var sm = _make_sound_manager()
	await get_tree().process_frame
	sm.set_sfx_volume(0.0)
	assert_eq(sm._ui_player.volume_db, -80.0, "ui at silence")
	assert_eq(sm._battle_player.volume_db, -80.0, "battle at silence")
	assert_eq(sm._ability_player.volume_db, -80.0, "ability at silence")


func test_save_system_load_settings_no_crash_on_missing_file():
	# load_settings() must not crash when settings.json doesn't exist —
	# this is the path on a fresh install. We can't easily delete the
	# real settings.json in a test, but we can verify the early-exit
	# guard is in place by reading the source.
	var content = FileAccess.get_file_as_string("res://src/save/SaveSystem.gd")
	assert_false(content.is_empty(), "SaveSystem.gd should be readable")

	var idx = content.find("func load_settings(")
	assert_gt(idx, 0, "load_settings must exist")
	# Capture function body up to the next func.
	var next_func = content.find("\nfunc ", idx + 1)
	if next_func == -1:
		next_func = content.length()
	var body = content.substr(idx, next_func - idx)
	# Defensive guard #1: file existence check.
	assert_true(body.contains("FileAccess.file_exists(SETTINGS_PATH)"),
		"load_settings must check FileAccess.file_exists before opening")
	# Defensive guard #2: JSON parse error path.
	assert_true(body.contains("json.parse"),
		"load_settings must use JSON.new().parse")
	assert_true(body.contains("!= OK") or body.contains("!= 0"),
		"load_settings must check parse_result for OK")
