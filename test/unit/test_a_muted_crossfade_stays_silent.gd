extends GutTest

## Mute the music and every track change still makes a sound.
##
## The crossfade moves the outgoing bed to the B player and tweens its `volume_db` to a hardcoded
## -40. That is "silent enough" only from above. The slider maps to -80 dB at mute, so the tween
## ran the wrong way: a 0.5 s ramp UP out of silence, at every battle start, victory and area
## change. Measured before the fix, muted, six consecutive frames on the B player:
##
##     -79.5 → -78.9 → -78.4 → -77.8 → -77.3 → -76.8   heading for -40
##
## 🔑 It is not only mute. `db = MUSIC_VOLUME_CEILING_DB + linear_to_db(slider)` is below -40
## whenever the slider is under ~3.2%, so every setting in that band fades the old bed LOUDER than
## the new one plays. A rising ramp out of silence is also the worst shape for it: quiet is what
## the player asked for, and a swell is what draws the ear.
##
## The fix is `minf(-40.0, <B's starting level>)` — from any normal level the fade is the same -40
## it always was, and a quiet player is left where they already are.

const BATTLE := "battle_medieval"
const NEXT := "victory"
## SoundManager.CROSSFADE_DURATION is 0.5 s of real time (the tween ignores time_scale).
const CROSSFADE_MS := 500.0


func before_each() -> void:
	SoundManager.stop_music()


func after_each() -> void:
	SoundManager.set_music_volume(1.0)
	SoundManager.stop_music()


func _frames(n: int = 3) -> void:
	for i in range(n):
		await get_tree().process_frame


## Start a bed, swap it, and report the B player's level across the crossfade.
func _crossfade_levels() -> Array:
	SoundManager.play_music(BATTLE)
	await _frames()
	var start: float = SoundManager._music_player.volume_db
	SoundManager.play_music(NEXT)
	var peak: float = -1000.0
	for i in range(8):
		await get_tree().process_frame
		peak = maxf(peak, SoundManager._music_player_b.volume_db)
	return [start, peak]


func test_a_muted_player_hears_nothing_when_the_track_changes() -> void:
	SoundManager.set_music_volume(0.0)
	assert_almost_eq(SoundManager._music_base_db, -80.0, 0.01, "CONTROL: mute puts the base at -80 dB")

	var levels: Array = await _crossfade_levels()
	assert_almost_eq(float(levels[0]), -80.0, 0.01, "CONTROL: the bed itself is muted before the swap")
	assert_lte(float(levels[1]), -80.0 + 0.01,
		"the outgoing bed rose to %.1f dB while the player had music muted — the crossfade must never fade UP" % levels[1])


func test_a_very_quiet_player_is_left_where_they_are() -> void:
	## Anything under ~3.2% maps below -40, which is the whole band the old constant inverted.
	SoundManager.set_music_volume(0.02)
	var base: float = SoundManager._music_base_db
	assert_lt(base, -40.0, "CONTROL: 2%% maps to %.1f dB, below the old -40 target" % base)

	var levels: Array = await _crossfade_levels()
	assert_lte(float(levels[1]), base + 0.01,
		"the outgoing bed rose from %.1f to %.1f dB — quieter than -40 must stay quieter" % [base, levels[1]])


func test_a_normal_player_still_gets_the_same_fade() -> void:
	## The fix must not deepen or shorten the fade anyone already hears. At full slider the target
	## is the -40 it has always been, and the tween is still what moves it.
	SoundManager.set_music_volume(1.0)
	var base: float = SoundManager._music_base_db
	assert_gt(base, -40.0, "CONTROL: a normal level (%.1f dB) sits above the fade target" % base)

	SoundManager.play_music(BATTLE)
	await _frames()
	SoundManager.play_music(NEXT)
	await get_tree().process_frame
	assert_lt(SoundManager._music_player_b.volume_db, base + 0.01,
		"the outgoing bed must be falling from its own level, not rising")

	## ⛔ FALLING IS NOT FADING. "below where it started" is also true of a fade that never moves,
	## so a target of B's own level passes that assert while the old bed plays at full volume for
	## the whole crossfade. Sample mid-fade and require real travel: half of -12 -> -40 is ~-26,
	## so 5 dB is a floor a working fade clears easily and a stalled one cannot.
	var midpoint: int = Time.get_ticks_msec() + int(CROSSFADE_MS * 0.5)
	while Time.get_ticks_msec() < midpoint and SoundManager._music_player_b.playing:
		await get_tree().process_frame
	assert_lte(SoundManager._music_player_b.volume_db, base - 5.0,
		"halfway through the crossfade the outgoing bed is still at %.1f dB against a base of %.1f — it is not fading" % [SoundManager._music_player_b.volume_db, base])

	## Wall-clock bounded, not frame-counted: the tween ignores time_scale (0.5 s real), and a
	## headless frame is far shorter than a rendered one, so 60 frames is not 0.5 s.
	var deadline: int = Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if not SoundManager._music_player_b.playing:
			break
	assert_false(SoundManager._music_player_b.playing,
		"the crossfade still ends by stopping the B player — the tween's callback must survive the fix")
