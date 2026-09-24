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


## Beds tools/crossfade_loop.py rewrote at the default 4.0s fold (0eabe0c90 and 94000af3d).
## Each was checked against its pre-rebuild master: the first 4s match that equal-power mix
## and the rest of the file is the body with the blend region removed. Beds the tool refused
## (overworld_industrial, ambient_steampunk, boss_warden_abstract) are not in this list.
const FOLDED: Array[String] = [
	"ambient_digital", "battle_cranky_lady", "battle_digital", "battle_imp",
	"battle_medieval", "battle_rogue_mailbox", "battle_slime", "battle_suburban",
	"boss_abstract", "boss_arbiter_digital", "boss_arbiter_industrial",
	"boss_curator_abstract", "boss_curator_digital", "boss_curator_suburban",
	"boss_industrial", "boss_medieval", "boss_phase2_arbiter", "boss_rat_king",
	"boss_suburban", "boss_tempo_industrial", "boss_tempo_steampunk", "boss_tempo_suburban",
	"boss_warden_digital", "boss_warden_industrial", "boss_warden_steampunk",
	"credits_digital", "credits_steampunk", "credits_suburban",
	"cutscene_alt_breaker_speed", "cutscene_w1_conscription", "cutscene_w1_warden_farewell",
	"cutscene_w2_portal_arrival", "cutscene_w3_pattern_recognized", "cutscene_w5_boot_sequence",
	"cutscene_w6_answer_exploit", "cutscene_w6_epilogue",
	"dungeon_medieval", "overworld_medieval", "victory_digital",
	"village_abstract", "village_digital", "village_maple_heights", "village_steampunk",
]


func test_every_rebuilt_bed_names_the_same_fold() -> void:
	var tracks: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://data/music_manifest.json")) as Dictionary)["tracks"]
	var declared: Array[String] = []
	for key in tracks:
		var entry: Dictionary = tracks[key]
		if not entry.has("loop_blend_seconds"):
			continue
		declared.append(str(key))
		assert_true(FOLDED.has(str(key)),
			"%s declares a fold but was not part of the crossfade rebuild" % key)
		assert_true(bool(entry.get("loop", false)),
			"%s declares a fold but does not loop — the wrap would never play the blend" % key)
		assert_almost_eq(float(entry["loop_blend_seconds"]), BLEND, 0.01,
			"%s fold length is not the 4.0s the rebuild wrote" % key)
	assert_eq(declared.size(), FOLDED.size(),
		"the manifest names %d folds and the rebuild list has %d" % [declared.size(), FOLDED.size()])
	for key in FOLDED:
		assert_true((tracks[key] as Dictionary).has("loop_blend_seconds"),
			"%s was rebuilt with a 4.0s fold and does not name it" % key)
	for plain in ["title", "battle_bat", "boss_mordaine", "stinger_level_up", "victory_medieval", "menu"]:
		assert_false((tracks[plain] as Dictionary).has("loop_blend_seconds"),
			"%s was not rebuilt and must still start at its head" % plain)


func test_each_rebuilt_bed_opens_past_its_fold() -> void:
	## Fixed frames, not a wait on playback. A stuck mixer fails the assert; it cannot hang here.
	for key in FOLDED:
		SoundManager.stop_music()
		SoundManager.play_music(key)
		await _frames(4)
		var pos: float = SoundManager._music_player.get_playback_position()
		assert_gte(pos, BLEND - 0.05,
			"%s opened at %.2f s, inside the %.1f s fold" % [key, pos, BLEND])
		assert_lt(pos, BLEND + 1.0,
			"%s opened at %.2f s — past the fold, or a leaked position" % [key, pos])
		var stream: AudioStream = SoundManager._music_player.stream
		assert_true(stream is AudioStreamOggVorbis and (stream as AudioStreamOggVorbis).loop,
			"%s must keep looping so the wrap can use the blend" % key)
		assert_almost_eq((stream as AudioStreamOggVorbis).loop_offset, 0.0, 0.001,
			"%s loop_offset must stay 0 — the wrap seeks there and needs the blend" % key)


func test_a_resume_inside_the_fold_starts_after_it() -> void:
	SoundManager.play_music("battle_medieval", false, 1.5)
	await _frames(4)
	var pos: float = SoundManager._music_player.get_playback_position()
	assert_gte(pos, BLEND - 0.05,
		"a resume at 1.5 s landed at %.2f, still inside the fold" % pos)
	assert_lt(pos, BLEND + 1.0,
		"a resume at 1.5 s landed at %.2f" % pos)


func test_a_paused_battle_past_the_fold_comes_back_there() -> void:
	SoundManager.play_music("battle_slime", false, 20.0)
	await _frames(4)
	var state: Dictionary = SoundManager.capture_music_state()
	assert_gt(float(state.get("position", 0.0)), 19.0, "CONTROL: the pause snapshot is past the fold")
	SoundManager.play_music("menu")
	await _frames(4)
	SoundManager.restore_music_state(state)
	await _frames(4)
	var pos: float = SoundManager._music_player.get_playback_position()
	assert_gt(pos, 19.0, "unpausing the fight restarted the slime bed at %.2f" % pos)
	assert_lt(pos, 22.0, "unpausing the fight landed at %.2f" % pos)


