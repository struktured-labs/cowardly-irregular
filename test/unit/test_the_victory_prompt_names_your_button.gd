extends GutTest

## The prompt after EVERY battle read "A: finish · A: continue". `ui_accept` advances it, and this
## game deliberately puts Confirm on the EAST face — so "A" is correct on a Switch pad, wrong on
## Xbox (Ⓑ) and PlayStation (○), and names a button a keyboard player does not have at all.
##
## ⚠️ Why no existing guard caught it: the fleet's censuses match `\b[ABXY]:[A-Za-z]` — a letter
## IMMEDIATELY after the colon. "A: finish" has a space, and that one character walked it past every
## caption sweep in the repo, including the two in my own lane.

const OVERLAY := "res://src/battle/VictoryOverlay.gd"
const LOOP := "res://src/GameLoop.gd"

func _src(p: String) -> String:
	var raw := FileAccess.get_file_as_string(p)
	assert_gt(raw.length(), 500, "CONTROL: read %s" % p)
	return raw

func test_the_prompt_does_not_freeze_a_face_letter() -> void:
	## Both spacings, because the space is exactly what hid this one.
	var src := _src(OVERLAY)
	var re := RegEx.new()
	re.compile("\"[^\"]*\\b[ABXY] ?: ?[A-Za-z][^\"]*\"")
	var found: Array = []
	for m in re.search_all(src):
		found.append(m.get_string())
	assert_eq(found.size(), 0, "the victory prompt names a fixed face button: " + str(found))

func test_it_derives_from_the_action_that_actually_advances_it() -> void:
	## Arms-reach: the expectation is parsed out of GameLoop's wait loop, not written down here. If
	## someone re-binds the victory confirm, this reds instead of quietly describing the old button.
	var loop := _src(LOOP)
	var i: int = loop.find("func _wait_for_confirm_victory")
	assert_gt(i, -1, "CONTROL: located the victory wait loop")
	var j: int = loop.find("\nfunc ", i + 10)
	var body: String = loop.substr(i, (j - i) if j > -1 else 900)
	var act_re := RegEx.new()
	act_re.compile("is_action_just_pressed\\(\"([a-z_]+)\"\\)")
	var m := act_re.search(body)
	assert_not_null(m, "CONTROL: the wait loop tests an action at all")
	if m == null:
		return
	var action: String = m.get_string(1)
	assert_eq(action, "ui_accept", "CONTROL: victory advances on ui_accept")
	assert_true(_src(OVERLAY).contains("hint_for_action(\"%s\")" % action),
		"the prompt must derive from %s — the action that advances it" % action)

func test_confirm_really_is_on_the_east_face_so_A_was_family_specific() -> void:
	## The premise, measured. If Confirm is ever moved to the south face, "A" becomes correct on
	## Xbox and wrong on Nintendo — and this reds so the claim above gets rewritten rather than
	## silently inverting.
	var events: Array = InputMap.action_get_events("ui_accept")
	var indices: Array = []
	for e in events:
		if e is InputEventJoypadButton:
			indices.append((e as InputEventJoypadButton).button_index)
	assert_gt(indices.size(), 0, "CONTROL: ui_accept has a pad binding")
	assert_true(indices.has(JOY_BUTTON_B),
		"Confirm is expected on the EAST face (JOY_BUTTON_B); got %s" % str(indices))

func test_a_keyboard_player_is_given_a_key_they_have() -> void:
	## hint_for_action falls back to the keyboard key with no pad — that is why it is the right
	## helper here, and why face_glyph_for_index would NOT be: it returns an xbox glyph for an
	## unknown device, which is how a keyboard player gets shown a button they do not own.
	var src := _src(OVERLAY)
	assert_false(src.contains("face_glyph_for_index"),
		"the glyph helpers hand an xbox glyph to a keyboard player; this prompt has no pad branch")
	var ipm: Node = Engine.get_main_loop().root.get_node_or_null("InputProfileManager")
	if ipm == null:
		pending("InputProfileManager required")
		return
	if not Input.get_connected_joypads().is_empty():
		pending("a pad is connected; the no-pad path cannot be measured here")
		return
	var hint: String = ipm.hint_for_action("ui_accept")
	assert_ne(hint, "", "with no pad the hint must name a KEY, not render empty")
	assert_false(hint in ["A", "B", "X", "Y"],
		"with no pad the prompt must not render a face letter, got '%s'" % hint)
