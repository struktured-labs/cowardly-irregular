extends GutTest

## Regression (cowir-main's .595 victory frames): the battle hint bar ("[Q] Defer · [W] Advance · [`] Speed · [Tab] Auto")
## stayed up under the results screen, advertising controls that do nothing there beside the results' own
## "X: continue". The bar now leaves with the battle, as the turn header already did (.567).

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


func test_the_hint_bar_hides_when_the_battle_ends() -> void:
	_scene = load("res://src/battle/BattleScene.tscn").instantiate()
	add_child(_scene)
	await get_tree().process_frame
	var bar := _scene.get_node_or_null("UI/InputHintBar") as CanvasItem
	assert_not_null(bar, "SCOPE: the battle builds its hint bar")
	if bar == null:
		return
	bar.visible = true
	_scene._on_battle_ended(true)
	assert_false(bar.visible, "the battle shortcuts must not stay up over the results screen")


func test_the_bar_is_up_during_the_battle() -> void:
	_scene = load("res://src/battle/BattleScene.tscn").instantiate()
	add_child(_scene)
	await get_tree().process_frame
	var bar := _scene.get_node_or_null("UI/InputHintBar") as CanvasItem
	assert_true(bar != null and bar.visible, "CONTROL: the hint bar is shown while the battle runs")
