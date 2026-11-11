extends GutTest

## struktured's .788 playtest, pad connected: the battle zoom chip read "A: Zoom", the KEYBOARD key, and on his pad zoom is
## the west face. glyph_for_action / button_name_for_action answered only for actions in the controller PROFILE table
## (the eight remappable ones), so every other action (ability_zoom, dash) had no pad answer and every hint fell to the
## keyboard. The pad answer now falls back to the action's live InputMap binding. The corpus is DERIVED: every action in
## project.godot with a pad BUTTON bound, so a new action cannot be left out.

const PADS := {"xbox": "Xbox Wireless Controller", "playstation": "DualSense Wireless Controller", "nintendo": "Nintendo Switch Pro Controller"}


func _project_actions() -> Array:
	var src := FileAccess.get_file_as_string("res://project.godot")
	var start := src.find("[input]")
	var stop := src.find("\n[", start + 1)
	var body := src.substr(start, (stop - start) if stop > start else -1)
	var out: Array = []
	for m in RegEx.create_from_string("(?m)^([A-Za-z_][A-Za-z0-9_]*)=\\{").search_all(body):
		out.append(m.get_string(1))
	return out


func _button_bound(action: String) -> Array:
	return InputProfileManager.get_current_button_indices(action)


func test_every_action_with_a_pad_button_names_it_on_every_pad() -> void:
	var checked := 0
	var bad: Array = []
	for a in _project_actions():
		var idx: Array = _button_bound(a).filter(func(i): return i < JOY_BUTTON_DPAD_UP)
		if idx.is_empty():
			continue   # no pad button, or only d-pad directions, which legends name as "D-Pad" by design
		checked += 1
		for fam in PADS:
			var i: int = int(idx[0])
			var want: String = InputProfileManager.face_glyph_for_index(i, PADS[fam]) if i <= JOY_BUTTON_Y else InputProfileManager.button_name_for_index(i, PADS[fam])
			var hint: String = InputProfileManager.hint_for_action(a, PADS[fam])
			if hint != want:
				bad.append("%s on %s reads '%s', its pad button %d prints '%s'" % [a, fam, hint, i, want])
	assert_gt(checked, 8, "CONTROL: project.godot binds pad buttons to more than the profile's eight actions")
	assert_eq(bad, [], "every pad-bound action names the button it is bound to: %s" % [bad])


## The two the playtest hit, named exactly: zoom and run both sit on the west face, the same button Repeat names.
func test_zoom_names_the_west_face_like_repeat_does() -> void:
	for fam in PADS:
		var west: String = InputProfileManager.face_glyph_for_index(JOY_BUTTON_X, PADS[fam])
		assert_ne(west, "?", "CONTROL: %s has a west-face glyph (what Repeat's hint prints)" % fam)
		assert_eq(InputProfileManager.hint_for_action(String(AbilityZoom.ACTION), PADS[fam]), west, "%s: Zoom names the west face" % fam)
		assert_eq(InputProfileManager.hint_for_action("dash", PADS[fam]), west, "%s: Run names the west face" % fam)


## CONTROL: a profile action still goes through its profile row and the face convention, unchanged by the fallback.
func test_a_profile_action_still_reads_its_profile() -> void:
	var b: Dictionary = InputProfileManager.get_profile_bindings(InputProfileManager.active_profile)
	assert_true(b.has("ui_accept"), "PRECONDITION: ui_accept is a profile action")
	var want: Array = InputProfileManager.face_convention_indices("ui_accept", b["ui_accept"])
	assert_eq(InputProfileManager.glyph_for_action("ui_accept", PADS["xbox"]),
		InputProfileManager.face_glyph_for_index(int(want[0]), PADS["xbox"]), "Confirm's glyph comes from its profile row")
