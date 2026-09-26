extends GutTest

## Settings → Controls draws a Keyboard column and a Mouse column beside each action.
## Those columns looked up REMAPPABLE_ACTIONS with `index - 1`, which was right when the
## only row above the actions was the profile selector. Nintendo Mode and How to Play
## sit above them now (ROW_ACTION_FIRST is 3), so every row showed the key and mouse
## binding of the action two slots down, and Toggle Auto and Menu drew no columns at all.
## The gamepad column on the same row was already correct — it is filled from the loop
## variable — so the screen disagreed with itself.


const ControlsMenuScript = preload("res://src/ui/ControlsMenu.gd")


func _make_menu() -> ControlsMenu:
	var menu = ControlsMenuScript.new()
	menu.size = Vector2(1280, 720)
	add_child_autofree(menu)
	return menu


## Labels on an action row that are neither the action name, the dot leader, nor the
## gamepad value. Creation order is keyboard, then mouse.
func _binding_column_texts(menu: ControlsMenu, action: String) -> Array:
	var value_label: Label = menu._action_labels[action]
	var title: String = str(InputProfileManager.ACTION_LABELS.get(action, action))
	var out: Array = []
	for child in value_label.get_parent().get_children():
		if not (child is Label) or child == value_label:
			continue
		var text := str(child.text)
		if text == title:
			continue
		if text != "" and text.replace(".", "") == "":
			continue
		out.append(text)
	return out


func test_keyboard_and_mouse_columns_name_that_rows_action() -> void:
	var menu := _make_menu()
	var seen := {}
	for action in InputProfileManager.REMAPPABLE_ACTIONS:
		var key_label: String = InputProfileManager.get_action_key_label(action)
		seen[key_label] = true
		var cols: Array = _binding_column_texts(menu, action)
		assert_eq(cols.size(), 2,
			"%s must show a keyboard column and a mouse column, got %s" % [action, str(cols)])
		if cols.size() < 2:
			continue
		assert_eq(cols[0], key_label,
			"%s keyboard column must be that action's keys, not a neighbour's" % action)
		assert_eq(cols[1], InputProfileManager.get_action_mouse_label(action),
			"%s mouse column must be that action's mouse binding" % action)
	assert_gt(seen.size(), 1,
		"CONTROL: every remappable action shares one key label, so a shifted column would still match")