func test_a_saved_field_bed_past_the_fold_is_kept() -> void:
	SoundManager.play_area_music("overworld", 50.0)
	await _frames(12)
	var pos: float = SoundManager._music_player.get_playback_position()
	assert_gt(pos, 49.0, "the field bed resumed at %.2f — the fold skip ate a saved position" % pos)
	assert_lt(pos, 52.0, "the field bed resumed at %.2f" % pos)


func test_a_fresh_field_bed_opens_past_the_fold() -> void:
	SoundManager.play_area_music("overworld")
	await _frames(12)
	var pos: float = SoundManager._music_player.get_playback_position()
	assert_gte(pos, BLEND - 0.05, "the overworld opened at %.2f s, inside its fold" % pos)
	assert_lt(pos, BLEND + 1.0, "the overworld opened at %.2f s" % pos)


func test_a_battle_change_does_not_inherit_the_other_beds_position() -> void:
	SoundManager.play_music("battle_slime", false, 20.0)
	await _frames(4)
	assert_gt(SoundManager._music_player.get_playback_position(), 19.0, "CONTROL: slime is past the fold")
	SoundManager.play_music("battle_slime")
	await _frames(4)
	assert_gt(SoundManager._music_player.get_playback_position(), 19.0,
		"asking for the slime bed again restarted it — a second slime fight on the same theme must not skip")

	SoundManager.play_music("battle_medieval")
	await _frames(4)
	var medieval: float = SoundManager._music_player.get_playback_position()
	assert_gte(medieval, BLEND - 0.05,
		"battle_medieval opened at %.2f s, inside its fold" % medieval)
	assert_lt(medieval, BLEND + 1.0,
		"battle_medieval opened at %.2f s — it inherited the slime bed's position" % medieval)
	var path: String = str(SoundManager._music_player.stream.resource_path) if SoundManager._music_player.stream else ""
	assert_true(path.ends_with("battle_medieval.ogg"), "the live stream is %s" % path)

	## play_music returns immediately when that bed is already playing, so a seek has to be a fresh start.
	SoundManager.stop_music()
	SoundManager.play_music("battle_medieval", false, 40.0)
	await _frames(4)
	assert_gt(SoundManager._music_player.get_playback_position(), 39.0, "CONTROL: medieval is at 40s")
	SoundManager.play_music("boss_medieval")
	await _frames(4)
	var boss: float = SoundManager._music_player.get_playback_position()
	assert_gte(boss, BLEND - 0.05, "boss_medieval opened at %.2f s, inside its fold" % boss)
	assert_lt(boss, BLEND + 1.0,
		"boss_medieval opened at %.2f s — a boss transition skipped to the previous bed's position" % boss)

	SoundManager.play_music("boss_mordaine")
	await _frames(4)
	assert_lt(SoundManager._music_player.get_playback_position(), 0.5,
		"boss_mordaine opened at %.2f s — a bed with no fold was skipped" % SoundManager._music_player.get_playback_position())

	SoundManager.play_music("battle_bat")
	await _frames(4)
	assert_lt(SoundManager._music_player.get_playback_position(), 0.5,
		"battle_bat opened at %.2f s — a battle bed with no fold was skipped" % SoundManager._music_player.get_playback_position())


func test_a_non_looping_track_still_starts_at_its_head() -> void:
	SoundManager.play_music("stinger_level_up")
	await _frames(4)
	assert_lt(SoundManager._music_player.get_playback_position(), 0.5,
		"the level-up stinger opened at %.2f s — a non-looping track was skipped" % SoundManager._music_player.get_playback_position())
	var stream: AudioStream = SoundManager._music_player.stream
	assert_true(stream is AudioStreamOggVorbis and not (stream as AudioStreamOggVorbis).loop,
		"CONTROL: the stinger must not be looping")


func test_an_overworld_crossfade_into_the_generic_battle_is_one_stream() -> void:
	SoundManager.play_area_music("overworld")
	await _frames(12)
	assert_true(SoundManager._music_player.playing, "CONTROL: the field bed is playing")
	SoundManager.play_music("battle_medieval")
	await _frames(4)
	var pos: float = SoundManager._music_player.get_playback_position()
	assert_gte(pos, BLEND - 0.05, "the generic battle opened at %.2f s, inside its fold" % pos)
	assert_lt(pos, BLEND + 1.0, "the generic battle opened at %.2f s" % pos)
	if SoundManager._music_player_b.playing and SoundManager._music_player_b.stream:
		var other: String = str(SoundManager._music_player_b.stream.resource_path)
		assert_false(other.ends_with("battle_medieval.ogg"),
			"a second player is also on the generic battle (%s)" % other)
	await get_tree().create_timer(HANDOFF_S).timeout
	await _frames(4)
	assert_eq(_music_players_playing(), 1,
		"after the handoff, %d music players are still sounding" % _music_players_playing())
	assert_true(SoundManager._music_player.playing, "the battle bed stopped during the handoff")
	assert_false(SoundManager._music_player_b.playing, "the overworld is still playing under the battle")
