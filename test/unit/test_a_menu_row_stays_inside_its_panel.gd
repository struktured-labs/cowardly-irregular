extends GutTest

## struktured playing .792 (2026-11-12): "Teleport btw doesnt quite fit in the border of the settings screen it bleeds
## toward bottom". Measured: the field menu's 21 rows, Teleport LAST, ran 22 px past its panel at 1.0 (no scroll, and no
## guard compared a row with the PANEL it sits in). The rows now wrap into columns, or a cursor-following window where
## columns cannot fit. Every arm measures built nodes. The Settings and Teleport-list censuses that ran beside this one
## found other things (a long header at 1.5+, toggle text at 1.5+) and live on their own tip.

const SETTINGS := "res://src/ui/SettingsMenu.gd"
const FIELD := "res://src/ui/OverworldMenu.gd"
const TELEPORT := "res://src/ui/TeleportMenu.gd"
const CombatantScript := preload("res://src/battle/Combatant.gd")
const SLACK := 0.5

var _saved_scale := 1.0
var _saved_debug := false


func before_each() -> void:
	_saved_scale = float(GameState.text_size_scale)
	_saved_debug = bool(GameState.debug_log_enabled)


func after_each() -> void:
	GameState.text_size_scale = _saved_scale
	GameState.debug_log_enabled = _saved_debug


