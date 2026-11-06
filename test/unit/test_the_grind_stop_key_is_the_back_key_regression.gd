extends GutTest

## Regression: the F1 reference's "Stop grinding and return" row said "X / Esc" while X has been the
## CONFIRM key since the 2026-09-29 emulator layout (Z = Back). A keyboard player told to press X to
## stop a grind pressed Confirm. The cell is now read off ui_cancel's InputMap keys; this guard reads
## InputMap itself, never AutogrindInputHelper, so it cannot merely agree with the helper.

const STOP_ROW := "Stop grinding and return"


func _keys_of(action: String) -> Array:
	var out: Array = []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey and (ev as InputEventKey).keycode != 0:
			out.append(OS.get_keycode_string((ev as InputEventKey).keycode))
	return out


func _stop_cell() -> String:
	for line in AutogrindInputHelper.grind_reference_rows().split("\n"):
		if line.contains(STOP_ROW):
			return line.substr(AutogrindInputHelper.REFERENCE_COL, AutogrindInputHelper.REFERENCE_COL).strip_edges()
	return ""


func _tokens(cell: String) -> Array:
	var out: Array = []
	for t in cell.split("/"):
		out.append(t.strip_edges())
	return out


func test_the_stop_row_names_every_back_key() -> void:
	var back := _keys_of("ui_cancel")
	assert_gt(back.size(), 0, "CONTROL: ui_cancel binds no keyboard key, so this arm proves nothing")
	var cell := _stop_cell()
	assert_ne(cell, "", "CONTROL: the F1 table has no '%s' row" % STOP_ROW)
	assert_eq(_tokens(cell), back,
		"the stop row's keyboard cell must be ui_cancel's keys %s, in order — it reads '%s'" % [back, cell])


func test_the_stop_row_never_names_the_confirm_key() -> void:
	var confirm := _keys_of("ui_accept")
	assert_gt(confirm.size(), 0, "CONTROL: ui_accept binds no keyboard key")
	var offenders: Array = []
	for t in _tokens(_stop_cell()):
		if confirm.has(t):
			offenders.append(t)
	assert_eq(offenders, [], "the stop row tells the player to press a CONFIRM key to stop: %s" % [offenders])


func test_the_fallback_letter_is_the_back_key() -> void:
	var back := _keys_of("ui_cancel")
	assert_gt(back.size(), 0, "CONTROL: ui_cancel binds no keyboard key")
	assert_eq(str(AutogrindInputHelper.ACTION_KEYS["exit"]), str(back[0]),
		"with no InputProfileManager the stop key falls back to ACTION_KEYS['exit'], which must be ui_cancel's first key")
