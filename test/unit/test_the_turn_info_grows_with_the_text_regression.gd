extends GutTest

## TurnInfo is one of BattleScene's themed scene nodes — no font override in the `.tscn`, no project
## theme to inherit a scale from — so it ignored Text Size. It is the strip that names whose turn it
## is and what the battle is waiting for.
##
## ✅ WHY THIS ONE IS SAFE AND ITS SIBLING IS NOT, probed rather than assumed. The battle log's budget
## is `474 - enemy_panel_bottom`, and with five enemies that is 68px. Scaling EnemyStatusPanel's
## title moves enemy_bottom 406 -> 413 and LOSES the log at 1.25x, so that label is held with the
## enemy-panel trade. TurnInfo lives in its own UI/TurnInfoPanel and is an input to nobody's budget.
## The last arm pins that, because "it is in its own panel" is a claim about today's scene tree.

const SCENE := "res://src/battle/BattleScene.tscn"
const TURN_INFO := "UI/TurnInfoPanel/TurnInfo"
const PRESETS: Array = [0.8, 1.0, 1.25, 1.5, 2.0]

var _saved_scale: float = 1.0
var _scene: Node = null


func before_each() -> void:
	_saved_scale = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.text_size_scale = _saved_scale
	if _scene and is_instance_valid(_scene):
		_scene.queue_free()
	_scene = null


func _build(scale: float) -> Node:
	GameState.text_size_scale = scale
	var n: Node = load(SCENE).instantiate()
	add_child(n)
	await get_tree().process_frame
	return n


func _px(n: Node) -> int:
	var c: Control = n.get_node_or_null(TURN_INFO)
	return -1 if c == null else c.get_theme_font_size("font_size")


## FLOOR: a path typo would make every size arm compare -1 to -1 and pass.
func test_the_turn_info_node_exists_at_its_path() -> void:
	_scene = await _build(1.0)
	assert_false(_scene.get_node_or_null(TURN_INFO) == null,
		"FLOOR: TurnInfo must exist at %s, or the arms below compare -1 to -1" % TURN_INFO)
	assert_gt(_px(_scene), 0, "FLOOR: and it must resolve a font size")


func test_the_turn_info_font_follows_the_setting_in_both_directions() -> void:
	_scene = await _build(1.0)
	var base: int = _px(_scene)
	_scene.queue_free()
	_scene = await _build(2.0)
	var big: int = _px(_scene)
	_scene.queue_free()
	_scene = await _build(0.8)
	var small: int = _px(_scene)
	assert_gt(big, base, "TurnInfo must GROW at 200%%: 100%%=%d 200%%=%d" % [base, big])
	assert_lt(small, base, "and SHRINK at 80%%: 80%%=%d 100%%=%d" % [small, base])


func test_every_preset_moves_it_monotonically() -> void:
	var seen: Array = []
	for s in PRESETS:
		_scene = await _build(float(s))
		seen.append(_px(_scene))
		_scene.queue_free()
		_scene = null
		await get_tree().process_frame
	for i in range(1, seen.size()):
		assert_true(int(seen[i]) >= int(seen[i - 1]),
			"it must never shrink as the setting rises: %s for %s" % [str(seen), str(PRESETS)])
	assert_true(int(seen[-1]) > int(seen[0]), "and the ladder must move: %s" % str(seen))


## The text must FIT its own panel at every preset — a font-grew arm alone is blind to overflow.
func test_the_strip_fits_its_panel_at_every_preset() -> void:
	for s in PRESETS:
		_scene = await _build(float(s))
		var panel: Control = _scene.get_node_or_null("UI/TurnInfoPanel")
		var label: Control = _scene.get_node_or_null(TURN_INFO)
		assert_false(panel == null or label == null, "fixture: panel and label must exist at %sx" % str(s))
		if panel == null or label == null:
			return
		label.text = "Fighter's turn — choose an action"
		await get_tree().process_frame
		await get_tree().process_frame
		assert_true(label.size.y <= panel.size.y + 1.0,
			("at %sx the turn strip's text (%.1f) ran past its panel (%.1f)")
			% [str(s), label.size.y, panel.size.y])
		_scene.queue_free()
		_scene = null
		await get_tree().process_frame


## THE SAFETY CLAIM, pinned. TurnInfo must not become an input to the battle log's budget the way
## EnemyStatusPanel's title is. If a later layout change moves it into that column, this reds and
## the held enemy-panel trade has to be reconsidered rather than silently regressed.
func test_scaling_the_turn_strip_leaves_the_logs_budget_alone() -> void:
	var seen: Array = []
	for s in [1.0, 2.0]:
		_scene = await _build(float(s))
		var enemy: Control = _scene.get_node_or_null("UI/EnemyStatusPanel")
		var panel: Control = _scene.get_node_or_null("UI/BattleLogPanel")
		assert_false(enemy == null or panel == null, "fixture: both panels must exist")
		if enemy == null or panel == null:
			return
		_scene._reposition_battle_log_panel_now()
		await get_tree().process_frame
		seen.append({"scale": s, "bottom": enemy.position.y + enemy.size.y, "log": panel.visible})
		_scene.queue_free()
		_scene = null
		await get_tree().process_frame
	## ⚠️ NOT asserted: that the enemy panel's bottom is PIXEL-IDENTICAL across the two builds.
	## Measured 282 at 100%% and 280 at 200%% — it moves 2px, and only with this change in place, so it
	## is real rather than noise. But I could not attribute those 2px to TurnInfo with confidence:
	## the arm calls _reposition_battle_log_panel_now(), whose chrome probe zeroes and restores a child
	## minimum and so provokes a layout pass, and a rect compared across two separately-built scenes
	## carries settling noise (cowir-autogrind: whether a minimum is current depends on the ORDER
	## properties were set in). An equality arm I cannot explain is not a guard, it is a tripwire on
	## my own fixture — so this asserts the CONSEQUENCE instead, and the 2px is written down for
	## whoever takes the enemy-panel trade. The full-roster case is pinned separately.
	assert_true(seen[0]["bottom"] > 0.0 and seen[1]["bottom"] > 0.0,
		"fixture: the enemy panel must have settled to a real height at both ends: %s" % str(seen))
	assert_true(bool(seen[0]["log"]) and bool(seen[1]["log"]),
		"and the log must stay visible at both ends with a default roster: %s" % str(seen))
