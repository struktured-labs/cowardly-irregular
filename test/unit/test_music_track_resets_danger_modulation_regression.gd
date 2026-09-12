extends GutTest

## Bug 2026-07-04: the danger-intensity system elevates _music_player's
## pitch_scale (up to 1.15) and volume during a tense battle. play_music
## didn't fully reset that when starting a new track — the cache branch
## reset NEITHER, the manifest branch reset only volume — so after a
## low-HP fight the next track could play higher-pitched and/or louder
## until something else reset it. play_music now resets pitch + volume to
## the clean base for every branch, once, after the crossfade copy.

const SM := preload("res://src/audio/SoundManager.gd")


func _fresh_sm():
	var sm = SM.new()
	add_child_autofree(sm)
	return sm


func test_new_track_clears_stale_danger_pitch_and_volume() -> void:
	var sm = _fresh_sm()
	if sm._music_player == null:
		pass_test("no music player in this env")
		return
	sm._music_base_db = -18.0
	# Simulate danger modulation left on the player from a prior tense battle.
	sm._music_player.pitch_scale = 1.15
	sm._music_player.volume_db = -5.0
	# Cache a dummy track so play_music takes the early-return cache branch
	# (the branch that reset nothing before this fix).
	sm._music_cache["unit_test_track"] = AudioStreamWAV.new()
	sm.play_music("unit_test_track")
	assert_almost_eq(sm._music_player.pitch_scale, 1.0, 0.001,
		"a new track must reset the danger pitch elevation (1.15 → 1.0)")
	assert_almost_eq(sm._music_player.volume_db, -18.0, 0.01,
		"a new track must reset to the user's base volume, not inherit the danger boost")


func test_the_clean_slate_precedes_branch_dispatch() -> void:
	# Source pin: the reset must sit before the manifest/cache/generated
	# branches so ALL of them get the clean slate, not just one. The reset
	# is reset_danger() since 8a15eef1 (play_area_music needs it too), so
	# the second assert keeps this from passing on an empty function.
	var src: String = FileAccess.get_file_as_string("res://src/audio/SoundManager.gd")
	var fn: int = src.find("func play_music")
	var body: String = src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	var reset_idx: int = body.find("reset_danger()")
	var manifest_idx: int = body.find("_try_play_from_manifest")
	var cache_idx: int = body.find("_music_cache.has(track)")
	assert_gt(reset_idx, -1, "play_music must end the danger envelope")
	assert_gt(manifest_idx, -1)
	assert_true(reset_idx < manifest_idx and reset_idx < cache_idx,
		"the pitch/volume reset must precede every play branch so all paths start clean")
	var rd: int = src.find("func reset_danger(")
	var rd_body: String = src.substr(rd, src.find("\nfunc ", rd + 1) - rd)
	assert_true(rd_body.contains("pitch_scale = 1.0") and rd_body.contains("_music_base_db"),
		"and reset_danger must actually restore the clean pitch and the user's volume")
