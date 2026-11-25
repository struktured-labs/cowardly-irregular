extends GutTest

## An ordinary roamer's yellow "!" rose in silence; it now sounds monster_spotted on the CALM->ALERTED edge, once per pack.

const RM := "res://src/exploration/RoamingMonster.gd"
const RMS := preload("res://src/exploration/RoamingMonster.gd")
const SfxState := preload("res://test/unit/helpers/sfx_state.gd")
const KEY := "monster_spotted"
const NEAR := Vector2(40, 0)
const FAR := Vector2(2000, 0)


class FakePlayer:
	extends Node2D
	func set_can_move(_v: bool) -> void:
		pass


var _player: FakePlayer = null


func before_each() -> void:
	RMS._last_spotted_ms = -100000
	SoundManager._sfx_cooldowns.erase(KEY)
	SoundManager._ui_player.stream = null
	_player = FakePlayer.new()
	add_child_autofree(_player)
	_player.global_position = FAR


func after_each() -> void:
	RMS._last_spotted_ms = -100000
	SoundManager._sfx_cooldowns.erase(KEY)
	SoundManager._sfx_suppressed_by_cooldown = false
	SfxState.release_streams()
	SoundManager._ui_player.stream = null


func _file() -> String:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sfx_manifest.json"))
	var sfx: Dictionary = (parsed as Dictionary).get("sfx", {}) if parsed is Dictionary else {}
	return str((sfx.get(KEY, {}) as Dictionary).get("file", ""))


func _roamer() -> Node:
	var host := Node2D.new()
	add_child_autofree(host)
	var m: Node = load(RM).new()
	host.add_child(m)
	m.global_position = Vector2.ZERO
	m.set_player_ref(_player)
	return m


## The path the UI voice holds now, then cleared (with the manifest's own cooldown) so the next read is fresh.
func _heard() -> String:
	var s: AudioStream = SoundManager._ui_player.stream
	SoundManager._ui_player.stream = null
	SoundManager._sfx_cooldowns.erase(KEY)
	return s.resource_path if s != null else ""


func test_the_cue_is_authored_and_loads_as_its_own_file() -> void:
	var f := _file()
	assert_ne(f, "", "monster_spotted is not registered in sfx_manifest.json")
	assert_true(FileAccess.file_exists("res://" + f), "monster_spotted names %s, which is not on disk" % f)
	var stream = load("res://" + f)
	assert_true(stream is AudioStream and (stream as AudioStream).get_length() > 0.2,
		"monster_spotted does not load as a real stream (length %s)" % [
			(stream as AudioStream).get_length() if stream is AudioStream else -1.0])


func test_the_exclamation_appearing_is_heard() -> void:
	var m := _roamer()
	m._process(0.016)
	assert_eq(m._mood, RMS.Mood.CALM, "CONTROL: the roamer is not calm with the player 2000px away")
	assert_eq(_heard(), "", "CONTROL: the cue played before the roamer spotted anyone")
	_player.global_position = NEAR
	m._process(0.016)
	assert_eq(m._mood, RMS.Mood.ALERTED, "CONTROL: the roamer did not alert with the player 40px away")
	assert_eq(m._tell.text, "!", "CONTROL: the alerted tell is not the yellow '!'")
	assert_string_ends_with(_heard(), _file(), "the '!' rose and monster_spotted was not heard")


func test_the_beat_and_the_charge_after_it_stay_quiet() -> void:
	var m := _roamer()
	_player.global_position = NEAR
	m._process(0.016)
	assert_string_ends_with(_heard(), _file(), "CONTROL: the first spotting was not heard")
	RMS._last_spotted_ms = -100000
	var repeats := 0
	var went_calm := false
	for _i in range(40):
		m._process(0.05)
		went_calm = went_calm or m._mood == RMS.Mood.CALM
		if _heard() != "":
			repeats += 1
	assert_ne(m._mood, RMS.Mood.ALERTED, "CONTROL: the roamer never left the '!' beat in 2 s")
	assert_false(went_calm, "CONTROL: the roamer lost interest, so a re-spotting would be a fair cue, not a repeat")
	assert_eq(repeats, 0, "the cue played %d more times after the '!' (the beat or its '!!'/'~' replayed it)" % repeats)


func test_a_pack_that_spots_you_together_makes_one_sound() -> void:
	var pack: Array = [_roamer(), _roamer(), _roamer()]
	_player.global_position = NEAR
	pack[0]._process(0.016)
	assert_string_ends_with(_heard(), _file(), "CONTROL: the first of the pack was not heard")
	var extra := 0
	for r in pack.slice(1):
		r._process(0.016)
		assert_eq(r._mood, RMS.Mood.ALERTED, "CONTROL: a packmate did not alert")
		if _heard() != "":
			extra += 1
	assert_eq(extra, 0, "a pack spotting you at once played the cue %d extra times" % extra)
	RMS._last_spotted_ms -= RMS.SPOTTED_SHARED_GAP_MS
	var late := _roamer()
	late._process(0.016)
	assert_string_ends_with(_heard(), _file(), "a roamer spotting you after the shared gap was not heard")
