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
