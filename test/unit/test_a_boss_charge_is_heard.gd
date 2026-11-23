extends GutTest

## A boss spending a turn gathering power (battle's BossCadence) is HEARD: a rising draw-in on the charge's rising edge and a
## snap when a stun or silence breaks it. The false edge (release, death, end of battle) is silent on purpose: the release
## is the signature, which keeps its own ability cue, so a second sound there would double it.

const SCENE := "res://src/battle/BattleScene.tscn"
const CUES := ["boss_charge_gather", "boss_charge_broken"]
const BattleState := preload("res://test/unit/helpers/battle_state.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")

var _guard: RefCounted = null


func before_each() -> void:
	_guard = BattleState.new()
	_guard.snapshot()


func after_each() -> void:
	if _guard != null:
		_guard.restore()


func after_all() -> void:
	SoundState.restore()


func _boss() -> Combatant:
	var b := Combatant.new()
	b.combatant_name = "Glacius"
	b.max_hp = 100
	b.current_hp = 100
	b.is_alive = true
	autofree(b)
	return b


func _scene() -> Node:
	var scene = load(SCENE).instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	for k in CUES:
		SoundManager._sfx_cooldowns.erase(k)
	return scene


func test_both_cues_are_registered_with_a_file_and_their_generator() -> void:
	for k in CUES:
		var e: Dictionary = SoundManager._sfx_manifest.get(k, {})
		assert_false(e.is_empty(), "%s must be in the sfx manifest" % k)
		assert_true(FileAccess.file_exists(str(e.get("file", ""))), "%s must name a file that exists" % k)
		assert_eq(str(e.get("source", "")), "tools/gen_charge_cues.py " + k, "%s must name the script that regenerates it" % k)


func test_the_rising_edge_draws_the_breath() -> void:
	await _scene()
	BattleManager.boss_charge_changed.emit(_boss(), true)
	assert_true(SoundManager._sfx_cooldowns.has("boss_charge_gather"), "a boss starting its charge must be heard in a real battle scene")
	assert_false(SoundManager._sfx_cooldowns.has("boss_charge_broken"), "a charge starting is not a charge breaking")


func test_the_falling_edge_is_silent_and_the_rising_edge_is_its_control() -> void:
	await _scene()
	BattleManager.boss_charge_changed.emit(_boss(), false)
	assert_false(SoundManager._sfx_cooldowns.has("boss_charge_gather"), "a release, death or end_battle must not replay the gather")
	assert_false(SoundManager._sfx_cooldowns.has("boss_charge_broken"), "a release is not a break")
	BattleManager.boss_charge_changed.emit(_boss(), true)
	assert_true(SoundManager._sfx_cooldowns.has("boss_charge_gather"), "CONTROL: the same scene and signal DO play on the rising edge, so the silence above is the edge rule")


func test_a_broken_charge_snaps() -> void:
	await _scene()
	BattleManager.boss_charge_broken.emit(_boss(), "stun")
	assert_true(SoundManager._sfx_cooldowns.has("boss_charge_broken"), "a stun that breaks the charge must be heard")
	assert_false(SoundManager._sfx_cooldowns.has("boss_charge_gather"), "a break must not sound like a fresh charge")


func test_the_scene_lets_go_of_both_signals_when_it_leaves() -> void:
	var scene = load(SCENE).instantiate()
	add_child(scene)
	await get_tree().process_frame
	var sound := Callable(scene, "_on_boss_charge_sound")
	var snap := Callable(scene, "_on_boss_charge_broken")
	assert_true(BattleManager.boss_charge_changed.is_connected(sound), "PREMISE: the scene listens for the charge edge")
	assert_true(BattleManager.boss_charge_broken.is_connected(snap), "PREMISE: the scene listens for the break")
	remove_child(scene)
	assert_false(BattleManager.boss_charge_changed.is_connected(sound), "a scene leaving the tree must disconnect its charge sound")
	assert_false(BattleManager.boss_charge_broken.is_connected(snap), "a scene leaving the tree must disconnect its break sound")
	scene.free()
