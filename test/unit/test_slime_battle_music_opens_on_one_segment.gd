extends GutTest

## A slime fight opened on two parts of battle_slime at once.
##
## tools/crossfade_loop.py (94000af3d) folds a bed's tail over its own head.
## The shipped file's first 4.0 s are that mix — measured against the pre-fold
## master, correlation 0.997 — and play() started at 0, so the opening phrase
## was the ending and the beginning together. The blend stays in the file
## because the LOOP seeks to 0 and needs it. Entry must start after it.
##
## BattleScene plays one track for a slime: monsters.json music_track
## "battle_slime". The field bed crossfades out on the other music player for
## CROSSFADE_DURATION; once that handoff ends, only the slime stream is up.

const BLEND := 4.0
const HANDOFF_S := 0.7


func before_each() -> void:
	SoundManager.stop_music()
	SoundManager.stop_ambient()
	SoundManager.set_music_volume(1.0)


func after_each() -> void:
	SoundManager.stop_music()
	SoundManager.stop_ambient()


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


func _music_players_playing() -> int:
	var n := 0
	for p in [SoundManager._music_player, SoundManager._music_player_b, SoundManager._ambient_player]:
		if p and p.playing:
			n += 1
	return n


func test_a_plain_slime_resolves_to_the_folded_bed() -> void:
	## BattleScene: a monsters.json music_track wins; otherwise the bed is "battle_" + id.
	## A plain slime has no override, so the fight asks for battle_slime and nothing else.
	var monsters: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var slime: Dictionary = monsters["slime"]
	assert_eq(str(slime.get("music_track", "")), "",
		"CONTROL: a plain slime names no music_track, so the battle scene derives the bed from its id")
	var derived: String = "battle_" + str(slime.get("id", ""))
	assert_eq(derived, "battle_slime",
		"a slime fight must ask for one bed, battle_slime — not a family theme stacked on the default")
	var tracks: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://data/music_manifest.json")) as Dictionary)["tracks"]
	assert_almost_eq(float((tracks["battle_slime"] as Dictionary).get("loop_blend_seconds", -1.0)), BLEND, 0.01,
		"battle_slime must name its fold length — playback reads this and the ogg itself is not rewritten")


func test_a_slime_battle_opens_past_the_fold_on_one_player() -> void:
	SoundManager.play_area_music("overworld")
	await _frames(12)
	assert_true(SoundManager._music_player.playing, "CONTROL: the field bed is playing before the encounter")

	SoundManager.play_music("battle_slime")
	await _frames(4)
	var pos: float = SoundManager._music_player.get_playback_position()
	assert_gte(pos, BLEND - 0.05,
		"slime battle opened at %.2f s, inside the %.1f s fold where the ending plays over the opening" % [pos, BLEND])
	assert_lt(pos, BLEND + 1.0,
		"slime battle opened at %.2f s — past the fold, but not a leaked field-bed position" % pos)
	var path: String = str(SoundManager._music_player.stream.resource_path) if SoundManager._music_player.stream else ""
	assert_true(path.ends_with("battle_slime.ogg"), "the live stream is %s, not the slime bed" % path)
	if SoundManager._music_player_b.playing and SoundManager._music_player_b.stream:
		var other: String = str(SoundManager._music_player_b.stream.resource_path)
		assert_false(other.ends_with("battle_slime.ogg"),
			"a second player is also on battle_slime (%s) — two segments of the same bed" % other)

	await get_tree().create_timer(HANDOFF_S).timeout
	await _frames(4)
	assert_eq(_music_players_playing(), 1,
		"after the handoff, %d music players are still sounding — a slime fight should be one stream" % _music_players_playing())
	assert_true(SoundManager._music_player.playing, "the slime bed stopped during the handoff")
	assert_false(SoundManager._music_player_b.playing, "the outgoing bed is still playing under the slime theme")
	assert_false(SoundManager._ambient_player.playing, "ambient is still playing under the slime theme")
	assert_gte(SoundManager._music_player.get_playback_position(), BLEND - 0.05,
		"the slime bed fell back into the fold")
	var stream: AudioStream = SoundManager._music_player.stream
	assert_true(stream is AudioStreamOggVorbis and (stream as AudioStreamOggVorbis).loop,
		"the bed must keep looping")
	assert_almost_eq((stream as AudioStreamOggVorbis).loop_offset, 0.0, 0.001,
		"loop_offset must stay 0 so the wrap still plays the blend — skipping it on the loop clicks")


func test_a_resume_past_the_fold_is_kept() -> void:
	SoundManager.play_music("battle_slime", false, 20.0)
	await _frames(4)
	var pos: float = SoundManager._music_player.get_playback_position()
	assert_gt(pos, 19.0, "a resume at 20 s landed at %.2f — the fold skip ate a real position" % pos)
	assert_lt(pos, 21.5, "a resume at 20 s landed at %.2f" % pos)


func test_a_bed_without_a_fold_still_starts_at_its_head() -> void:
	SoundManager.play_music("title")
	await _frames(4)
	assert_lt(SoundManager._music_player.get_playback_position(), 0.5,
		"title opened at %.2f s — the fold skip ran on a bed that does not declare one" % SoundManager._music_player.get_playback_position())
