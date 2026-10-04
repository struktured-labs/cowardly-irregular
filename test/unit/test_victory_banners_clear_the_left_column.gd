extends GutTest

## Regression (struktured's play log, 2026-10-04: 112x "Rect2 size is negative" at victory). _place_victory_banner still treated the
## battle log as a FLOOR at the bottom of the screen; since .558 the log lives in the LEFT column with the enemy panel and turn order,
## so the EXP-boost banners' band collapsed to negative height and was handed to intersects(). Column panels are now a left wall.

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


func _banner(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.offset_left = -200
	l.offset_right = 200
	l.offset_top = -40
	l.offset_bottom = 0
	return l


func _settled_scene() -> Node:
	_scene = load("res://src/battle/BattleScene.tscn").instantiate()
	add_child(_scene)
	for i in 6:
		_scene._update_turn_info()
		await get_tree().process_frame
	return _scene


func test_the_banners_land_right_of_the_left_column() -> void:
	var scene: Node = await _settled_scene()
	var log_panel := scene.find_child("BattleLogPanel", true, false) as Control
	assert_not_null(log_panel, "CONTROL: the log panel exists")
	assert_lt(log_panel.get_global_rect().end.x, scene.get_viewport_rect().size.x * 0.3,
		"SCOPE: the log really lives in the left column (the layout this guards)")
	var a := _banner("AUTO-BATTLE!")
	var b := _banner("x1.5 EXP")
	scene.add_child(a)
	scene.add_child(b)
	scene._place_victory_banner([a, b])
	var vp: Vector2 = scene.get_viewport_rect().size
	for l in [a, b]:
		var r: Rect2 = scene._banner_rect(l, vp)
		assert_true(r.has_area(), "a placed banner keeps a positive size (%s)" % r)
		for pname in ["EnemyStatusPanel", "BattleLogPanel", "CTBTimeline"]:
			var p := scene.find_child(pname, true, false) as Control
			if p and p.is_visible_in_tree():
				assert_false(r.intersects(p.get_global_rect()), "'%s' must not sit on %s (%s vs %s)" % [l.text, pname, r, p.get_global_rect()])


func test_no_band_with_no_area_reaches_intersects() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	var i := src.find("func _place_victory_banner")
	assert_gt(i, -1, "SCOPE: the placement function exists")
	var body := src.substr(i, src.find("\nfunc ", i + 1) - i)
	assert_true(body.contains("band.has_area()"), "the occupied-rect loop must refuse a band with no area")
	assert_false(body.contains("r.intersects(Rect2(left, top, right - left, bottom - top))"),
		"the unguarded inline band is what logged 'Rect2 size is negative' 112x")
