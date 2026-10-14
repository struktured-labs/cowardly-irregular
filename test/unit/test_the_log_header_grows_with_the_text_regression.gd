extends GutTest

## LogTitle and LogExpandButton are two of BattleScene's themed scene nodes — no font override in the
## `.tscn`, and nothing scales the project theme (there is no project theme), so they ignored Text
## Size entirely. They sit in LogHeader, which IS the battle log panel's chrome.
##
## ⛔ THAT IS WHY THEY COULD NOT BE SCALED BEFORE ce12bc8ab. The panel budgeted its text with a
## hand-measured NON_TEXT_OVERHEAD of 64 — "the LogHeader row + MarginContainer insets", per its own
## comment. Growing the header against that literal over-budgets the text, the panel's true minimum
## passes hard_bottom_cap, and `_reposition_battle_log_panel_now` HIDES THE WHOLE LOG. The arm below
## named for that is the one that would red if the chrome derivation were reverted.
##
## The font is scaled from each node's OWN captured size, so 100% is identical to before.

const SCENE := "res://src/battle/BattleScene.tscn"
const TITLE_PATH := "UI/BattleLogPanel/MarginContainer/VBoxContainer/LogHeader/LogTitle"
const BUTTON_PATH := "UI/BattleLogPanel/MarginContainer/VBoxContainer/LogHeader/LogExpandButton"
## ⛔ Adding a BattleScene to the tree STARTS A BATTLE on the BattleManager autoload, and this
## file instantiates one. Without a restore, test_battle_state_not_leaked_by_tests reds after
## it ("state=3") — which is how the first version of this stack was dropped from .691.
## The helper derives its surface from get_property_list(), so a field added tomorrow is
## covered without editing anything; a hand-written teardown covers only the fields its
## author thought of, which is the failure its own docstring records twice.
const BattleStateHelper := preload("res://test/unit/helpers/battle_state.gd")
const PRESETS: Array = [0.8, 1.0, 1.25, 1.5, 2.0]

var _saved_scale: float = 1.0
var _scene: Node = null
var _battle_state: RefCounted = null


func before_each() -> void:
	_battle_state = BattleStateHelper.new()
	_battle_state.snapshot()
	_saved_scale = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.text_size_scale = _saved_scale
	if _scene and is_instance_valid(_scene):
		_scene.queue_free()
	_scene = null
	## LAST, not first: queue_free()ing the scene above can re-dirty the autoload, and the
	## helper's own note says a restore must follow any line that does.
	if _battle_state != null:
		_battle_state.restore()
func _build(scale: float) -> Node:
	GameState.text_size_scale = scale
	var n: Node = load(SCENE).instantiate()
	add_child(n)
	await get_tree().process_frame
	return n


func _px(n: Node, path: String) -> int:
	var c: Control = n.get_node_or_null(path)
	if c == null:
		return -1
	return c.get_theme_font_size("font_size")


## FLOOR: the nodes these arms drive. A scene-path typo would otherwise make every arm compare -1 to
## -1 and pass, which is the vacuous shape a path-keyed fixture fails into.
func test_the_header_nodes_exist_at_their_paths() -> void:
	_scene = await _build(1.0)
	assert_false(_scene.get_node_or_null(TITLE_PATH) == null,
		"FLOOR: LogTitle must exist at its path, or every size arm compares -1 to -1 and passes")
	assert_false(_scene.get_node_or_null(BUTTON_PATH) == null,
		"FLOOR: LogExpandButton must exist at its path")
	assert_true(_scene.has_method("_scale_themed_font"),
		"FLOOR: _scale_themed_font is what applies the scale")


func test_both_header_fonts_follow_the_setting_in_both_directions() -> void:
	_scene = await _build(1.0)
	var base_t: int = _px(_scene, TITLE_PATH)
	var base_b: int = _px(_scene, BUTTON_PATH)
	assert_gt(base_t, 0, "CONTROL: LogTitle must resolve a font size at 100%")
	assert_gt(base_b, 0, "CONTROL: LogExpandButton must resolve a font size at 100%")
	_scene.queue_free()
	_scene = await _build(2.0)
	var big_t: int = _px(_scene, TITLE_PATH)
	var big_b: int = _px(_scene, BUTTON_PATH)
	_scene.queue_free()
	_scene = await _build(0.8)
	var small_t: int = _px(_scene, TITLE_PATH)
	var small_b: int = _px(_scene, BUTTON_PATH)
	assert_gt(big_t, base_t, "LogTitle must GROW at 200%%: 100%%=%d 200%%=%d" % [base_t, big_t])
	assert_gt(big_b, base_b, "LogExpandButton must GROW at 200%%: 100%%=%d 200%%=%d" % [base_b, big_b])
	assert_lt(small_t, base_t, "and LogTitle must SHRINK at 80%%: %d vs %d" % [small_t, base_t])
	assert_lt(small_b, base_b, "and LogExpandButton must SHRINK at 80%%: %d vs %d" % [small_b, base_b])


