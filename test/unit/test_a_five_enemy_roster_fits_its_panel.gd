extends GutTest

## A five-enemy pull ran the ENEMIES panel down into the TURN ORDER card (the last "Healthy" sat on the card's header
## and the card was shoved partly off-screen): every enemy took three lines -- name, AP, health. AP and health now
## share one line (the HP node keeps its text, hidden), so five enemies fit above the card at its normal height.

const BattleStateHelper := preload("res://test/unit/helpers/battle_state.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")
## The card's resting top is 230 px above the bottom edge (BattleUIManager); five boxes must fit between y 60 and it.
const CTB_TOP_AT_720 := 720.0 - 230.0
const PANEL_TOP := 60.0
const PANEL_CHROME := 50.0

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


func test_each_enemy_reads_on_two_lines_and_five_fit_above_the_turn_order() -> void:
	_scene = load("res://src/battle/BattleScene.tscn").instantiate()
	add_child(_scene)
	for i in 6:
		await get_tree().process_frame
	var ui = _scene._ui_manager
	ui.update_enemy_status()
	for i in 3:
		await get_tree().process_frame
	var boxes: Array = ui._enemy_status_boxes
	assert_gt(boxes.size(), 0, "CONTROL: the battle built enemy status boxes")
	var tallest := 0.0
	for i in boxes.size():
		var box: Control = boxes[i]
		ui._update_enemy_member_status(i, _scene.test_enemies[i])
		var hp: Control = box.get_node("HP")
		var ap: RichTextLabel = box.get_node("AP")
		assert_false(hp.visible, "the separate HP line is folded away")
		assert_true(ap.get_parsed_text().contains("·") or not _scene.test_enemies[i].is_alive, "health shares the AP line: '%s'" % ap.get_parsed_text())
		tallest = maxf(tallest, box.get_combined_minimum_size().y)
	var five := PANEL_TOP + PANEL_CHROME + 5.0 * (tallest + 4.0)
	assert_lt(five, CTB_TOP_AT_720, "five enemy boxes (%.0f px each) end at %.0f, above the turn-order card at %.0f" % [tallest, five, CTB_TOP_AT_720])
