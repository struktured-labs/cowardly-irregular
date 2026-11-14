extends GutTest

## .803 made a broken charge say Glacius's authored bark, but only as a bubble; sfx cut the line as boss_line_glacius_45.
## The manager now sends boss_cadence_bark just before the taunt, and the scene voices it under the same gate as every
## boss bark: never in turbo or the grind console, never over another voice.

const SCENE := "res://src/battle/BattleScene.tscn"
const BattleState := preload("res://test/unit/helpers/battle_state.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")

var _guard: RefCounted = null
var _saved_scale: float = 1.0
var _saved_wedged: bool = false


func before_each() -> void:
	_guard = BattleState.new()
	_guard.snapshot()
	_saved_scale = Engine.time_scale
	_saved_wedged = SoundManager._audio_mixer_wedged
	SoundManager._audio_mixer_wedged = false
	SoundManager.stop_voiced_line()
	SoundManager.stop_voice()


func after_each() -> void:
	SoundManager.stop_voiced_line()
	Engine.time_scale = _saved_scale
	SoundManager._audio_mixer_wedged = _saved_wedged
	if _guard != null:
		_guard.restore()


func after_all() -> void:
	SoundState.restore()


func _glacius() -> Combatant:
	var c: Combatant = Combatant.new()
	add_child_autofree(c)
	c.initialize({"name": "Glacius", "max_hp": 100, "max_mp": 100, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	c.set_meta("monster_type", "ice_dragon")
	c.set_meta("_cadence", {"phase": "charging", "count": 0, "charge_left": 1, "interrupted": false})
	return c


func _bark(boss: Combatant) -> String:
	return str(BossDialogue.get_charge_lines(BattleManager._boss_persona_id(boss)).get("interrupted_bark", ""))


func _quiet() -> void:
	SoundManager.stop_voice()
	SoundManager.stop_voiced_line()
	for b in BattleSpeechBubble._live:
		if is_instance_valid(b):
			b.free()
	BattleSpeechBubble._live.clear()


func test_the_bark_goes_out_before_its_bubble() -> void:
	var boss := _glacius()
	var order: Array = []
	var on_bark := func(_b, line): order.append("bark:" + str(line))
	var on_taunt := func(_b, line): order.append("taunt:" + str(line))
	BattleManager.boss_cadence_bark.connect(on_bark)
	BattleManager.boss_taunt.connect(on_taunt)
	BattleManager._on_cadence_status("stun", boss)
	BattleManager.boss_cadence_bark.disconnect(on_bark)
	BattleManager.boss_taunt.disconnect(on_taunt)
	var bark := _bark(boss)
	assert_ne(bark, "", "CONTROL: Glacius authors an interrupted bark")
	assert_eq(order, ["bark:" + bark, "taunt:" + bark], "voice first, so the bark is not blocked by its own bubble")


func test_a_broken_charge_is_heard_in_a_real_battle_scene() -> void:
	var boss := _glacius()
	assert_ne(SoundManager.voiced_line_clip("Glacius", _bark(boss)), "", "CONTROL: the bark has a recording")
	var scene = load(SCENE).instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	Engine.time_scale = 1.0
	_quiet()
	assert_false(SoundManager.is_voiced_line_playing(), "CONTROL: nothing is speaking before the break")
	BattleManager._on_cadence_status("stun", boss)
	assert_true(SoundManager.is_voiced_line_playing(), "the break bark speaks in Glacius's voice")


func test_turbo_breaks_the_charge_in_silence() -> void:
	var boss := _glacius()
	var scene = load(SCENE).instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	Engine.time_scale = 1.0
	_quiet()
	scene.turbo_mode = true
	BattleManager._on_cadence_status("stun", boss)
	assert_false(SoundManager.is_voiced_line_playing(), "turbo stays silent, like every boss bark")
	assert_false(BossCadence.is_charging(boss.get_meta("_cadence", {})), "CONTROL: the stun still broke the charge")
