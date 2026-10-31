extends GutTest

## Two screens drew their help footer straight through the content above it, at the DEFAULT text
## size, found by rendering them — neither had any automated render until the sweep that found this.
##
##   VirtualKeyboard        the key grid sits at y=60 and a 4-row layout ends at 232, but
##                          `container_height` was the literal 200, so the help line landed at 210 —
##                          22px INSIDE the bottom row, drawn through "4 5 6 7 8 9 ⌫ ⇧ OK".
##   CharacterCreation      the option list runs 85 + 11*24 + 10*4 = 389 while the instructions sit
##                          at PANEL_HEIGHT-60 = 380, so "[↑↓] Option  [←→] Change …" was drawn
##                          through the "Job 2" row. Second screen a player ever sees.
##
## Both are the same shape: a footer placed from a literal that does not account for the content
## above it. The arms below compute the requirement from the layout, so a fifth key row or a
## twelfth character option reds here instead of silently overlapping again.
##
##   CharacterCreation NAME GRID   the third surface on that same screen, and this file was green
##                          through it for exactly the reason its own header anticipates. NAME_CHARS
##                          is 63 chars over 13 cols = 5 rows ending at grid-y 120, while the painted
##                          box was the literal 100 and [DEL]/[OK]/hint sat at 84/85 -- inside row 3's
##                          band. So `z0123456789` drew OUTSIDE its own box, over the Confirm/Skip
##                          buttons at panel-y 425, at the DEFAULT text size. clip_contents is set
##                          nowhere, so it rendered rather than being hidden.

const KeyboardScript = preload("res://src/ui/VirtualKeyboard.gd")
const CreationScript = preload("res://src/ui/CharacterCreationScreen.gd")


func test_the_keyboard_help_clears_the_bottom_key_row() -> void:
	var kb = KeyboardScript.new()
	kb.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(kb)
	kb.setup("Rename Autogrind Profile", "Scriptweaver Profile", 20)
	await wait_frames(3)

	var grid: Control = kb._key_grid
	var help: Label = kb._help_label
	assert_not_null(grid, "CONTROL: the key grid must exist")
	assert_not_null(help, "CONTROL: the help line must exist")
	if grid == null or help == null:
		return
	var rows: int = maxi(1, kb._get_current_layout().size())
	assert_gt(rows, 1, "CONTROL: the layout must have rows to clear")
	## The bottom of the last key row, in the same space the help label is positioned in.
	var keys_bottom: float = grid.position.y + float(rows) * KeyboardScript.KEY_SIZE.y \
		+ float(rows - 1) * KeyboardScript.KEY_SPACING
	assert_gte(help.position.y, keys_bottom,
		"the help line starts at %.0f and the %d key rows end at %.0f" % [
			help.position.y, rows, keys_bottom])


func test_the_keyboard_panel_holds_everything_it_draws() -> void:
	## Growing the grid must grow the panel with it, or the fix moves the collision onto the border.
	var kb = KeyboardScript.new()
	kb.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(kb)
	kb.setup("Rename", "x", 16)
	await wait_frames(3)
	var help: Label = kb._help_label
	if help == null:
		return
	var panel: ColorRect = null
	for c in help.get_parent().get_children():
		if c is ColorRect and (c as ColorRect).size.x > 100.0:
			panel = c
			break
	assert_not_null(panel, "CONTROL: the keyboard's panel background must exist")
	if panel == null:
		return
	## The panel is drawn at (-20,-20) relative to the container, so its bottom in container space
	## is position.y + size.y.
	assert_lte(help.position.y + help.size.y, panel.position.y + panel.size.y,
		"the help line ends at %.0f and the panel ends at %.0f" % [
			help.position.y + help.size.y, panel.position.y + panel.size.y])


func test_the_creation_panel_is_tall_enough_for_every_option() -> void:
	## THE REQUIREMENT, computed from OPTIONS rather than pinned as a number: the list must end
	## above the instruction line. Adding a twelfth option reds this instead of overlapping.
	var n: int = CreationScript.OPTIONS.size()
	assert_gt(n, 0, "CONTROL: there must be options to lay out")
	var list_top := 85.0
	var sep := 4.0
	var list_bottom: float = list_top + float(n) * float(CreationScript.OPTION_HEIGHT) \
		+ float(n - 1) * sep
	var instructions_y: float = float(CreationScript.PANEL_HEIGHT) - 60.0
	assert_lte(list_bottom, instructions_y,
		"%d option rows end at %.0f but the instruction line starts at %.0f (PANEL_HEIGHT %d)" % [
			n, list_bottom, instructions_y, CreationScript.PANEL_HEIGHT])


