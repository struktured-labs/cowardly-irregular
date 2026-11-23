extends GutTest

## A boss winding up its signature leans the bed back ~4 dB and holds it there until the breath is let go,
## broken, or the boss dies (main 23917, on cowir-battle's boss_charge_changed edges). Silent at turbo/console.

const BattleSceneScript := preload("res://src/battle/BattleScene.gd")
const GdSource := preload("res://test/unit/helpers/gd_source.gd")
const BOUND_MS := 3000

var _scene = null
var _saved_scale: float = 1.0


func before_each() -> void:
	_saved_scale = Engine.time_scale
	SoundManager.clear_charge_duck()
	await _settle(0.0)


func after_each() -> void:
	Engine.time_scale = _saved_scale
	if _scene != null and is_instance_valid(_scene):
		_scene.free()
	_scene = null
	SoundManager.clear_charge_duck()
	var idx: int = AudioServer.get_bus_index(SoundManager.MUSIC_DUCK_BUS)
	if idx != -1:
		for slot in range(AudioServer.get_bus_effect_count(idx)):
			var e = AudioServer.get_bus_effect(idx, slot)
			if e:
				e.volume_db = 0.0


## Wait for the CONDITION under a wall-clock bound: the envelope ignores time scale, so a scaled timer would race it.
func _settle(target_db: float) -> float:
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < BOUND_MS:
		if absf(SoundManager.get_charge_duck_db() - target_db) < 0.05:
			break
		await get_tree().process_frame
	return SoundManager.get_charge_duck_db()


func _boss() -> Combatant:
	var b := Combatant.new()
	b.combatant_name = "Glacius"
	autofree(b)
	return b


func test_floor_the_duck_and_its_signal_exist() -> void:
	assert_true(SoundManager.has_method("duck_for_charge"), "SoundManager.duck_for_charge is gone; every arm below would abort")
	assert_true(BattleManager.has_signal("boss_charge_changed"), "BattleManager.boss_charge_changed is gone; nothing can start the dip")
	assert_true(BattleSceneScript.new().has_method("_on_boss_charge_changed"), "BattleScene no longer listens for a charge")
	assert_eq(SoundManager.CHARGE_DUCK_TARGET_DB, -4.0, "main 23917 asked for about -4 dB; change it only on his ear")
	assert_gt(SoundManager.CHARGE_DUCK_TARGET_DB, SoundManager.DUCK_TARGET_DB, "a charge is a lean, not a conversation: shallower than the dialogue duck")


func test_a_charge_dips_the_bed_and_holds_until_it_is_let_go() -> void:
	var boss := _boss()
	assert_almost_eq(SoundManager.get_charge_duck_db(), 0.0, 0.05, "CONTROL: the bed must start at rest")
	SoundManager.duck_for_charge(true, boss)
	var dipped: float = await _settle(SoundManager.CHARGE_DUCK_TARGET_DB)
	assert_almost_eq(dipped, SoundManager.CHARGE_DUCK_TARGET_DB, 0.05, "a charging boss must lean the bed to the charge depth, read %.2f dB" % dipped)
	await get_tree().create_timer(0.4, true, false, true).timeout
	assert_almost_eq(SoundManager.get_charge_duck_db(), SoundManager.CHARGE_DUCK_TARGET_DB, 0.05, "the dip must HOLD while the boss charges, not spring back like the kill duck")
	SoundManager.duck_for_charge(false, boss)
	var back: float = await _settle(0.0)
	assert_almost_eq(back, 0.0, 0.05, "the release must bring the bed back to 0, read %.2f dB" % back)


func test_one_boss_letting_go_does_not_lift_anothers_charge() -> void:
	var a := _boss()
	var b := _boss()
	SoundManager.duck_for_charge(true, a)
	SoundManager.duck_for_charge(true, b)
	await _settle(SoundManager.CHARGE_DUCK_TARGET_DB)
	SoundManager.duck_for_charge(false, a)
	await get_tree().create_timer(0.5, true, false, true).timeout
	assert_almost_eq(SoundManager.get_charge_duck_db(), SoundManager.CHARGE_DUCK_TARGET_DB, 0.05, "A released while B still charges: the bed must stay down")
	SoundManager.duck_for_charge(false, b)
	assert_almost_eq(await _settle(0.0), 0.0, 0.05, "the LAST release must lift it")


