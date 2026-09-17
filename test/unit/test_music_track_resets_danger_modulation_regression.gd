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
	## \u26d4 NOT "_music_cache.has(track)" -- that substring occurs THREE times in play_music
	## (the refusal guard, this branch, and the write at the foot), so .find() returns whichever
	## comes first. It named this branch by luck until a guard was added above it, and then the
	## pin failed against correct code. Use the one spelling only the cache BRANCH has.
	var cache_idx: int = body.find("_music_player.stream = _music_cache[track]")
	assert_gt(reset_idx, -1, "play_music must end the danger envelope")
	assert_gt(manifest_idx, -1)
	assert_true(reset_idx < manifest_idx and reset_idx < cache_idx,
		"the pitch/volume reset must precede every play branch so all paths start clean")
	var rd: int = src.find("func reset_danger(")
	var rd_body: String = src.substr(rd, src.find("\nfunc ", rd + 1) - rd)
	assert_true(rd_body.contains("pitch_scale = 1.0") and rd_body.contains("_music_base_db"),
		"and reset_danger must actually restore the clean pitch and the user's volume")


## The refusal guard returns BEFORE reset_danger(), and that ordering is deliberate: a call that
## will play nothing leaves the current bed playing, so ending its danger envelope would flatten
## the pitch and volume of a track that is still going. Every OTHER path still resets first.
func test_a_refusal_does_not_end_the_envelope_of_the_bed_that_keeps_playing() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/audio/SoundManager.gd")
	var fn: int = src.find("func play_music")
	var body: String = src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	var guard_idx: int = body.find("music_is_available(track)")
	var reset_idx: int = body.find("reset_danger()")
	assert_gt(guard_idx, -1, "play_music must refuse an id it cannot play")
	assert_true(guard_idx < reset_idx,
		"the refusal must return before reset_danger(), or it flattens a bed that is still playing")
