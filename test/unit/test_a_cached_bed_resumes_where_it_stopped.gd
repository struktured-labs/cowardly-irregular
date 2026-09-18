extends GutTest

## "A restore without a position RESTARTS THE BED" has been fixed twice — once in the manifest
## branch, once in `restore_music_state`'s track branch, each with a measured player consequence.
## `play_music`'s CACHE branch kept the bare `play()`.
##
## ⛔ MEASURED: asked to resume at 40.0 s, the cache branch played from 0.003 s where the manifest
## branch gives 40.003.
##
## ⚠️ LATENT ON THE SHIPPED BUILD, AND I AM NOT DRESSING IT UP. Every manifest key has a file on
## disk, so nothing reaches the cache branch carrying a position. It is live under `WEB_STAGE=0`,
## the opt-out publish, where the W4-W6 audio exclusions make `_try_play_from_manifest` fail and a
## procedurally generated bed gets cached instead — and from then on every pause-menu or cutscene
## restore of that bed starts it from zero.
##
## 🔑 The repair is a single owner rather than a copied clamp: both branches start a stream, and the
## clamp's rule ("within 1 s of the end, restart — resuming there is a wrap the player hears as a
## stutter") is one rule that must not exist in two places.

const BED := "overworld_medieval"
const FAKE := "zzq_cached_only_bed"
const SEEK := 40.0


func before_each() -> void:
	SoundManager.stop_music()
	SoundManager._pending_resume_position = 0.0


func after_each() -> void:
	SoundManager.stop_music()
	SoundManager._music_cache.erase(FAKE)
	SoundManager._pending_resume_position = 0.0


func _stream() -> AudioStream:
	return load("res://assets/audio/music/%s.ogg" % BED)


func _pos() -> float:
	return SoundManager._music_player.get_playback_position()


func test_control_the_id_is_absent_from_the_manifest() -> void:
	## Without this the "cache branch" arms would be driving the MANIFEST branch and passing for the
	## wrong reason — the manifest is checked first, so a real key never reaches the cache.
	SoundManager._load_music_manifest()
	assert_false(SoundManager._music_manifest.has(FAKE),
		"%s must be absent from the manifest, or these arms measure the branch that already worked" % FAKE)
	assert_true(SoundManager._music_manifest.has(BED), "CONTROL: and the comparison key must be present")
	var s: AudioStream = _stream()
	assert_not_null(s, "CONTROL: the comparison stream must load")
	assert_gt(s.get_length(), SEEK + 5.0,
		"CONTROL: the stream (%.1f s) must be long enough that %.1f s is not inside the clamp window" % [s.get_length(), SEEK])


func test_control_the_manifest_branch_resumes() -> void:
	SoundManager.play_music(BED, false, SEEK)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_almost_eq(_pos(), SEEK, 0.5,
		"CONTROL: the manifest branch must resume at %.1f s (got %.3f) — the direction that already worked" % [SEEK, _pos()])


func test_a_cached_bed_resumes_too() -> void:
	SoundManager._music_cache[FAKE] = _stream()
	SoundManager.play_music(FAKE, false, SEEK)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_almost_eq(_pos(), SEEK, 0.5,
		"the cache branch started at %.3f s instead of %.1f — a restore of a procedural bed replays it from the top" % [_pos(), SEEK])


func test_the_clamp_reaches_the_cache_branch_as_well() -> void:
	## The other direction, so the fix cannot be "always seek". Seeking within 1 s of the end plays
	## nothing at all, which reads as a missing file — one rule, and it must hold on both branches.
	var s: AudioStream = _stream()
	SoundManager._music_cache[FAKE] = s
	SoundManager.play_music(FAKE, false, s.get_length() - 0.2)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(SoundManager._music_player.playing,
		"a resume position inside the clamp window must restart the bed, not seek past the end into silence")
	assert_lt(_pos(), 1.0,
		"and restart means from the top, not %.3f s" % _pos())


func test_the_position_is_consumed_once_on_the_cache_branch() -> void:
	## A parked position outliving its own start is the leak the owner's comment warns about; the
	## cache branch is a second consumer and must clear it too.
	SoundManager._music_cache[FAKE] = _stream()
	SoundManager.play_music(FAKE, false, SEEK)
	await get_tree().process_frame
	assert_almost_eq(SoundManager._pending_resume_position, 0.0, 0.001,
		"the cache branch left %.3f parked for whatever plays next" % SoundManager._pending_resume_position)
	SoundManager.stop_music()
	SoundManager.play_music(FAKE)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_lt(_pos(), 1.0,
		"the second play inherited the first call's position and started at %.3f s" % _pos())