func test_the_charge_duck_leaves_the_other_ducks_alone() -> void:
	SoundManager.duck_music_for_dialogue(true, self)
	SoundManager.duck_for_charge(true, _boss())
	await _settle(SoundManager.CHARGE_DUCK_TARGET_DB)
	var idx: int = AudioServer.get_bus_index(SoundManager.MUSIC_DUCK_BUS)
	var dialogue = AudioServer.get_bus_effect(idx, 0)
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < BOUND_MS and absf(dialogue.volume_db - SoundManager.DUCK_TARGET_DB) > 0.05:
		await get_tree().process_frame
	SoundManager.clear_charge_duck()
	await _settle(0.0)
	assert_almost_eq(dialogue.volume_db, SoundManager.DUCK_TARGET_DB, 0.05, "releasing the charge must not release the dialogue duck on slot 0")
	SoundManager.duck_music_for_dialogue(false, self)


func test_battle_end_clears_a_charge_nobody_released() -> void:
	SoundManager.duck_for_charge(true, _boss())
	await _settle(SoundManager.CHARGE_DUCK_TARGET_DB)
	SoundManager.clear_charge_duck()
	assert_false(SoundManager.is_music_ducked_for_charge(), "clear must forget every charging boss")
	assert_almost_eq(await _settle(0.0), 0.0, 0.05, "a charge left over from a fight must not lean the next bed")


func test_the_scene_dips_on_the_real_signal_at_full_tier() -> void:
	_scene = BattleSceneScript.new()
	BattleManager.boss_charge_changed.connect(_scene._on_boss_charge_changed)
	Engine.time_scale = 0.25
	var boss := _boss()
	BattleManager.boss_charge_changed.emit(boss, true)
	BattleManager.boss_charge_changed.disconnect(_scene._on_boss_charge_changed)
	assert_true(SoundManager.is_music_ducked_for_charge(), "a FULL-tier battle hearing boss_charge_changed(true) must take the charge duck")
	assert_almost_eq(await _settle(SoundManager.CHARGE_DUCK_TARGET_DB), SoundManager.CHARGE_DUCK_TARGET_DB, 0.05, "and the bed must actually dip")


func _body_of(code: String, fn: String) -> String:
	var at: int = code.find("\nfunc %s(" % fn)
	assert_gt(at, -1, "FLOOR: BattleScene.%s is gone" % fn)
	var end: int = code.find("\nfunc ", at + 1)
	return code.substr(at) if end < 0 else code.substr(at, end - at)


## The arms above drive the handler directly; this is what proves a REAL battle ever reaches it, and lets go when it ends.
func test_the_scene_wires_the_charge_in_and_clears_it_on_the_way_out() -> void:
	var code: String = GdSource.code_of("res://src/battle/BattleScene.gd")
	assert_true(_body_of(code, "_ready").contains("BattleManager.boss_charge_changed.connect(_on_boss_charge_changed)"), "BattleScene._ready must connect boss_charge_changed, or no battle ever dips")
	var leaving: String = _body_of(code, "_exit_tree")
	assert_true(leaving.contains("boss_charge_changed.disconnect(_on_boss_charge_changed)"), "a freed scene must stop listening")
	assert_true(leaving.contains("SoundManager.clear_charge_duck()"), "a scene freed mid-charge must clear the dip")
	assert_true(_body_of(code, "_on_battle_ended").contains("SoundManager.clear_charge_duck()"), "battle end must clear the dip whatever path ended it")


func test_turbo_and_the_console_never_dip_but_always_release() -> void:
	_scene = BattleSceneScript.new()
	var boss := _boss()
	Engine.time_scale = 0.25
	_scene._on_boss_charge_changed(boss, true)
	assert_true(SoundManager.is_music_ducked_for_charge(), "CONTROL: the same call at 1x must dip, or the silent arms below prove nothing")
	_scene._on_boss_charge_changed(boss, false)
	_scene.turbo_mode = true
	_scene._on_boss_charge_changed(boss, true)
	assert_false(SoundManager.is_music_ducked_for_charge(), "turbo must not dip the bed")
	_scene.turbo_mode = false
	_scene.autogrind_console_mode = true
	_scene._on_boss_charge_changed(boss, true)
	assert_false(SoundManager.is_music_ducked_for_charge(), "the autogrind console must not dip the bed")
	_scene.autogrind_console_mode = false
	_scene._on_boss_charge_changed(boss, true)
	_scene.turbo_mode = true
	_scene._on_boss_charge_changed(boss, false)
	assert_false(SoundManager.is_music_ducked_for_charge(), "a release at turbo must still let go: speeding up mid-charge cannot strand the dip")
