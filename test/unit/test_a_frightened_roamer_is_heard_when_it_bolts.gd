extends GutTest

## A timid roamer's blue "~" turned tail in silence; it now squeaks monster_afraid on the ALERTED->AFRAID edge, once per pack.
## Driven for real: a level-30 party and a goblin that is timid by its own spawn hash, never a faked predicate.

const RMS := preload("res://src/exploration/RoamingMonster.gd")
const SfxState := preload("res://test/unit/helpers/sfx_state.gd")
const KEY := "monster_afraid"
const NEAR := Vector2(40, 0)


class FakePlayer:
	extends Node2D
	func set_can_move(_v: bool) -> void:
		pass


var _player: FakePlayer = null
var _saved_party: Array[Dictionary] = []


func before_each() -> void:
	RMS._reset_afraid_gap()
	RMS._reset_spotted_gap()
	SoundManager._sfx_cooldowns.erase(KEY)
	SoundManager._ui_player.stream = null
	_saved_party = GameState.player_party
	var party: Array[Dictionary] = []
	for i in range(4):
		party.append({"name": "p%d" % i, "job_level": 30})
	GameState.player_party = party
	_player = FakePlayer.new()
	add_child_autofree(_player)
	_player.global_position = NEAR


func after_each() -> void:
	GameState.player_party = _saved_party
	RMS._reset_afraid_gap()
	RMS._reset_spotted_gap()
	SoundManager._sfx_cooldowns.erase(KEY)
	SoundManager._sfx_suppressed_by_cooldown = false
	SfxState.release_streams()
	SoundManager._ui_player.stream = null


func _file() -> String:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sfx_manifest.json"))
	var sfx: Dictionary = (parsed as Dictionary).get("sfx", {}) if parsed is Dictionary else {}
	return str((sfx.get(KEY, {}) as Dictionary).get("file", ""))


## A goblin whose own spawn hash makes it timid (want_timid) or bold, placed at the origin with the player 40px away.
func _goblin(want_timid: bool) -> Node:
	var host := Node2D.new()
	add_child_autofree(host)
	for i in range(200):
		var m: Node = RMS.new()
		m.monster_id = "goblin"
		host.add_child(m)
		m._spawn_origin = Vector2((i * 37) % 3000, (i * 53) % 2000)
		if m._is_timid() == want_timid:
			m.global_position = Vector2.ZERO
			m.set_player_ref(_player)
			return m
		m.free()
	return null


## Every afraid-cue the UI voice held across n ticks, the voice cleared after each read.
func _squeaks_over(m: Node, ticks: int) -> int:
	var n := 0
	for _i in range(ticks):
		m._process(0.05)
		var s: AudioStream = SoundManager._ui_player.stream
		SoundManager._ui_player.stream = null
		SoundManager._sfx_cooldowns.erase(KEY)
		SoundManager._sfx_cooldowns.erase("monster_spotted")
		if s != null and s.resource_path.ends_with(_file()):
			n += 1
	return n


func test_the_cue_is_authored_and_loads_as_its_own_file() -> void:
	var f := _file()
	assert_ne(f, "", "monster_afraid is not registered in sfx_manifest.json")
	assert_true(FileAccess.file_exists("res://" + f), "monster_afraid names %s, which is not on disk" % f)
	var stream = load("res://" + f)
	assert_true(stream is AudioStream and (stream as AudioStream).get_length() > 0.2,
		"monster_afraid does not load as a real stream (length %s)" % [
			(stream as AudioStream).get_length() if stream is AudioStream else -1.0])


func test_a_timid_roamer_squeaks_once_as_it_bolts() -> void:
	var m := _goblin(true)
	assert_not_null(m, "CONTROL: no timid goblin in 200 spawn points")
	if m == null:
		return
	assert_true(m._is_outmatched(), "CONTROL: a timid goblin is not outmatched by a level-30 party")
	var n := _squeaks_over(m, 25)
	assert_eq(m._mood, RMS.Mood.AFRAID, "CONTROL: the timid goblin never reached '~' in 1.25 s")
	assert_eq(n, 1, "a timid goblin bolting played the squeak %d times; it must be exactly once" % n)


func test_a_bold_roamer_charges_without_a_squeak() -> void:
	var m := _goblin(false)
	assert_not_null(m, "CONTROL: no bold goblin in 200 spawn points")
	if m == null:
		return
	var n := _squeaks_over(m, 25)
	assert_eq(m._mood, RMS.Mood.ANGRY, "CONTROL: the bold goblin never reached '!!' in 1.25 s")
	assert_eq(n, 0, "a charging '!!' played the frightened squeak %d times" % n)


## Read after EACH goblin with the manifest's own 80 ms cooldown cleared, so only the roamers' shared gap can hold the count at one.
func test_a_pack_that_bolts_together_squeaks_once() -> void:
	var pack: Array = [_goblin(true), _goblin(true), _goblin(true)]
	for g in pack:
		assert_not_null(g, "CONTROL: a timid packmate was not found")
		if g == null:
			return
	var total := 0
	for _i in range(25):
		for g in pack:
			g._process(0.05)
			var s: AudioStream = SoundManager._ui_player.stream
			SoundManager._ui_player.stream = null
			SoundManager._sfx_cooldowns.erase(KEY)
			SoundManager._sfx_cooldowns.erase("monster_spotted")
			if s != null and s.resource_path.ends_with(_file()):
				total += 1
	for g in pack:
		assert_eq(g._mood, RMS.Mood.AFRAID, "CONTROL: a packmate never bolted")
	assert_eq(total, 1, "three goblins bolting together squeaked %d times; a pack shares one" % total)
