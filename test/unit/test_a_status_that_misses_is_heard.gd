extends GutTest

## struktured 2026-11-01: "there's a sfx that sounds like a fart noise when a status effect doesn't land". A failed harmful
## roll used to be silent, so the cast-time debuff sample (a deflating balloon) was all he heard. A miss now says so.

const SCENE := "res://src/battle/BattleScene.tscn"
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


func _target() -> Combatant:
	var t := Combatant.new()
	t.combatant_name = "Goblin"
	t.max_hp = 100
	t.current_hp = 100
	t.is_alive = true
	autofree(t)
	return t


func test_a_harmful_roll_that_misses_is_announced() -> void:
	watch_signals(BattleManager)
	var t := _target()
	assert_false(BattleManager._support_roll_lands(t, "defense_down", 0.0), "PREMISE: a 0% debuff cannot land")
	assert_signal_emitted(BattleManager, "status_resisted", "a debuff that fails must say so, not fall silent")


func test_a_harmful_roll_that_lands_is_not_a_resist() -> void:
	watch_signals(BattleManager)
	assert_true(BattleManager._support_roll_lands(_target(), "defense_down", 1.0), "PREMISE: a 100% debuff lands")
	assert_signal_not_emitted(BattleManager, "status_resisted", "a landed debuff is not a resist")


func test_a_ward_that_fails_is_not_called_a_resist() -> void:
	watch_signals(BattleManager)
	BattleManager._support_roll_lands(_target(), "barrier", 0.0)
	assert_signal_not_emitted(BattleManager, "status_resisted", "an ally ward is not resisted by anyone")


func test_the_scene_plays_the_resist_tink() -> void:
	var e: Dictionary = SoundManager._sfx_manifest.get("resist_deflect", {})
	assert_false(e.is_empty(), "the resist cue must exist")
	var scene = load(SCENE).instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	SoundManager._sfx_cooldowns.erase("resist_deflect")
	BattleManager.status_resisted.emit(_target(), "poison")
	assert_true(SoundManager._sfx_cooldowns.has("resist_deflect"), "a resisted status must play its tink in a real battle scene")
