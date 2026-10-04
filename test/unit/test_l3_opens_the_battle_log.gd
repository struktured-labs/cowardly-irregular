extends GutTest

## struktured 2026-10-04: "reuse L3" for the full battle log. Every other pad button is claimed in battle; L3 doubled as Start
## (ui_menu). BattleScene now takes L3 to open and close the full log, and marks it handled so ui_menu never sees it in battle.

const BattleStateHelper := preload("res://test/unit/helpers/battle_state.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")

var _bm: RefCounted = null
var _scene: Node = null


func before_each() -> void:
	_bm = BattleStateHelper.new()
	_bm.snapshot()


func after_each() -> void:
	if _scene and is_instance_valid(_scene):
		_scene.queue_free()
	_scene = null
	if _bm != null:
		_bm.restore()


func after_all() -> void:
	SoundState.restore()


func _l3() -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = JOY_BUTTON_LEFT_STICK
	e.pressed = true
	return e


func _overlay_up() -> bool:
	return _scene._log_overlay != null and is_instance_valid(_scene._log_overlay)


func test_l3_opens_and_closes_the_full_log() -> void:
	_scene = load("res://src/battle/BattleScene.tscn").instantiate()
	add_child(_scene)
	await get_tree().process_frame
	## _input rightly ignores every press while a tutorial tip is up; this arm tests L3, so it holds the tip gate open and restores it.
	var saved_tips: int = TutorialHint._active_count
	TutorialHint._active_count = 0
	assert_false(TutorialHint.is_any_active(), "SCOPE: no tutorial tip is capturing input")
	assert_false(_overlay_up(), "CONTROL: the full log starts closed")
	_scene._input(_l3())
	await get_tree().process_frame
	assert_true(_overlay_up(), "L3 opens the full battle log")
	_scene._input(_l3())
	await get_tree().process_frame
	assert_false(_overlay_up(), "L3 again closes it")
	TutorialHint._active_count = saved_tips
