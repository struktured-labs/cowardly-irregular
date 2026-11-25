extends GutTest

## A field elite's "It is watching you." rose in silence; it now sounds elite_notice once as the tell appears.

const RM := "res://src/exploration/RoamingMonster.gd"
const SfxState := preload("res://test/unit/helpers/sfx_state.gd")
const KEY := "elite_notice"


class FakePlayer:
	extends Node2D
	func set_can_move(_v: bool) -> void:
		pass


var _player: FakePlayer = null


func before_each() -> void:
	SoundManager._sfx_cooldowns.erase(KEY)
	SoundManager._alert_player.stream = null


func after_each() -> void:
	SoundManager._sfx_cooldowns.erase(KEY)
	SoundManager._sfx_suppressed_by_cooldown = false
	SfxState.release_streams()
	SoundManager._alert_player.stream = null


func _file() -> String:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sfx_manifest.json"))
	var sfx: Dictionary = (parsed as Dictionary).get("sfx", {}) if parsed is Dictionary else {}
	return str((sfx.get(KEY, {}) as Dictionary).get("file", ""))


func _elite() -> Node:
	var host := Node2D.new()
	add_child_autofree(host)
	var m: Node = load(RM).new()
	m.elite = true
	host.add_child(m)
	m.global_position = Vector2.ZERO
	_player = FakePlayer.new()
	add_child_autofree(_player)
	_player.global_position = Vector2(2000, 0)
	m.set_player_ref(_player)
	return m


## The path of whatever the alert channel holds now, then cleared so the next read is fresh.
func _heard() -> String:
	var s: AudioStream = SoundManager._alert_player.stream
	SoundManager._alert_player.stream = null
	SoundManager._sfx_cooldowns.erase(KEY)
	return s.resource_path if s != null else ""


func test_the_cue_is_authored_and_loads_as_its_own_file() -> void:
	var f := _file()
	assert_ne(f, "", "elite_notice is not registered in sfx_manifest.json")
	assert_true(FileAccess.file_exists("res://" + f), "elite_notice names %s, which is not on disk" % f)
	var stream = load("res://" + f)
	assert_true(stream is AudioStream and (stream as AudioStream).get_length() > 0.5,
		"elite_notice does not load as a real stream (length %s), so play_ui would fall through to nothing" % [
			(stream as AudioStream).get_length() if stream is AudioStream else -1.0])


func test_the_tell_appearing_is_heard() -> void:
	var m := _elite()
	m._process(0.1)
	assert_false(m._tell.visible, "CONTROL: the tell is up with the player 2000px away")
	assert_eq(_heard(), "", "CONTROL: the cue played before the elite noticed anyone")
	_player.global_position = Vector2(40, 0)
	m._process(0.1)
	assert_true(m._tell.visible, "CONTROL: the tell did not rise with the player 40px away")
	assert_string_ends_with(_heard(), _file(), "the tell rose and elite_notice was not heard")


func test_it_sounds_once_while_the_tell_stays_up() -> void:
	var m := _elite()
	_player.global_position = Vector2(40, 0)
	m._process(0.1)
	assert_string_ends_with(_heard(), _file(), "CONTROL: the first notice was not heard")
	var repeats := 0
	for _i in range(20):
		m._process(0.1)
		if _heard() != "":
			repeats += 1
	assert_eq(repeats, 0, "the cue repeated %d times while the tell simply stayed up" % repeats)


func test_stepping_in_and_out_of_range_does_not_chatter() -> void:
	var m := _elite()
	_player.global_position = Vector2(40, 0)
	m._process(0.1)
	assert_string_ends_with(_heard(), _file(), "CONTROL: the first notice was not heard")
	_player.global_position = Vector2(2000, 0)
	m._process(0.1)
	assert_false(m._tell.visible, "CONTROL: the tell did not drop when the player left")
	_player.global_position = Vector2(40, 0)
	m._process(0.1)
	assert_eq(_heard(), "", "re-entering the radius at once replayed the cue, so the edge of the radius chatters")
	m._last_notice_ms -= m.NOTICE_COOLDOWN_MS
	_player.global_position = Vector2(2000, 0)
	m._process(0.1)
	_player.global_position = Vector2(40, 0)
	m._process(0.1)
	assert_string_ends_with(_heard(), _file(), "after the cooldown a fresh notice was not heard")
