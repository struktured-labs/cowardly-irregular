extends GutTest

## A broken charge does two things to the bed at once: the charge dip (slot 3) lets go, and Glacius's voiced bark takes the
## dialogue duck (slot 0). They are separate Amplifies, so the bed must land at the dialogue depth, not stay at the
## sum nor spring to 0 under the voice (cowir-music, main 25312).

const SCENE := "res://src/battle/BattleScene.tscn"
const BattleState := preload("res://test/unit/helpers/battle_state.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const BOUND_MS := 1500

var _guard: RefCounted = null
var _saved_scale: float = 1.0
var _saved_wedged: bool = false


func before_each() -> void:
	_guard = BattleState.new()
	_guard.snapshot()
	_saved_scale = Engine.time_scale
	_saved_wedged = SoundManager._audio_mixer_wedged
	SoundManager._audio_mixer_wedged = false
	_quiet()
	SoundManager.clear_charge_duck()
	SoundManager.duck_music_for_dialogue(false)


func after_each() -> void:
	_quiet()
	SoundManager.clear_charge_duck()
	SoundManager.duck_music_for_dialogue(false)
	Engine.time_scale = _saved_scale
	SoundManager._audio_mixer_wedged = _saved_wedged
	var idx: int = AudioServer.get_bus_index(SoundManager.MUSIC_DUCK_BUS)
	if idx != -1:
		for slot in range(AudioServer.get_bus_effect_count(idx)):
			var e = AudioServer.get_bus_effect(idx, slot)
			if e:
				e.volume_db = 0.0
	if _guard != null:
		_guard.restore()


func after_all() -> void:
	SoundState.restore()


func _quiet() -> void:
	SoundManager.stop_voice()
	SoundManager.stop_voiced_line()
	for b in BattleSpeechBubble._live:
		if is_instance_valid(b):
			b.free()
	BattleSpeechBubble._live.clear()


func _glacius() -> Combatant:
	var c: Combatant = Combatant.new()
	add_child_autofree(c)
	c.initialize({"name": "Glacius", "max_hp": 100, "max_mp": 100, "attack": 10, "defense": 10, "magic": 10, "speed": 10})
	c.set_meta("monster_type", "ice_dragon")
	c.set_meta("_cadence", {"phase": "charging", "count": 0, "charge_left": 1, "interrupted": false})
	return c


func _dialogue_db() -> float:
	var idx: int = AudioServer.get_bus_index(SoundManager.MUSIC_DUCK_BUS)
	if idx == -1 or AudioServer.get_bus_effect_count(idx) == 0:
		return 0.0
	var amp = AudioServer.get_bus_effect(idx, 0)
	return amp.volume_db if amp else 0.0


## Wall-clock bound on the CONDITION: the charge envelope ignores time scale and the dialogue taper does not.
func _settle(charge_db: float, dialogue_db: float) -> void:
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < BOUND_MS:
		if absf(SoundManager.get_charge_duck_db() - charge_db) < 0.05 and absf(_dialogue_db() - dialogue_db) < 0.05:
			return
		await get_tree().process_frame


func test_floor_the_three_seams_exist() -> void:
	assert_true(SoundManager.has_method("duck_for_charge"), "SoundManager.duck_for_charge is gone")
	assert_true(SoundManager.has_method("play_voiced_line"), "SoundManager.play_voiced_line is gone")
	assert_true(BattleManager.has_signal("boss_cadence_bark"), "BattleManager.boss_cadence_bark is gone; the break is silent")
	assert_ne(SoundManager.CHARGE_DUCK_EFFECT_SLOT, 0, "the charge dip must not share the dialogue duck's slot")


func test_a_broken_charge_hands_the_bed_from_the_dip_to_the_voice() -> void:
	var boss := _glacius()
	assert_ne(SoundManager.voiced_line_clip("Glacius", "...Oh. That was new."), "", "CONTROL: the break bark has a recording")
	var scene = load(SCENE).instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	_quiet()
	Engine.time_scale = 0.25
	BattleManager.boss_charge_changed.emit(boss, true)
	await _settle(SoundManager.CHARGE_DUCK_TARGET_DB, 0.0)
	assert_almost_eq(SoundManager.get_charge_duck_db(), SoundManager.CHARGE_DUCK_TARGET_DB, 0.05, "CONTROL: a full-tier charge dips the bed")
	assert_almost_eq(_dialogue_db(), 0.0, 0.05, "CONTROL: nobody is speaking yet")
	Engine.time_scale = 1.0
	BattleManager._on_cadence_status("stun", boss)
	assert_true(SoundManager.is_voiced_line_playing(), "CONTROL: the break bark speaks")
	assert_false(SoundManager.is_music_ducked_for_charge(), "the break must release the charge dip")
	assert_true(SoundManager.is_music_ducked_for_dialogue(), "the voiced bark must take the dialogue duck")
	await _settle(0.0, SoundManager.DUCK_TARGET_DB)
	assert_almost_eq(SoundManager.get_charge_duck_db(), 0.0, 0.05, "under the voice the charge slot must reach 0, read %.2f dB" % SoundManager.get_charge_duck_db())
	assert_almost_eq(_dialogue_db(), SoundManager.DUCK_TARGET_DB, 0.05, "while he speaks the dialogue slot must hold its depth, read %.2f dB" % _dialogue_db())
	assert_true(SoundManager.is_voiced_line_playing(), "the line must still be speaking when both settle, or the depth read is the release")