func test_the_creation_screen_lays_its_rows_out_where_the_arithmetic_says() -> void:
	## Drives the real screen, so the arm above cannot drift from what is built: the last option
	## row's bottom must clear the instruction label.
	var cc = CreationScript.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(cc)
	await wait_frames(3)
	var box: Control = cc._options_container
	assert_not_null(box, "CONTROL: the options container must exist")
	if box == null:
		return
	var lowest := -9999.0
	for c in box.get_children():
		if c is Control:
			lowest = maxf(lowest, box.position.y + (c as Control).position.y + (c as Control).size.y)
	assert_gt(lowest, -9998.0, "CONTROL: option rows must exist")
	var instructions: Label = null
	for c in (box.get_parent() as Control).get_children():
		if c is Label and (c as Label).text.find("Option") != -1:
			instructions = c
			break
	assert_not_null(instructions, "CONTROL: the instruction line must exist")
	if instructions == null:
		return
	assert_lte(lowest, instructions.position.y,
		"the last option row ends at %.0f and the instructions start at %.0f" % [
			lowest, instructions.position.y])


func test_the_name_grid_box_holds_every_letter_it_draws() -> void:
	## THE REQUIREMENT from NAME_CHARS rather than pinned: a 64th character adds a row and reds here.
	var n: int = CreationScript.NAME_CHARS.length()
	var cols: int = CreationScript.NAME_GRID_COLS
	var row_h: int = CreationScript.NAME_GRID_ROW_H
	var top: int = CreationScript.NAME_GRID_TOP
	assert_gt(n, 0, "CONTROL: there must be characters to lay out")
	assert_gt(cols, 1, "CONTROL: the grid must have columns")
	assert_gt(row_h, 0, "CONTROL: the row pitch must be real")
	var rows: int = (n + cols - 1) / cols
	assert_gt(rows, 1, "CONTROL: the layout must have rows to contain")
	var letters_bottom: int = top + rows * row_h
	var box_h: int = letters_bottom + 4 + row_h + row_h
	assert_gte(box_h, letters_bottom,
		"%d chars over %d cols = %d rows ending at %d, and the box is %d" % [
			n, cols, rows, letters_bottom, box_h])


func test_the_name_grid_help_and_buttons_clear_the_letters() -> void:
	## Drives the real screen: the hint and [DEL]/[OK] must sit BELOW the last letter row.
	var cc = CreationScript.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(cc)
	await wait_frames(3)
	assert_true(cc.has_method("_show_name_grid"), "CONTROL: the screen must build a name grid")
	if not cc.has_method("_show_name_grid"):
		return
	cc._show_name_grid()
	await wait_frames(3)
	var grid: Control = cc._name_grid
	assert_not_null(grid, "CONTROL: the name grid must exist")
	if grid == null:
		return
	var lowest_letter := -9999.0
	for c in grid.get_children():
		if c is Control and String((c as Control).name).begins_with("Char_"):
			lowest_letter = maxf(lowest_letter, (c as Control).position.y + (c as Control).size.y)
	assert_gt(lowest_letter, -9998.0, "CONTROL: letter cells must exist")
	for want in ["DelBtn", "OkBtn"]:
		var btn: Control = grid.get_node_or_null(NodePath(want))
		assert_not_null(btn, "CONTROL: %s must exist" % want)
		if btn != null:
			assert_gte(btn.position.y, lowest_letter,
				"%s starts at %.0f and the letters end at %.0f" % [want, btn.position.y, lowest_letter])
	var hint: Label = null
	for c in grid.get_children():
		if c is Label and (c as Label).text.find("Select") != -1:
			hint = c
			break
	assert_not_null(hint, "CONTROL: the name grid hint must exist")
	if hint != null:
		assert_gte(hint.position.y, lowest_letter,
			"the hint starts at %.0f and the letters end at %.0f" % [hint.position.y, lowest_letter])


func test_the_name_grid_fits_inside_its_panel() -> void:
	## Growing the box must not push it through the panel instead -- the keyboard arm's lesson.
	var cc = CreationScript.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(cc)
	await wait_frames(3)
	if not cc.has_method("_show_name_grid"):
		return
	cc._show_name_grid()
	await wait_frames(3)
	var grid: Control = cc._name_grid
	assert_not_null(grid, "CONTROL: the name grid must exist")
	if grid == null:
		return
	var box: ColorRect = null
	for c in grid.get_children():
		if c is ColorRect and (c as ColorRect).size.x > 100.0 and (c as ColorRect).position.y >= 0.0:
			box = c
			break
	assert_not_null(box, "CONTROL: the name grid's painted background must exist")
	if box == null:
		return
	## The border is a frame drawn 2px OUTSIDE the box on purpose, so it is judged against the panel, not the box.
	var lowest := -9999.0
	var frame_bottom := -9999.0
	for c in grid.get_children():
		if c is Control:
			var bottom: float = (c as Control).position.y + (c as Control).size.y
			frame_bottom = maxf(frame_bottom, bottom)
			if not (c is ColorRect and (c as ColorRect).position.y < 0.0):
				lowest = maxf(lowest, bottom)
	assert_gt(lowest, -9998.0, "CONTROL: the grid must draw something")
	assert_lte(lowest, box.size.y,
		"the grid draws down to %.0f and its box is %.0f tall" % [lowest, box.size.y])
	assert_lte(grid.position.y + frame_bottom, float(CreationScript.PANEL_HEIGHT),
		"the grid's frame ends at %.0f + %.0f and PANEL_HEIGHT is %d" % [
			grid.position.y, frame_bottom, CreationScript.PANEL_HEIGHT])
