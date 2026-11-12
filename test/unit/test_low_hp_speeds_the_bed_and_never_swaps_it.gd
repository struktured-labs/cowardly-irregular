extends GutTest

## struktured, playing .792 (2026-11-11): "theres 'ur gonna die music' and the music goes faster music we need to
## pick one" -> "I'm ok with music going faster" -> "but the victory music should not change pace".
## ONE low-HP music signal: the fight's own bed speeds up with party danger. No bed is swapped in, and nothing
## that is not a fight's bed (victory, a stinger, game over) is ever sped up, whoever asks.
## The danger_* beds stay on disk and in the Jukebox, reserved for a party-wiper encounter.

const BattleSceneScript := preload("res://src/battle/BattleScene.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const SCENE := "res://src/battle/BattleScene.gd"
const BED := "battle_medieval"
const PITCH_CAP := 1.15
const DOWN := -1

var _scene = null
var _party: Array[Combatant] = []
var _saved_party: Array = []


func before_each() -> void:
	SoundManager.reset_corruption()
	SoundManager.stop_music()
	_saved_party = BattleManager.player_party.duplicate()
	BattleManager.player_party.clear()
	_scene = BattleSceneScript.new()
	_party = []
	for i in range(4):
		var m := Combatant.new()
		m.max_hp = 100
		m.current_hp = 100
		m.is_alive = true
		_party.append(m)
	_scene.party_members = _party
	_scene._music_follows_hp = true
	SoundManager.play_music(BED)
	SoundManager.declare_fight_bed()


func after_each() -> void:
	SoundManager.clear_fight_bed()
	SoundManager.reset_danger()
	SoundManager.reset_corruption()
	SoundManager.stop_music()
	BattleManager.player_party.assign(_saved_party)
	if is_instance_valid(_scene):
		_scene.free()
	for m in _party:
		if is_instance_valid(m):
			m.free()
	SoundState.restore()


func _pitch() -> float:
	return SoundManager._music_player.pitch_scale


func _set_party(hp: Array) -> void:
	for i in range(_party.size()):
		var v: int = int(hp[i])
		_party[i].is_alive = v != DOWN
		_party[i].current_hp = maxi(v, 0)


## One UI refresh's worth of feed, then the envelope's own tween run to its end (bounded; never a wall-clock wait).
func _refresh() -> void:
	_scene._update_danger_music()
	for i in range(240):
		await get_tree().process_frame
		var tw: Tween = SoundManager._danger_tween
		if tw == null or not tw.is_running():
			return
	fail_test("the danger envelope was still moving after 240 frames")


func _func_code(fname: String) -> String:
	var out := PackedStringArray()
	var inside := false
	for line in GdSource.code_of(SCENE).split("\n"):
		if line.begins_with("func %s(" % fname):
			inside = true
			continue
		if inside and (line.begins_with("func ") or line.begins_with("static func ")):
			break
		if inside:
			out.append(line)
	return "\n".join(out)


func test_floor_the_symbols_this_file_reaches_still_exist() -> void:
	for name in ["set_danger_intensity", "reset_danger", "play_music", "playing_track_stem", "takes_danger", "declare_fight_bed", "clear_fight_bed", "_apply_danger_intensity"]:
		assert_true(SoundManager.has_method(name), "SoundManager.%s is gone; every arm below would abort or pass on nothing" % name)
	assert_true("_music_follows_hp" in _scene, "BattleScene._music_follows_hp is gone: the feed has no battle-is-live latch")
	assert_true(_scene.has_method("_update_danger_music"), "BattleScene._update_danger_music is gone")


func test_from_full_hp_to_a_wipe_the_bed_stays_and_only_gets_faster() -> void:
	var walk: Array = [
		[100, 100, 100, 100], [60, 60, 60, 60], [40, 40, 40, 40], [20, 20, 20, 20],
		[20, 20, 20, DOWN], [10, 10, DOWN, DOWN], [5, DOWN, DOWN, DOWN], [DOWN, DOWN, DOWN, DOWN],
	]
	var last: float = 0.0
	var rises: int = 0
	for step in walk:
		_set_party(step)
		await _refresh()
		assert_eq(SoundManager.playing_track_stem(), BED,
			"party at %s: the bed changed to %s. Low HP speeds the fight's own bed up; it never swaps another in" % [str(step), SoundManager.playing_track_stem()])
		assert_eq(str(SoundManager._current_music), BED, "party at %s: the current track id moved" % str(step))
		var p: float = _pitch()
		if last == 0.0:
			assert_almost_eq(p, 1.0, 0.0001, "CONTROL: a full-HP party plays the bed at 1.0, not %.4f" % p)
		else:
			assert_gte(p, last - 0.0001, "party at %s: pitch FELL from %.4f to %.4f while danger rose" % [str(step), last, p])
			if p > last + 0.005:
				rises += 1
		assert_lte(p, PITCH_CAP + 0.0001,
			"party at %s: pitch %.4f is above the authored cap %.2f (his first report called it 2x)" % [str(step), p, PITCH_CAP])
		assert_lte(SoundManager._music_player.volume_db, SoundManager._music_base_db + 3.0001,
			"party at %s: the level is more than 3 dB over his slider" % str(step))
		last = p
	assert_gte(rises, 3, "the pitch rose at only %d of 7 steps: the speed-up is the low-HP signal and must track the party down" % rises)
	assert_almost_eq(last, PITCH_CAP, 0.001, "a wiped party must sit at the cap, not %.4f" % last)


func test_a_recovered_party_hears_the_bed_at_exactly_one_again() -> void:
	_set_party([10, 10, DOWN, DOWN])
	await _refresh()
	assert_gt(_pitch(), 1.05, "CONTROL: two down and two critical must have sped the bed up (%.4f)" % _pitch())
	_set_party([100, 100, 100, 100])
	await _refresh()
	assert_eq(_pitch(), 1.0, "a healed party still hears pitch %.5f" % _pitch())
	assert_eq(SoundManager._music_player.volume_db, SoundManager._music_base_db, "and the +3 dB must be gone with it")
	## The deadband's own corner: a meter left under 0.05 used to be 'no change' from safe, for the rest of the fight.
	SoundManager._apply_danger_intensity(0.04)
	assert_gt(_pitch(), 1.0, "CONTROL: 0.04 of danger is audible to the meter (%.5f)" % _pitch())
	await _refresh()
	assert_eq(_pitch(), 1.0, "a party that recovered from a sliver of danger stays at pitch %.5f for the rest of the fight" % _pitch())
	assert_eq(SoundManager._danger_intensity, 0.0, "the meter is parked at %.3f, not safe" % SoundManager._danger_intensity)


func test_a_win_with_two_down_plays_the_victory_bed_at_one_through_every_refresh() -> void:
	_set_party([100, 100, DOWN, DOWN])
	await _refresh()
	assert_gt(_pitch(), 1.02, "CONTROL: two KO'd must have sped the battle bed up (%.4f), or this arm proves nothing" % _pitch())  # two down at full HP is 1.05 exactly
	BattleSceneScript.play_victory_music(false)
	assert_eq(_pitch(), 1.0, "the victory bed's first frame is at pitch %.4f" % _pitch())
	## The latch is deliberately LEFT OPEN here: the mixer must refuse on its own, for a caller that forgets.
	for i in range(6):
		await _refresh()  # EXP rows, level-ups, loot: each is a UI refresh with two members still down
		assert_eq(_pitch(), 1.0, "UI refresh %d after the win pitched the victory bed to %.4f" % [i + 1, _pitch()])
	assert_eq(SoundManager._danger_intensity, 0.0, "the meter rose to %.3f under the victory bed" % SoundManager._danger_intensity)


func test_only_the_bed_the_battle_declared_takes_the_speed_up() -> void:
	assert_true(SoundManager.takes_danger(), "CONTROL: the declared battle bed takes the speed-up")
	for id in ["victory", "stinger_boss_defeated", "game_over"]:
		SoundManager.play_music(id)
		assert_false(SoundManager.takes_danger(), "%s is not the bed this fight declared" % id)
		SoundManager.set_danger_intensity(1.0)
		for i in range(40):
			await get_tree().process_frame
		assert_eq(_pitch(), 1.0, "%s was pitched to %.4f by a direct danger call" % [id, _pitch()])
	## Not a name test: a grind fights on "autogrind" and keeps its speed-up, as before (main 24199).
	SoundManager.play_music("autogrind")
	SoundManager.declare_fight_bed()
	_set_party([10, 10, DOWN, DOWN])
	await _refresh()
	assert_gt(_pitch(), 1.05, "a grind's own bed lost the low-HP speed-up (%.4f)" % _pitch())
	SoundManager.clear_fight_bed()
	SoundManager.reset_danger()
	await _refresh()
	assert_eq(_pitch(), 1.0, "with no fight declared, party HP still pitched the bed to %.4f" % _pitch())
	SoundManager.stop_music()
	SoundManager.declare_fight_bed()
	assert_false(SoundManager.takes_danger(), "silence must not count as a declared bed")


## SPELLING: every place BattleScene starts a bed for this fight declares it, or that bed silently never speeds up.
func test_every_bed_the_battle_starts_mid_fight_is_declared() -> void:
	for fname in ["_on_boss_face_changed", "_check_masterite_phase2_music_swap"]:
		var body := _func_code(fname)
		var plays: int = body.find("SoundManager.play_music(")
		assert_gt(plays, -1, "FLOOR: %s no longer starts a bed; this arm is stale" % fname)
		assert_gt(body.find("SoundManager.declare_fight_bed()", plays), -1, "%s starts a bed and never declares it as the fight's" % fname)
	var code := GdSource.code_of(SCENE)
	var opens: int = code.find("_music_follows_hp = true")
	assert_gt(opens, -1, "FLOOR: nothing opens the feed")
	assert_lt(code.find("SoundManager.declare_fight_bed()", opens) - opens, 80, "battle start opens the feed without declaring its bed")


func test_the_feed_closes_when_the_battle_ends() -> void:
	_set_party([10, 10, DOWN, DOWN])
	_scene._music_follows_hp = false  # what _on_battle_ended does first
	await _refresh()
	assert_eq(_pitch(), 1.0, "a closed feed still pitched the bed to %.4f" % _pitch())
	_scene._music_follows_hp = true
	await _refresh()
	assert_gt(_pitch(), 1.05, "CONTROL: the same party with the feed open must speed the bed up (%.4f)" % _pitch())
	## SPELLING, for the half no bare scene can run: the latch closes before the win/defeat bed starts and before the last refresh.
	var body := _func_code("_on_battle_ended")
	var closes: int = body.find("_music_follows_hp = false")
	assert_gt(closes, -1, "_on_battle_ended no longer closes the feed")
	assert_gt(body.find("SoundManager.clear_fight_bed()"), -1, "_on_battle_ended no longer withdraws the fight's bed")
	assert_gt(body.find("SoundManager.reset_danger()"), -1, "_on_battle_ended no longer ends the envelope itself: a turbo win or an escape starts no new bed and stays sped up")
	for later in ["play_victory_music(", "play_music(\"game_over\")", "_update_ui()"]:
		assert_gt(body.find(later), -1, "FLOOR: _on_battle_ended no longer contains `%s`; this arm is stale" % later)
		assert_lt(closes, body.find(later), "the feed must close BEFORE `%s`" % later)
	assert_true(GdSource.code_of(SCENE).contains("_music_follows_hp = true"), "nothing opens the feed at battle start: the speed-up is dead")


func test_no_bed_is_swapped_in_and_the_danger_beds_are_kept() -> void:
	var code := GdSource.code_of(SCENE)
	assert_true(code.contains("SoundManager.play_music("), "FLOOR: the stripped source has no play_music call at all")
	assert_false(code.contains("play_music(\"danger"), "BattleScene starts a danger bed again: two low-HP music signals, the thing he asked us to pick one of")
	var tracks: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/music_manifest.json")).get("tracks", {})
	var kept: int = 0
	for key in tracks:
		if str(key) == "danger" or str(key).begins_with("danger_"):
			kept += 1
			assert_true(FileAccess.file_exists(str(tracks[key].get("file", ""))), "%s lost its file: the danger beds are reserved, not retired" % key)
			assert_true(str(tracks[key].get("reserved_for", "")) != "", "%s must say what it is reserved for, or the next lane spends it" % key)
	assert_eq(kept, 7, "the manifest names %d danger beds, not the 7 that shipped" % kept)
