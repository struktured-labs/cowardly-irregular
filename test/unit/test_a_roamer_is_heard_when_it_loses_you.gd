extends GutTest

## A chaser's red "!!" dropped back to calm in silence when you got clear; it now sighs monster_lost_you on ANGRY->CALM only, once per pack.
## Driven for real: a level-30 party and goblins bold or timid by their own spawn hash, never a faked mood.

const RMS := preload("res://src/exploration/RoamingMonster.gd")
const SfxState := preload("res://test/unit/helpers/sfx_state.gd")
const KEY := "monster_lost_you"
const NEAR := Vector2(40, 0)
const FAR := Vector2(2000, 0)


class FakePlayer:
	extends Node2D
	func set_can_move(_v: bool) -> void:
		pass


var _player: FakePlayer = null
var _saved_party: Array[Dictionary] = []
var _saved_repel: int = 0


func before_each() -> void:
	RMS._reset_lost_gap()
	RMS._reset_spotted_gap()
	RMS._reset_afraid_gap()
	SoundManager._sfx_cooldowns.erase(KEY)
	SoundManager._ui_player.stream = null
	_saved_repel = EncounterSystem.repel_steps_remaining
	EncounterSystem.repel_steps_remaining = 0
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
	EncounterSystem.repel_steps_remaining = _saved_repel
	RMS._reset_lost_gap()
	RMS._reset_spotted_gap()
	RMS._reset_afraid_gap()
	SoundManager._sfx_cooldowns.erase(KEY)
	SoundManager._sfx_suppressed_by_cooldown = false
	SfxState.release_streams()
	SoundManager._ui_player.stream = null


func _file() -> String:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sfx_manifest.json"))
	var sfx: Dictionary = (parsed as Dictionary).get("sfx", {}) if parsed is Dictionary else {}
	return str((sfx.get(KEY, {}) as Dictionary).get("file", ""))


## A goblin whose own spawn hash makes it timid (want_timid) or bold, at the origin with the player 40px away.
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


## True when the UI voice holds the sigh; the voice and every manifest cooldown it could hide behind are cleared.
func _heard() -> bool:
	var s: AudioStream = SoundManager._ui_player.stream
	SoundManager._ui_player.stream = null
	for k in [KEY, "monster_spotted", "monster_afraid"]:
		SoundManager._sfx_cooldowns.erase(k)
	return s != null and s.resource_path.ends_with(_file())


## Ticks a roamer from calm to past its "!" beat, the player 40px away; returns how often the sigh played meanwhile.
func _rile(m: Node) -> int:
	var n := 0
	for _i in range(15):
		m._process(0.05)
		if _heard():
			n += 1
	return n


func test_the_cue_is_authored_and_loads_as_its_own_file() -> void:
	var f := _file()
	assert_ne(f, "", "monster_lost_you is not registered in sfx_manifest.json")
	assert_true(FileAccess.file_exists("res://" + f), "monster_lost_you names %s, which is not on disk" % f)
	var stream = load("res://" + f)
	assert_true(stream is AudioStream and (stream as AudioStream).get_length() > 0.2,
		"monster_lost_you does not load as a real stream (length %s)" % [
			(stream as AudioStream).get_length() if stream is AudioStream else -1.0])


func test_a_chaser_that_loses_you_sighs_once() -> void:
	var m := _goblin(false)
	assert_not_null(m, "CONTROL: no bold goblin in 200 spawn points")
	if m == null:
		return
	assert_eq(_rile(m), 0, "the sigh played while the goblin was still spotting and charging you")
	assert_eq(m._mood, RMS.Mood.ANGRY, "CONTROL: the bold goblin never reached '!!'")
	_player.global_position = m.global_position + FAR
	m._process(0.05)
	assert_eq(m._mood, RMS.Mood.CALM, "CONTROL: the goblin did not give up with the player 2000px away")
	assert_true(_heard(), "a chaser gave up on you and monster_lost_you was not heard")
	var later := 0
	for _i in range(10):
		m._process(0.05)
		if _heard():
			later += 1
	assert_eq(later, 0, "the sigh repeated %d times while the goblin simply stayed calm" % later)


func test_a_frightened_roamer_running_clear_stays_quiet() -> void:
	var m := _goblin(true)
	assert_not_null(m, "CONTROL: no timid goblin in 200 spawn points")
	if m == null:
		return
	_rile(m)
	assert_eq(m._mood, RMS.Mood.AFRAID, "CONTROL: the timid goblin never reached '~'")
	_player.global_position = m.global_position + FAR
	m._process(0.05)
	assert_eq(m._mood, RMS.Mood.CALM, "CONTROL: the frightened goblin did not settle with the player 2000px away")
	assert_false(_heard(), "a frightened roamer getting clear of you sighed as if it had lost a chase")


func test_a_repel_calming_a_chaser_stays_quiet() -> void:
	var m := _goblin(false)
	assert_not_null(m, "CONTROL: no bold goblin in 200 spawn points")
	if m == null:
		return
	_rile(m)
	assert_eq(m._mood, RMS.Mood.ANGRY, "CONTROL: the bold goblin never reached '!!'")
	EncounterSystem.repel_steps_remaining = 5
	m._process(0.05)
	assert_eq(m._mood, RMS.Mood.CALM, "CONTROL: an active Repel did not calm the chaser")
	assert_false(_heard(), "a Repel calming a chaser played the lost-you sigh; the Repel has its own voice")


func test_a_pack_that_loses_you_together_sighs_once() -> void:
	var pack: Array = [_goblin(false), _goblin(false), _goblin(false)]
	for g in pack:
		assert_not_null(g, "CONTROL: a bold packmate was not found")
		if g == null:
			return
	for _i in range(15):
		for g in pack:
			g._process(0.05)
			_heard()
	for g in pack:
		assert_eq(g._mood, RMS.Mood.ANGRY, "CONTROL: a packmate never reached '!!'")
	_player.global_position = FAR * 2.0
	var total := 0
	for g in pack:
		g._process(0.05)
		assert_eq(g._mood, RMS.Mood.CALM, "CONTROL: a packmate did not give up")
		if _heard():
			total += 1
	assert_eq(total, 1, "three chasers giving up together sighed %d times; a pack shares one" % total)
