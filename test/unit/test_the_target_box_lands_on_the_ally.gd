extends GutTest

## The acting character stands 80px forward for their whole selection turn, but an ally target row carried the sprite's
## HOME position, so targeting yourself with a Potion or Cure drew the highlight box on empty air beside the next party
## member. Ally rows now ask the scene where the member is standing.

const BattleScene := preload("res://src/battle/BattleScene.gd")
const MENU_PATH := "res://src/battle/BattleCommandMenu.gd"
const SCENE_PATH := "res://src/battle/BattleScene.gd"

var _scene = null
var _menu: BattleCommandMenu = null


func before_each() -> void:
	_scene = BattleScene.new()
	for i in 3:
		var s := AnimatedSprite2D.new()
		s.set_meta("home_position", Vector2(950, 180 + 120 * i))
		_scene.party_sprite_nodes.append(s)
	_menu = BattleCommandMenu.new(_scene)


func after_each() -> void:
	_menu = null
	for s in _scene.party_sprite_nodes:
		s.free()
	_scene.free()


func test_nobody_stepped_out_means_everyone_is_at_home() -> void:
	for i in 3:
		assert_eq(_menu._ally_target_pos(i), Vector2(950, 180 + 120 * i), "member %d is targeted at home" % i)


func test_the_acting_member_is_targeted_where_they_stand() -> void:
	_scene._mark_stepped_out(1, true)
	assert_eq(_menu._ally_target_pos(1), Vector2(950 + BattleScene.ACTIVE_PC_STEP_OUT_OFFSET, 300), "the stepped-out member's box moves with them")
	assert_ne(BattleScene.ACTIVE_PC_STEP_OUT_OFFSET, 0.0, "CONTROL: the step-out is a real distance")
	assert_eq(_menu._ally_target_pos(0), Vector2(950, 180), "the others stay at home")
	assert_eq(_menu._ally_target_pos(2), Vector2(950, 420), "the others stay at home")


func test_stepping_back_puts_the_box_back() -> void:
	_scene._mark_stepped_out(1, true)
	_scene._mark_stepped_out(1, false)
	assert_eq(_menu._ally_target_pos(1), Vector2(950, 300), "back in formation, back at home")


func test_a_late_step_back_does_not_cancel_the_next_turn() -> void:
	_scene._mark_stepped_out(1, true)
	_scene._mark_stepped_out(2, true)
	_scene._mark_stepped_out(1, false)
	assert_eq(_menu._ally_target_pos(2), Vector2(950 + BattleScene.ACTIVE_PC_STEP_OUT_OFFSET, 420), "member 2 is still out")


func test_a_missing_sprite_has_no_box() -> void:
	assert_eq(_menu._ally_target_pos(7), Vector2.ZERO, "out of range means no highlight")
	assert_eq(_menu._ally_target_pos(-1), Vector2.ZERO, "out of range means no highlight")


func test_every_ally_row_asks_the_helper_and_the_step_reports_itself() -> void:
	var menu := FileAccess.get_file_as_string(MENU_PATH)
	assert_eq(menu.count("= _ally_target_pos(i)"), 3, "ability, revive and item ally rows all use the helper")
	var scene := FileAccess.get_file_as_string(SCENE_PATH)
	var at := scene.find("func _step_active_pc(")
	var next := scene.find("\nfunc ", at + 1)
	var body := scene.substr(at) if next < 0 else scene.substr(at, next - at)
	assert_gt(at, -1, "CONTROL: _step_active_pc exists")
	assert_true(body.contains("_mark_stepped_out(idx, step_out)"), "the step tween records who is standing out")
