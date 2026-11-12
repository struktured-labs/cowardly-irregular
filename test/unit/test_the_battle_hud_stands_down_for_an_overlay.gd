extends GutTest

## struktured, playing .792: "the exp cards still overlap with the enemy cards". The victory overlay drew over the enemy
## status panel, which had no way to be asked to leave. BattleScene.hud_stand_down / hud_return is that way: an overlay
## names the surfaces it covers, and gets back exactly what it took.

const SCENE := preload("res://src/battle/BattleScene.tscn")
const BattleStateGuard := preload("res://test/unit/helpers/battle_state.gd")

var _guard
var _scene: Node


func before_each() -> void:
	AutobattleSystem._test_disable_persistence = true
	_guard = BattleStateGuard.new()
	_guard.snapshot()
	_scene = SCENE.instantiate()
	add_child_autofree(_scene)
	await get_tree().process_frame


func after_each() -> void:
	_guard.restore()


func _node(key: String) -> CanvasItem:
	return _scene.get_node_or_null(str(_scene.HUD_SURFACES[key])) as CanvasItem


func test_every_named_surface_is_a_real_node_in_the_scene() -> void:
	for key in _scene.HUD_SURFACES:
		assert_not_null(_node(key), "%s names %s, which the built scene has" % [key, _scene.HUD_SURFACES[key]])
	assert_true(_scene.HUD_SURFACES.has("enemy_panel"), "the enemy panel, the one he saw under the EXP cards, can be named")


func test_an_overlay_takes_what_it_names_and_gets_it_back() -> void:
	var enemy := _node("enemy_panel")
	var log := _node("log")
	var hint := _node("hint_bar")
	enemy.visible = true
	log.visible = true
	hint.visible = true
	_scene.hud_stand_down("victory", ["enemy_panel", "log"])
	assert_true(hint.visible, "CONTROL: a surface it did not name is not touched")
	assert_false(enemy.visible, "the enemy panel stands down")
	assert_false(log.visible, "and the log")
	_scene.hud_return("victory")
	assert_true(enemy.visible, "returned on close")
	assert_true(log.visible, "both")


func test_it_does_not_reveal_what_something_else_had_hidden() -> void:
	var log := _node("log")
	var enemy := _node("enemy_panel")
	enemy.visible = true
	log.visible = false  # hidden by the layout (a tall roster at a big Text Size), not by the overlay
	_scene.hud_stand_down("victory", ["enemy_panel", "log"])
	_scene.hud_return("victory")
	assert_true(enemy.visible, "CONTROL: what the overlay took comes back")
	assert_false(log.visible, "what was already hidden stays hidden: the overlay never owned it")


func test_two_owners_do_not_return_each_others_surfaces() -> void:
	var enemy := _node("enemy_panel")
	var hint := _node("hint_bar")
	enemy.visible = true
	hint.visible = true
	_scene.hud_stand_down("victory", ["enemy_panel"])
	_scene.hud_stand_down("results", ["hint_bar"])
	_scene.hud_return("results")
	assert_true(hint.visible, "the second owner's surface returns")
	assert_false(enemy.visible, "and the first owner's stays down until IT returns")
	_scene.hud_return("victory")
	assert_true(enemy.visible, "CONTROL: then it returns")
	_scene.hud_stand_down("victory", ["no_such_surface"])
	_scene.hud_return("victory")
	assert_true(enemy.visible, "an unknown name is ignored, not an error")
