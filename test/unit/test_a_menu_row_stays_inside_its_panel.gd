extends GutTest

## struktured playing .792 (2026-11-12): "Teleport btw doesnt quite fit in the border of the settings screen it bleeds
## toward bottom". Teleport lives in three places: the field menu's LAST row (25 rows, no scroll), Settings' debug row,
## and the Teleport list itself. No guard compared a row with the PANEL it sits in: the Text Size arms compare rows with
## each other and labels with their own row. This is that arm, as a CENSUS first: every built row of the three screens,
## at every Text Size step, measured on the built nodes in a 1280x720 viewport. A scrolling list is judged with each row
## SELECTED (the list follows the cursor); a list with no scroll is judged as it stands.

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


func _host() -> CanvasLayer:
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
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
	var layer := _host()
	var s: Control = load(SETTINGS).new()
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(s)
	var t: Control = load(TELEPORT).new()
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(t)
	var f: Control = load(FIELD).new()
	f.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(f)
	await _settle()
	assert_true("_settings_items" in s and "_scroll" in s and "selected_index" in s and "_footer" in s and s.has_method("_update_selection"), "SettingsMenu's rows, scroll, cursor and footer must exist")
	assert_true("_row_refs" in t and "_scroll" in t and "_selected" in t and t.has_method("_update_selection"), "TeleportMenu's rows, scroll and cursor must exist")
	assert_true("_menu_labels" in f and f.has_method("setup"), "OverworldMenu's rows must exist")
	assert_true("debug_log_enabled" in GameState and "text_size_scale" in GameState, "GameState carries both settings")


## The field menu does not scroll: every row, Teleport last, must sit inside the menu panel as built.
func test_every_field_menu_row_is_inside_its_panel() -> void:
	var bad: Array = []
	var seen := 0
	for s in _presets():
		GameState.text_size_scale = s
		var pc = CombatantScript.new()
		pc.combatant_name = "Bram"
		add_child_autofree(pc)
		var m: Control = load(FIELD).new()
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		_host().add_child(m)
		m.setup([pc])
		await _settle()
		var last_id := ""
		for i in m._menu_labels.size():
			var row: Control = m._menu_labels[i]
			var panel := _panel_of(row, m)
			seen += 1
			last_id = str(m._menu_options[i].get("id", "?"))
			var over := _below(row.get_global_rect(), panel.get_global_rect())
			if over > SLACK:
				bad.append("@%s field row '%s' ends %.0f px below its panel (row bottom %.0f, panel bottom %.0f)" % [s, last_id, over, row.get_global_rect().end.y, panel.get_global_rect().end.y])
		assert_eq(last_id, "teleport", "CONTROL @%s: Teleport is the field menu's last row" % s)
	assert_gt(seen, 100, "CONTROL: the census measured real rows (%d)" % seen)
	assert_eq(bad.size(), 0, "every field-menu row sits inside the menu panel:\n%s" % "\n".join(PackedStringArray(bad)))


## Settings scrolls: with each row SELECTED it must be wholly inside the scroll window, its text inside the row, and
## the window and footer inside the panel. Debug rows on, so Debug Teleport and its subtitle are in the census.
func test_every_settings_row_is_inside_the_panel_when_selected() -> void:
	GameState.debug_log_enabled = true
	var bad: Array = []
	var seen := 0
	for s in _presets():
		GameState.text_size_scale = s
		var m: Control = load(SETTINGS).new()
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		_host().add_child(m)
		await _settle()
		var scroll: ScrollContainer = m._scroll
		var panel: Control = scroll.get_parent()
		if _below(scroll.get_global_rect(), panel.get_global_rect()) > SLACK:
			bad.append("@%s the Settings scroll window ends below its panel" % s)
		if _below(_text_rect(m._footer), panel.get_global_rect()) > SLACK:
			bad.append("@%s the Settings footer ends below its panel" % s)
		var ids: Array = []
		for i in m._settings_items.size():
			var row: Control = m._settings_items[i].get("control")
			if row == null:
				continue
			var id := str(m._settings_items[i].get("id", m._settings_items[i].get("action", i)))
			ids.append(id)
			m.selected_index = i
			m._update_selection()
			await get_tree().process_frame
			seen += 1
			var rr := row.get_global_rect()
			var sr := scroll.get_global_rect()
			if _below(rr, sr) > SLACK or _above(rr, sr) > SLACK:
				bad.append("@%s Settings row '%s' selected: %.0f below / %.0f above the scroll window" % [s, id, _below(rr, sr), _above(rr, sr)])
			for l in row.find_children("*", "Label", true, false):
				var over := _below(_text_rect(l as Label), rr)
				if over > SLACK:
					bad.append("@%s Settings row '%s': '%s' runs %.0f px below its row" % [s, id, (l as Label).text.left(28), over])
		assert_true(ids.any(func(x): return str(x).contains("teleport")), "CONTROL @%s: the Debug Teleport row is in the census: %s" % [s, ids])
	assert_gt(seen, 60, "CONTROL: the census measured real rows (%d)" % seen)
	assert_eq(bad.size(), 0, "every Settings row sits inside the panel:\n%s" % "\n".join(PackedStringArray(bad)))


## The Teleport list scrolls: with each destination SELECTED its row is inside the scroll window, and the window and the
## header lines are inside the panel.
func test_every_teleport_row_is_inside_the_panel_when_selected() -> void:
	var bad: Array = []
	var seen := 0
	for s in _presets():
		GameState.text_size_scale = s
		var m: Control = load(TELEPORT).new()
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		_host().add_child(m)
		await _settle()
		var scroll: ScrollContainer = m._scroll
		var panel: Control = scroll.get_parent()
		var pr := panel.get_global_rect()
		if _below(scroll.get_global_rect(), pr) > SLACK:
			bad.append("@%s the Teleport scroll window ends %.0f px below its panel" % [s, _below(scroll.get_global_rect(), pr)])
		for l in panel.get_children():
			if l is Label and (l as Label).global_position.x + (l as Label).get_minimum_size().x > pr.end.x + SLACK:
				bad.append("@%s Teleport header '%s' runs %.0f px past the panel's right edge" % [s, (l as Label).text.left(24), (l as Label).global_position.x + (l as Label).get_minimum_size().x - pr.end.x])
		for i in m._row_refs.size():
			m._selected = i
			m._update_selection()
			await get_tree().process_frame
			seen += 1
			var rr: Rect2 = (m._row_refs[i] as Control).get_global_rect()
			var sr := scroll.get_global_rect()
			if _below(rr, sr) > SLACK or _above(rr, sr) > SLACK:
				bad.append("@%s Teleport row %d selected: %.0f below / %.0f above the scroll window" % [s, i, _below(rr, sr), _above(rr, sr)])
	assert_gt(seen, 100, "CONTROL: the census measured real rows (%d)" % seen)
	assert_eq(bad.size(), 0, "every Teleport row sits inside the panel:\n%s" % "\n".join(PackedStringArray(bad)))