func _presets() -> Array:
	var p: Array = (load(SETTINGS) as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must hold more than one step")
	return p


func _host(px: Vector2i = Vector2i(1280, 720)) -> CanvasLayer:
	var vp := SubViewport.new()
	vp.size = px
	add_child_autofree(vp)
	var layer := CanvasLayer.new()
	vp.add_child(layer)
	return layer


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


## The nearest ancestor that IS a panel: the one a RetroPanel border was added to (a child named like its border), else
## the screen's first non-full-rect Control. Falls back to the screen.
func _panel_of(node: Control, screen: Control) -> Control:
	var best: Control = screen
	var p := node.get_parent()
	while p != null and p != screen:
		if p is Control and not (p is ScrollContainer) and not (p is VBoxContainer):
			best = p
		p = p.get_parent()
	return best


func _below(inner: Rect2, outer: Rect2) -> float:
	return (inner.position.y + inner.size.y) - (outer.position.y + outer.size.y)


func _above(inner: Rect2, outer: Rect2) -> float:
	return outer.position.y - inner.position.y


## The drawn extent of a Label: its position and its own text's height, not the box it was handed.
func _text_rect(l: Label) -> Rect2:
	var px: int = l.get_theme_font_size("font_size")
	var h: float = maxi(l.get_line_count(), 1) * l.get_theme_font("font").get_height(px)
	return Rect2(l.global_position, Vector2(l.size.x, h))


func test_the_floor_names_every_member_this_file_drives() -> void:
	var f: Control = load(FIELD).new()
	f.set_anchors_preset(Control.PRESET_FULL_RECT)
	_host().add_child(f)
	await _settle()
	assert_true("_menu_labels" in f and "_menu_options" in f and "_menu_windowed" in f and "_menu_window" in f and "_menu_more_up" in f and "_menu_more_down" in f, "OverworldMenu's rows and layout state must exist")
	assert_true(f.has_method("setup") and f.has_method("_nav_step") and f.has_method("_update_selection"), "OverworldMenu's navigation must exist")
	assert_true("text_size_scale" in GameState, "GameState carries the Text Size")


func _field_menu(s: float, px: Vector2i = Vector2i(1280, 720)) -> Control:
	GameState.text_size_scale = s
	var pc = CombatantScript.new()
	pc.combatant_name = "Bram"
	add_child_autofree(pc)
	var m: Control = load(FIELD).new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	_host(px).add_child(m)
	m.setup([pc])
	await _settle()
	return m


## The field menu, Teleport its last row: in COLUMNS every row is inside the menu panel as built; in the WINDOW (where
## columns stop fitting) each row is inside the window and the panel when SELECTED, and the window is inside the panel.
func test_every_field_menu_row_is_inside_its_panel() -> void:
	var bad: Array = []
	var seen := 0
	var modes := {}
	for s in _presets():
		var m: Control = await _field_menu(s)
		modes[bool(m._menu_windowed)] = true
		var last_id := ""
		for i in m._menu_labels.size():
			var row: Control = m._menu_labels[i]
			var panel := _panel_of(row, m)
			seen += 1
			last_id = str(m._menu_options[i].get("id", "?"))
			if m._menu_windowed:
				m.selected_index = i
				m._update_selection()
				var wr: Rect2 = (m._menu_window as Control).get_global_rect()
				if _below(wr, panel.get_global_rect()) > SLACK:
					bad.append("@%s the field menu's window ends below its panel" % s)
				if _below(row.get_global_rect(), wr) > SLACK or _above(row.get_global_rect(), wr) > SLACK:
					bad.append("@%s field row '%s' selected is outside the window" % [s, last_id])
				continue
			var over := _below(row.get_global_rect(), panel.get_global_rect())
			var wide: float = row.get_global_rect().end.x - panel.get_global_rect().end.x
			if over > SLACK or wide > SLACK:
				bad.append("@%s field row '%s' ends %.0f px below / %.0f px right of its panel" % [s, last_id, over, wide])
		assert_eq(last_id, "teleport", "CONTROL @%s: Teleport is the field menu's last row" % s)
		for l in m.find_children("*", "Label", true, false):
			var t := str((l as Label).text)
			if t.begins_with("Play Time:") or t.begins_with("Location:") or t.begins_with("Corruption:"):
				var panel2 := _panel_of(l as Control, m)
				if _below(_text_rect(l as Label), panel2.get_global_rect()) > SLACK:
					bad.append("@%s '%s' runs below the menu panel" % [s, t.left(12)])
	assert_gt(seen, 100, "CONTROL: the census measured real rows (%d)" % seen)
	assert_true(modes.has(false), "CONTROL: at some Text Size every option is on screen at once (columns)")
	assert_eq(bad.size(), 0, "every field-menu row sits inside the menu panel:\n%s" % "\n".join(PackedStringArray(bad)))


## Columns only where they fit, the window only where they do not: the rule itself, on plain numbers.
func test_the_layout_rule() -> void:
	var W98 = load(FIELD)
	assert_eq(W98.menu_layout(5, 30.0, 200.0, 660.0, 500.0), {"windowed": false, "cols": 1, "per_col": 5}, "a short list is one column")
	assert_eq(W98.menu_layout(25, 30.0, 200.0, 660.0, 550.0), {"windowed": false, "cols": 2, "per_col": 13}, "25 rows that fit 18 high become two BALANCED columns")
	var tight: Dictionary = W98.menu_layout(25, 48.0, 260.0, 660.0, 500.0)
	assert_true(bool(tight["windowed"]), "three 260 px columns do not fit 660 px: the window takes over")
	assert_eq(int(tight["per_col"]), 10, "and shows the rows that fit the height")
	assert_false(bool(W98.menu_layout(25, 48.0, 200.0, 660.0, 500.0)["windowed"]), "CONTROL: the same rows at 200 px wide DO fit as three columns")


## Up/Down walk the ONE list in order at every Text Size, column break and window included; Left/Right are not rows.
func test_down_reaches_every_option_in_order() -> void:
	for s in _presets():
		var m: Control = await _field_menu(s)
		var n: int = m._menu_options.size()
		m.selected_index = 0
		m._update_selection()
		var walked: Array = [0]
		for k in n - 1:
			m._nav_step("ui_down")
			m._update_selection()
			walked.append(m.selected_index)
		assert_eq(walked, range(n), "@%s Down visits every option once, in order" % s)
		m._nav_step("ui_down")
		assert_eq(m.selected_index, 0, "@%s and wraps to the top" % s)
		var at: int = m.selected_index
		m._nav_step("ui_right")
		assert_eq(m.selected_index, at, "@%s Right is the party card, not a menu row" % s)


## The WINDOW, which no shipped Text Size reaches on a 1280x720 screen (three columns fit even at 2.0): forced here by a
## small screen, so the fallback is exercised rather than trusted. Each row selected is inside the window and the panel,
## and the markers say which way the hidden rows lie.
func test_where_columns_cannot_fit_a_window_follows_the_cursor() -> void:
	var m: Control = await _field_menu(2.0, Vector2i(800, 400))
	assert_true(m._menu_windowed, "CONTROL: an 800x400 screen at 200% cannot fit the columns")
	if not m._menu_windowed:
		return
	var n: int = m._menu_labels.size()
	assert_gt(n, m._menu_per_col, "CONTROL: more rows than the window shows")
	var panel := _panel_of(m._menu_labels[0], m)
	var bad: Array = []
	for i in n:
		m.selected_index = i
		m._update_selection()
		var wr: Rect2 = (m._menu_window as Control).get_global_rect()
		var rr: Rect2 = (m._menu_labels[i] as Control).get_global_rect()
		if _below(rr, wr) > SLACK or _above(rr, wr) > SLACK:
			bad.append("row %d selected is outside the window" % i)
		if _below(wr, panel.get_global_rect()) > SLACK:
			bad.append("the window ends below the panel")
		if i == 0 and (m._menu_more_up.visible or not m._menu_more_down.visible):
			bad.append("at the top only the down marker shows")
		if i == n - 1 and (not m._menu_more_up.visible or m._menu_more_down.visible):
			bad.append("at the bottom only the up marker shows")
	assert_eq(bad, [], "the window follows the cursor: %s" % [bad])
