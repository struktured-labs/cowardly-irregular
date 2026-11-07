extends GutTest

## ZOOM (struktured 2026-11-07, design 23190): in the field Abilities menu one button (west face / keyboard A, the
## `ability_zoom` action) blows the highlighted description up to the whole content area, AbilityZoom.FACTOR larger on
## top of Text Size and capped where it still fits. Up/Down still step while zoomed; Back un-zooms and never closes;
## Confirm casts nothing. The same button or Back returns to the exact prior layout.
## Fit is judged on the BUILT label's own line count against its panel, never on a size the code computed.

const MENU := preload("res://src/ui/AbilitiesMenu.gd")
const CombatantScript := preload("res://src/battle/Combatant.gd")

var _saved := 1.0


func before_each() -> void:
	_saved = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.set_text_size_scale(_saved)


func _presets() -> Array:
	var p: Array = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must hold more than one step, or the preset loop proves nothing")
	return p


## A mage (spells with real descriptions), the cursor on the LONGEST description, so the fit arm judges the worst case.
func _menu(s: float = 1.0, job: String = "mage") -> Control:
	GameState.set_text_size_scale(s)
	var pc = CombatantScript.new()
	pc.combatant_name = "Mira"
	pc.job = JobSystem.get_job(job)
	add_child_autofree(pc)
	var m: Control = MENU.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(m)
	m.setup(pc)
	var longest := 0
	for i in m._abilities_list.size():
		if str(m._abilities_list[i]["data"].get("description", "")).length() > str(m._abilities_list[longest]["data"].get("description", "")).length():
			longest = i
	m.selected_index = longest
	m._build_ui()
	await get_tree().process_frame
	return m


func _ev(action: String) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	return ev


func _act(m: Control, action: String) -> void:
	m._input(_ev(action))
	await get_tree().process_frame


func _live(m: Control, node_name: String) -> Control:
	for c in m.get_children():
		if c.name == node_name and not c.is_queued_for_deletion():
			return c
	return null


## The live details panel's description label.
func _desc(m: Control) -> Label:
	for l in m.find_children("Description", "Label", true, false):
		if not l.is_queued_for_deletion():
			return l as Label
	return null


## Every live Control's path, rect and text: the "exact layout" a round trip must restore.
func _snapshot(m: Control) -> Array:
	var out: Array = []
	for c in m.find_children("*", "Control", true, false):
		var cc := c as Control
		if cc.is_queued_for_deletion():
			continue
		out.append([str(m.get_path_to(cc)).get_slice("@", 0), cc.get_global_rect(), (cc as Label).text if cc is Label else ""])
	return out


func test_the_floor_names_every_member_this_file_drives() -> void:
	var m: Control = await _menu()
	for f in ["_set_zoom", "_fit_zoom", "_back", "_has_selection", "_build_ui"]:
		assert_true(m.has_method(f), "AbilitiesMenu.%s must exist" % f)
	assert_true("_zoomed" in m, "AbilitiesMenu._zoomed must exist")
	assert_gt(m._abilities_list.size(), 1, "PRECONDITION: the mage has abilities to read")
	assert_true(InputMap.has_action(AbilityZoom.ACTION), "the ability_zoom action exists")
	var west := InputEventJoypadButton.new()
	west.button_index = JOY_BUTTON_X
	west.pressed = true
	var key_a := InputEventKey.new()
	key_a.keycode = KEY_A
	key_a.pressed = true
	assert_true(west.is_action(AbilityZoom.ACTION), "the WEST face is bound to it")
	assert_true(key_a.is_action(AbilityZoom.ACTION), "and keyboard A")


func test_zoom_grows_the_description_and_it_still_fits() -> void:
	for s in _presets():
		var m: Control = await _menu(s)
		var before: int = _desc(m).get_theme_font_size("font_size")
		await _act(m, AbilityZoom.ACTION)
		assert_true(m._zoomed, "CONTROL @%s: the zoom press took" % s)
		var panel := _live(m, "ZoomedDetails")
		assert_not_null(panel, "@%s the zoomed panel is built" % s)
		var d := _desc(m)
		var px: int = d.get_theme_font_size("font_size")
		assert_gt(px, before, "@%s the zoomed description is larger (%d -> %d)" % [s, before, px])
		var lines: int = d.get_line_count()
		var bottom: float = d.position.y + lines * d.get_theme_font("font").get_height(px)
		assert_gt(lines, 0, "CONTROL @%s: the built label has lines" % s)
		assert_lte(bottom, panel.size.y, "@%s the zoomed description (%d lines, ends %.0f) fits its panel (%.0f)" % [s, lines, bottom, panel.size.y])
		assert_lte(d.position.x + d.size.x, panel.size.x, "@%s and stays inside its width" % s)


