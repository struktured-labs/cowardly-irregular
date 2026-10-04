extends GutTest

## Regression (visible in cowir-battle's victory screenshots, 2026-10-03): the battle header read "Round 1 - SELECT: Fighter (AP: +1)"
## on top of the VICTORY screen. update_turn_info only rewrites it during selection/execution, so the last selection text stayed up.
## The header now hides when the battle ends.

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


func test_the_header_hides_when_the_battle_ends() -> void:
	_scene = load("res://src/battle/BattleScene.tscn").instantiate()
	add_child(_scene)
	await get_tree().process_frame
	var panel := _scene.get_node_or_null("UI/TurnInfoPanel") as CanvasItem
	assert_not_null(panel, "SCOPE: the turn header exists")
	panel.visible = true
	_scene.turn_info.text = "Round 1 - SELECT: Fighter (AP: +1)"
	_scene._on_battle_ended(true)
	assert_false(panel.visible, "the selection header must not stay up over the victory screen")
