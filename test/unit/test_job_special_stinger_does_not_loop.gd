extends GutTest

## A Limit Break must not replace the battle theme with a 5-second loop.
##
## _on_group_attack_executing (BattleScene:3689) plays the party leader's
## job stinger through SoundManager.play_music("job_<id>_special"). Those
## files are 1.9-5.3s fragments (necromancer 57.6s is the outlier).
##
## _try_play_from_manifest already has the fix for exactly this — written
## 2026-05-02 after "level up music repeats itself" — but it classifies by
## NAME:
##
##     var is_stinger = track_id.begins_with("stinger_")
##
## The five stinger_* keys match. The fourteen job_*_special keys do not,
## so they take the manifest's loop=true AND miss the resume hookup, which
## is gated on the same flag. Using a Limit Break therefore drops the battle
## theme and loops a ~5s fragment for the rest of the fight.
##
## Same shape as the ability-animation bug found the same morning: the
## consumer classifies by a NAME the thing it should catch does not carry.
## The guard is data-driven now (a manifest `stinger` flag, defaulting to
## the old prefix) so a future stinger declares itself instead of needing
## to be named correctly.

const MANIFEST_PATH := "res://data/music_manifest.json"


func after_each() -> void:
	SoundManager.stop_music()


func _stream_for(track_id: String) -> AudioStream:
	SoundManager.play_music(track_id)
	var player: AudioStreamPlayer = SoundManager._music_player
	assert_not_null(player, "SoundManager has no _music_player — this probe is measuring nothing")
	return player.stream


func test_control_a_named_stinger_does_not_loop() -> void:
	## The 2026-05-02 fix, still working. If this goes red the probe is broken,
	## not the subject — read it before trusting the arm below.
	var stream: AudioStream = _stream_for("stinger_level_up")
	assert_not_null(stream, "SCOPE control: stinger_level_up did not load at all")
	if stream is AudioStreamOggVorbis:
		assert_false((stream as AudioStreamOggVorbis).loop,
			"CONTROL FAILED: even the correctly-named stinger_level_up is looping — the probe or the fix is broken")


func test_every_job_special_is_treated_as_a_stinger() -> void:
	var raw: String = FileAccess.get_file_as_string(MANIFEST_PATH)
	assert_gt(raw.length(), 1000, "SCOPE control: manifest read back %d chars" % raw.length())
	var tracks: Dictionary = (JSON.parse_string(raw) as Dictionary).get("tracks", {})

	var keys: Array[String] = []
	for k in tracks.keys():
		var s: String = str(k)
		if s.begins_with("job_") and s.ends_with("_special"):
			keys.append(s)
	keys.sort()
	assert_gt(keys.size(), 10,
		"SCOPE control: found only %d job_*_special tracks — the walk is broken and a green here would be vacuous" % keys.size())

	var looping: Array[String] = []
	for k in keys:
		var stream: AudioStream = _stream_for(k)
		if stream == null:
			continue
		if stream is AudioStreamOggVorbis and (stream as AudioStreamOggVorbis).loop:
			looping.append("%s (%.1fs)" % [k, stream.get_length()])

	assert_eq(looping.size(), 0,
		"job specials that LOOP (%d of %d): %s — a Limit Break replaces the battle theme with this fragment and it repeats for the rest of the fight, because the stinger guard matches on the name 'stinger_' and these are not named that." % [looping.size(), keys.size(), looping])


func test_a_job_special_restores_the_music_it_interrupted() -> void:
	## Not looping is only half the fix: the resume hookup is gated on the same
	## flag, so an unrecognised stinger also never puts the battle bed back.
	SoundManager.play_music("battle_medieval")
	var before: Dictionary = SoundManager.capture_music_state()
	assert_ne(str(before.get("track", "")), "",
		"SCOPE control: capture_music_state returned no track after play_music — the probe is measuring nothing")

	## Counting connections ABSOLUTELY is hollow — SoundManager may hold its own
	## listener on `finished`, so a bare >0 passes whether or not the resume was
	## wired. Predicted 2 failures here and got 1; that gap is what exposed it.
	## Measure the DIFFERENCE a stinger makes instead.
	var player: AudioStreamPlayer = SoundManager._music_player
	var baseline: int = player.finished.get_connections().size()

	SoundManager.play_music("job_bard_special")
	var with_stinger: int = player.finished.get_connections().size()

	## A named stinger is the positive control: it MUST add the hookup, so if
	## this does not move, the probe is wrong rather than the subject.
	SoundManager.stop_music()
	SoundManager.play_music("battle_medieval")
	var base2: int = player.finished.get_connections().size()
	SoundManager.play_music("stinger_level_up")
	var control_delta: int = player.finished.get_connections().size() - base2
	assert_eq(control_delta, 1,
		"CONTROL FAILED: a correctly-named stinger did not add exactly one `finished` listener (delta %d) — this probe cannot detect the resume hookup at all, so the arm below proves nothing" % control_delta)

	assert_eq(with_stinger - baseline, 1,
		"job_bard_special added %d `finished` listeners, not 1 — when the stinger ends the battle theme never comes back, because the resume hookup is gated on the same name check that missed it" % (with_stinger - baseline))


func test_stop_music_cancels_a_pending_stinger_resume() -> void:
	## Found by probing my own test's teardown, then true in the GAME: win a
	## battle while the Limit Break stinger is still playing and stop_music()
	## left the resume armed, so when the VICTORY track finished the battle bed
	## started over the victory screen.
	SoundManager.play_music("battle_medieval")
	SoundManager.play_music("stinger_level_up")
	var armed: int = SoundManager._music_player.finished.get_connections().size()
	assert_gt(armed, 0,
		"SCOPE control: no resume was armed, so this test cannot show stop_music cancelling one")

	SoundManager.stop_music()
	assert_eq(SoundManager._music_player.finished.get_connections().size(), 0,
		"stop_music left %d pending finished listener(s) — the next track to end restarts music the player never asked for" % SoundManager._music_player.finished.get_connections().size())
	assert_true(SoundManager._stinger_resume_state.is_empty(),
		"stop_music left _stinger_resume_state holding %s" % SoundManager._stinger_resume_state)