## A description far longer than any shipped one, so the cap has to bind: the zoom shrinks back until it fits.
func test_a_description_too_long_for_full_zoom_is_capped_to_fit() -> void:
	var long_text := " ".join(PackedStringArray(range(160).map(func(i): return "word%d" % i)))
	for s in _presets():
		var m: Control = await _menu(s)
		var row: Dictionary = m._abilities_list[m.selected_index]
		row["data"] = (row["data"] as Dictionary).duplicate()
		row["data"]["description"] = long_text
		m._build_ui()
		await get_tree().process_frame
		var before: int = _desc(m).get_theme_font_size("font_size")
		await _act(m, AbilityZoom.ACTION)
		var panel := _live(m, "ZoomedDetails")
		var d := _desc(m)
		var px: int = d.get_theme_font_size("font_size")
		var bottom: float = d.position.y + d.get_line_count() * d.get_theme_font("font").get_height(px)
		assert_gte(px, before, "@%s the capped zoom never shrinks below the unzoomed text" % s)
		assert_lte(bottom, panel.size.y, "@%s the long description (%d lines at %d px, ends %.0f) fits its panel (%.0f)" % [s, d.get_line_count(), px, bottom, panel.size.y])


func test_the_toggle_restores_the_exact_layout() -> void:
	var m: Control = await _menu(1.25)
	var before := _snapshot(m)
	await _act(m, AbilityZoom.ACTION)
	assert_ne(_snapshot(m), before, "CONTROL: zoomed is a different layout")
	await _act(m, AbilityZoom.ACTION)
	assert_false(m._zoomed, "the same button un-zooms")
	assert_eq(_snapshot(m), before, "and the layout is exactly what it was")


func test_back_unzooms_and_never_closes() -> void:
	var m: Control = await _menu()
	var closes := [0]
	m.closed.connect(func(): closes[0] += 1)
	await _act(m, AbilityZoom.ACTION)
	await _act(m, "ui_cancel")
	assert_false(m._zoomed, "Back un-zooms")
	assert_eq(closes[0], 0, "and does not close the menu")
	m._input(_ev("ui_cancel"))
	assert_eq(closes[0], 1, "CONTROL: unzoomed, Back closes the menu")


func test_confirm_casts_nothing_while_zoomed_and_up_down_still_step() -> void:
	var m: Control = await _menu(1.0, "cleric")
	var cure := -1
	for i in m._abilities_list.size():
		if FieldCast.castable(m._abilities_list[i]["data"]):
			cure = i
	assert_gt(cure, -1, "CONTROL: the cleric has a field-castable spell, so Confirm WOULD cast")
	m.selected_index = cure
	m._build_ui()
	await get_tree().process_frame
	var mp: int = m.character.current_mp
	await _act(m, AbilityZoom.ACTION)
	await _act(m, "ui_accept")
	assert_true(m._zoomed and not m._picking, "Confirm while zoomed opens no target picker")
	assert_eq(m.character.current_mp, mp, "and spends no MP")
	var at: int = m.selected_index
	await _act(m, "ui_down")
	assert_eq(m.selected_index, (at + 1) % m._abilities_list.size(), "Down steps to the next ability")
	assert_true(m._zoomed, "and stays zoomed")


func test_the_footer_names_the_zoom_button_as_derived() -> void:
	var m: Control = await _menu()
	var hint := AbilityZoom.hint()
	assert_ne(hint, "", "CONTROL: the action has a hint to show")
	var footer: Label = _live(m, "Footer") as Label
	assert_true(footer.text.contains("%s: Zoom" % hint), "the footer offers Zoom on its derived button: %s" % footer.text)
	await _act(m, AbilityZoom.ACTION)
	footer = _live(m, "Footer") as Label
	assert_true(footer.text.contains(hint), "zoomed, it names the same button to go back: %s" % footer.text)
