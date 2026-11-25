extends GutTest

## The grid editor's Simulate readout (R) was a bare column at (80, 90): no width, no wrap, no scroll, while every line
## scaled with Text Size. At 200% a grid with many rules ran off the bottom of the screen and long lines off the right,
## and "any key closes" left no way to read the rest. It now wraps inside a screen-sized scroll that Up/Down move.

const EDITOR := "res://src/ui/autobattle/AutobattleGridEditor.gd"
const CID := "sim_scroll_probe"
const ABProfiles := preload("res://test/unit/helpers/autobattle_profiles.gd")

var _ab_profiles_entry: Dictionary = {}
var _saved_persist: bool = false
var _saved_scale = null


func before_all() -> void:
	_ab_profiles_entry = ABProfiles.snapshot(AutobattleSystem)


func after_all() -> void:
	ABProfiles.restore(AutobattleSystem, _ab_profiles_entry)


func before_each() -> void:
	_saved_persist = AutobattleSystem._test_disable_persistence
	AutobattleSystem._test_disable_persistence = true
	_saved_scale = GameState.text_size_scale
	AutobattleSystem.reset_rule_fire_counts(CID)


func after_each() -> void:
	AutobattleSystem.reset_rule_fire_counts(CID)
	AutobattleSystem._test_disable_persistence = _saved_persist
	GameState.text_size_scale = _saved_scale


func _presets() -> Array:
	var p: Array = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must resolve, or every preset loop passes empty: " + str(p))
	return p


func _rule(threshold: int) -> Dictionary:
	return {"enabled": true, "conditions": [{"type": "hp_percent", "op": "<", "value": threshold}],
		"actions": [{"type": "attack", "target": "lowest_hp_enemy"}]}


## The editor on a 1280x720 screen with Simulate open over `n` saved rules that have fought (so OBSERVED lists each).
func _simulate_at(scale: float, n: int) -> Node:
	GameState.text_size_scale = scale
	var rules: Array = []
	for i in n:
		rules.append(_rule(90 - i * 5))
	AutobattleSystem.set_character_script(CID, {"character_id": CID, "name": "Probe", "rules": rules.duplicate(true)})
	AutobattleSystem._rule_eval_counts[CID] = 40
	var fired: Dictionary = {}
	for i in n:
		fired[i] = i + 1
	AutobattleSystem._rule_fire_counts[CID] = fired
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	add_child_autofree(vp)
	var ed: Node = load(EDITOR).new()
	ed.character_id = CID
	ed.rules = rules
	vp.add_child(ed)
	await get_tree().process_frame
	ed._open_simulate()
	for i in 3:
		await get_tree().process_frame
	return ed


func _scroll(ed: Node) -> ScrollContainer:
	return ed._simulate_panel.get_node("SimulateScroll")


func _hint(ed: Node) -> Label:
	return ed._simulate_panel.find_child("SimulateHint", true, false)


func _press(ed: Node, nav: String) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = JOY_BUTTON_DPAD_DOWN if nav == "ui_down" else (JOY_BUTTON_DPAD_UP if nav == "ui_up" else JOY_BUTTON_X)
	ev.pressed = true
	ed._handle_simulate_input(ev, nav)


## CONTROL: at the largest preset twelve fought rules are taller than the screen, so the arms below can see a loss.
func test_control_a_long_readout_outgrows_the_screen() -> void:
	var p: Array = _presets()
	var ed: Node = await _simulate_at(float(p.max()), 12)
	var lines: Control = _scroll(ed).get_node("SimulateLines")
	assert_gt(lines.get_combined_minimum_size().y + 90.0, 720.0, "CONTROL: the readout is taller than the screen at %.2fx" % float(p.max()))


## Every preset: every line wraps inside the scroll's width, keeps its Text Size, and the hint sits on screen.
func test_every_line_wraps_inside_the_screen_and_the_hint_is_on_it() -> void:
	var bad: Array = []
	for scale in _presets():
		var ed: Node = await _simulate_at(float(scale), 12)
		var sc: ScrollContainer = _scroll(ed)
		if sc.position.x + sc.size.x > 1280.5 or sc.position.y + sc.size.y > 720.5:
			bad.append("%.2fx the scroll ends at (%.0f, %.0f) off a 1280x720 screen" % [scale, sc.position.x + sc.size.x, sc.position.y + sc.size.y])
		for l in sc.get_node("SimulateLines").get_children():
			var lab := l as Label
			if lab.size.x > sc.size.x + 0.5:
				bad.append("%.2fx '%s' is %.0f wide in a %.0f scroll" % [scale, lab.text.left(30), lab.size.x, sc.size.x])
			if lab.autowrap_mode == TextServer.AUTOWRAP_OFF:
				bad.append("%.2fx '%s' does not wrap" % [scale, lab.text.left(30)])
		var h: Label = _hint(ed)
		var hr: Rect2 = h.get_global_rect()
		if hr.end.y > 720.5 or hr.position.y < sc.position.y:
			bad.append("%.2fx the hint ends at %.0f, off screen or above the readout" % [scale, hr.end.y])
		if ed._simulate_overflows() and not h.text.contains("Up/Down"):
			bad.append("%.2fx the readout scrolls but its hint does not say how: '%s'" % [scale, h.text])
	assert_eq(bad, [], "the Simulate readout fits the screen: %s" % [bad])


## Down walks the long readout to its end and keeps it open; Up walks back; any other press still closes.
func test_down_reaches_the_last_line_and_another_press_closes() -> void:
	var p: Array = _presets()
	var ed: Node = await _simulate_at(float(p.max()), 12)
	var sc: ScrollContainer = _scroll(ed)
	assert_true(ed._simulate_overflows(), "PRECONDITION: the readout overflows")
	for i in 60:
		_press(ed, "ui_down")
	await get_tree().process_frame
	assert_not_null(ed._simulate_panel, "Down scrolls the readout instead of closing it")
	var last: Label = sc.get_node("SimulateLines").get_children().back()
	var bottom_in_view: float = last.position.y + last.size.y - float(sc.scroll_vertical)
	assert_lte(bottom_in_view, sc.size.y + 0.5, "Down reaches the readout's last line ('%s')" % last.text)
	var deep: int = sc.scroll_vertical
	_press(ed, "ui_up")
	assert_lt(sc.scroll_vertical, deep, "Up scrolls back")
	_press(ed, "")
	assert_null(ed._simulate_panel, "any other press still closes the readout")


## 100% with a short grid: nothing overflows, the hint keeps its words, and Down still closes as it always did.
func test_a_short_readout_at_100_percent_is_unchanged() -> void:
	var ed: Node = await _simulate_at(1.0, 2)
	assert_false(ed._simulate_overflows(), "PRECONDITION: two rules fit the screen at 100%")
	assert_eq(_hint(ed).text, "Rules are first-match-wins, top to bottom. Any key closes.", "the hint keeps its words")
	assert_eq(_scroll(ed).position, Vector2(80, 90), "the readout starts where it always did")
	_press(ed, "ui_down")
	assert_null(ed._simulate_panel, "with nothing to scroll, Down closes as before")