## Every preset, not just the endpoints — a defect in this class started at 125% on another surface.
func test_every_preset_moves_the_header_fonts_monotonically() -> void:
	var seen: Array = []
	for s in PRESETS:
		_scene = await _build(float(s))
		seen.append(_px(_scene, TITLE_PATH))
		_scene.queue_free()
		_scene = null
		await get_tree().process_frame
	for i in range(1, seen.size()):
		assert_true(int(seen[i]) >= int(seen[i - 1]),
			"LogTitle's font must never shrink as the setting rises: %s for %s"
			% [str(seen), str(PRESETS)])
	assert_true(int(seen[-1]) > int(seen[0]),
		"and the ladder must move across the range: %s" % str(seen))


## THE ARM THIS ITEM EXISTS BEHIND: a scaled header must not hide the log. Reverting ce12bc8ab's
## derived chrome to the 64 literal reds exactly this.
func test_a_scaled_header_does_not_hide_the_log() -> void:
	_scene = await _build(2.0)
	var panel: Control = _scene.get_node_or_null("UI/BattleLogPanel")
	var enemy: Control = _scene.get_node_or_null("UI/EnemyStatusPanel")
	var log_label: Control = _scene.get_node_or_null(
		"UI/BattleLogPanel/MarginContainer/VBoxContainer/BattleLog")
	assert_false(panel == null or enemy == null or log_label == null,
		"fixture: panel, enemy panel and log label must exist")
	if panel == null or enemy == null or log_label == null:
		return
	## A tall pull, so the gap is tight enough for a mis-budgeted reserve to cross the cap.
	enemy.custom_minimum_size.y = 240.0
	await get_tree().process_frame
	_scene._reposition_battle_log_panel_now()
	await get_tree().process_frame
	assert_true(panel.visible,
		"a header scaled to 200% must not hide the log: against the hand-measured 64 reserve the "
		+ "text is over-budgeted, the panel's true minimum passes hard_bottom_cap and the entire "
		+ "log vanishes — which is why this item waited for the derived chrome")
	assert_true(log_label.size.y <= panel.size.y + 1.0,
		"and the log text box (%.1f) must stay inside its panel (%.1f)"
		% [log_label.size.y, panel.size.y])


## 100% must be IDENTICAL to before the change. The base is each node's own captured size, so this
## is a property of the mechanism rather than of a number I picked.
func test_one_hundred_percent_is_unchanged() -> void:
	_scene = await _build(1.0)
	var title: Control = _scene.get_node_or_null(TITLE_PATH)
	assert_false(title == null, "fixture: LogTitle must exist")
	if title == null:
		return
	var applied: int = title.get_theme_font_size("font_size")
	var captured: int = int(title.get_meta(&"base_font_px", -1))
	assert_gt(captured, 0,
		"the base must be captured from the node itself, not guessed from the engine default")
	assert_eq(applied, captured,
		"at 100%% the applied size (%d) must equal the captured base (%d) — anything else is a "
		% [applied, captured] + "visual change at the DEFAULT setting, which this item must not make")


## Idempotent: re-applying must scale the captured base again, never the already-scaled override.
## A settings change re-runs this, so a compounding helper would grow the font every time.
func test_reapplying_the_scale_does_not_compound() -> void:
	_scene = await _build(2.0)
	var title: Control = _scene.get_node_or_null(TITLE_PATH)
	assert_false(title == null, "fixture: LogTitle must exist")
	if title == null:
		return
	var once: int = title.get_theme_font_size("font_size")
	_scene._scale_themed_font(title, &"font_size")
	_scene._scale_themed_font(title, &"font_size")
	assert_eq(title.get_theme_font_size("font_size"), once,
		"re-applying must be a no-op: reading get_theme_font_size() after an override returns the "
		+ "OVERRIDE, so a helper that re-reads it compounds on every settings change")
