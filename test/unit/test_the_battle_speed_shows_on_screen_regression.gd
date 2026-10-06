extends GutTest

## struktured (2026-10-06): "battle speed does not show anywhere in battle except the logs".
##
## ⛔ A styled speed readout existed the whole time — BattleScene._create_speed_indicator, colour-coded
## 1x..64x, refreshed by every _toggle_battle_speed. NOTHING CALLED IT: 32f42379f (2026-03-24) removed
## its only call (then a call_deferred by STRING, which a grep for the call shape does not find), so
## _speed_indicator stayed null and _update_speed_indicator returned on its first line. aa197e2a2
## (2026-07-17, "speed indicator forever visible") then restyled a panel that was never built.

const BattleStateHelper := preload("res://test/unit/helpers/battle_state.gd")
const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const BS := preload("res://src/battle/BattleScene.gd")

var _bm: RefCounted = null
var _scene: Node = null
var _saved_index := 0
var _saved_scale := 1.0
var _saved_default = null


func before_each() -> void:
	_bm = BattleStateHelper.new()
	_bm.snapshot()
	_saved_index = BS._battle_speed_index   # static: persists across battles, so it must be restored
	_saved_scale = Engine.time_scale
	_saved_default = GameState.default_battle_speed if "default_battle_speed" in GameState else null


func after_each() -> void:
	if _scene and is_instance_valid(_scene):
		_scene.queue_free()
	_scene = null
	BS._battle_speed_index = _saved_index
	Engine.time_scale = _saved_scale
	if _saved_default != null:
		GameState.default_battle_speed = _saved_default
	if _bm != null:
		_bm.restore()


func after_all() -> void:
	SoundState.restore()


func _battle() -> Node:
	_scene = load("res://src/battle/BattleScene.tscn").instantiate()
	add_child(_scene)
	await get_tree().process_frame
	return _scene


func _readout() -> RichTextLabel:
	return _scene.get_node_or_null("UI/SpeedPanel/SpeedIndicator") as RichTextLabel


func test_the_speed_shows_during_the_battle() -> void:
	await _battle()
	var label := _readout()
	assert_not_null(label, "the battle must build its speed readout — it showed only in the log")
	if label == null:
		return
	var panel := label.get_parent() as Control
	assert_true(panel.visible and label.visible, "the readout is visible while the battle runs")
	var screen: Rect2 = _scene.get_viewport().get_visible_rect()
	assert_true(screen.has_point(panel.position), "and on screen, not parked outside it: %s in %s" % [panel.position, screen])


func test_it_names_the_current_speed() -> void:
	await _battle()
	var label := _readout()
	assert_not_null(label, "PRECONDITION: the readout exists")
	if label == null:
		return
	assert_string_contains(label.get_parsed_text(), BS.BATTLE_SPEED_LABELS[BS._battle_speed_index],
		"the readout must name the speed the battle is running at")


func test_changing_speed_changes_the_readout() -> void:
	await _battle()
	var label := _readout()
	assert_not_null(label, "PRECONDITION: the readout exists")
	if label == null:
		return
	var before := label.get_parsed_text()
	_scene._toggle_battle_speed()
	var now: String = BS.BATTLE_SPEED_LABELS[BS._battle_speed_index]
	assert_string_contains(label.get_parsed_text(), now, "the readout must follow a speed change")
	assert_ne(label.get_parsed_text(), before, "CONTROL: the toggle really moved to another speed")


func test_the_readout_leaves_with_the_battle() -> void:
	await _battle()
	var label := _readout()
	assert_not_null(label, "PRECONDITION: the readout exists")
	if label == null:
		return
	_scene._on_battle_ended(true)
	assert_false((label.get_parent() as CanvasItem).visible,
		"speed means nothing on the results screen, which already drops the other battle shortcuts")


## THE ARM THE FIRST FIX NEEDED: built and "visible" is not readable. The July spot (bottom-left,
## height-222) rendered BEHIND the TURN ORDER box on a real frame (2026-10-06). So: the readout must
## overlap no other visible battle panel. Derived over UI's children, not a list of names, so a panel
## added later is covered too; full-screen overlays (>= half the screen) are not panels and are skipped.
func test_the_readout_overlaps_no_other_panel() -> void:
	await _battle()
	for i in 6:
		await get_tree().process_frame
	var label := _readout()
	assert_not_null(label, "PRECONDITION: the readout exists")
	if label == null:
		return
	var screen: Rect2 = _scene.get_viewport().get_visible_rect()
	var checked := 0
	var hits := []
	## Every speed, not just the default: 16x-64x render wider and larger, and the panel grows left.
	for step in BS.BATTLE_SPEEDS.size():
		await get_tree().process_frame
		await get_tree().process_frame
		var mine: Rect2 = (label.get_parent() as Control).get_global_rect()
		for c in _scene.get_node("UI").get_children():
			if not (c is Control) or c == label.get_parent() or not (c as Control).is_visible_in_tree():
				continue
			var r: Rect2 = (c as Control).get_global_rect()
			if r.size.x <= 0 or r.size.y <= 0 or r.get_area() >= screen.get_area() * 0.5:
				continue
			checked += 1
			if r.intersects(mine):
				hits.append("%s at %s: %s %s" % [BS.BATTLE_SPEED_LABELS[BS._battle_speed_index], mine, c.name, r])
		_scene._toggle_battle_speed()
	assert_gt(checked, 3 * BS.BATTLE_SPEEDS.size(), "CONTROL: other panels to compare against at every speed, found %d" % checked)
	assert_eq(hits, [], "the speed readout is drawn over another panel: %s" % [hits])
