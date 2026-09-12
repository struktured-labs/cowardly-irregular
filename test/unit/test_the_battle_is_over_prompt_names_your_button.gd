extends GutTest

## "Z / A / Click to continue..." was wrong twice for most players.
##
## `ui_accept` is button INDEX 1 — the EAST face. "A" is that face only on a Nintendo pad; an Xbox
## player was told to press Ⓐ when the button that continues is Ⓑ, and a PlayStation player ✕ when
## it is ○. Same inversion cowir-controller found in AbilitiesMenu the same day, in a different file.
## And "Click" was never true at all: _process_post_battle gates on ui_accept alone, so the mouse
## did nothing — a third of the advertised ways to continue did not exist.
##
## Measured with no pad: hint_for_action("ui_accept") -> "Z", which is what the line already said
## for keyboard. So the keyboard player loses nothing and everyone else stops being misdirected.

const BS := "res://src/battle/BattleScene.gd"


func test_the_token_is_the_keyboard_key_when_no_pad_is_connected() -> void:
	## Behavioural, on the real helper. The keyboard case is the one the old literal got RIGHT, so
	## it is the one a careless fix would regress.
	if not Input.get_connected_joypads().is_empty():
		pending("a pad is connected in this harness; the no-pad arm cannot be measured")
		return
	var scene = load(BS).new()
	autofree(scene)
	assert_eq(scene._accept_token(), "Z",
		"with no pad the prompt must name the keyboard key that actually continues")


func test_the_token_is_derived_rather_than_a_frozen_face_name() -> void:
	## The discriminator: the helper must go through hint_for_action, because that is what varies
	## per family. A helper that returned "Z" by hardcoding it would pass the arm above.
	var src: String = FileAccess.get_file_as_string(BS)
	assert_gt(src.length(), 1000, "CONTROL: read BattleScene")
	var idx: int = src.find("func _accept_token")
	assert_gt(idx, -1, "the helper must exist")
	var body: String = src.substr(idx, src.find("\nfunc ", idx + 1) - idx)
	assert_true(body.contains("hint_for_action(\"ui_accept\")"),
		"the token must be derived from the action, not written out per family")


func test_ui_accept_really_is_the_east_face_so_A_was_wrong() -> void:
	## The premise, measured rather than quoted. If ui_accept were index 0 the old caption would
	## have been right on Xbox and this whole file would be defending nothing.
	var ipm = Engine.get_main_loop().root.get_node_or_null("InputProfileManager")
	if ipm == null:
		pending("InputProfileManager autoload required")
		return
	var events: Array = InputMap.action_get_events("ui_accept")
	var indices: Array = []
	for e in events:
		if e is InputEventJoypadButton:
			indices.append(int((e as InputEventJoypadButton).button_index))
	assert_true(indices.has(JOY_BUTTON_B), "ui_accept must sit on the EAST face (index 1): %s" % str(indices))
	assert_false(indices.has(JOY_BUTTON_A),
		"if it were also on the SOUTH face the old 'A' would have worked and this fix would be noise")


func test_the_prompts_no_longer_promise_a_frozen_button_or_a_mouse() -> void:
	## Both call sites, and the mouse. _process_post_battle gates on ui_accept alone, so "Click"
	## advertised an input the scene does not read.
	var src: String = FileAccess.get_file_as_string(BS)
	for phrase in ["to continue...", "to restart..."]:
		var i: int = src.find(phrase)
		assert_gt(i, -1, "the %s prompt must still exist" % phrase)
		## ⚠️ First version ended the window at the phrase, so it cut off the `% _accept_token()`
		## that FOLLOWS it — the derived-token assert redded on correct code and the "Click" assert
		## was vacuous in the same window. Take the whole line.
		var line_start: int = src.rfind("\n", i) + 1
		var line_end: int = src.find("\n", i)
		var line: String = src.substr(line_start, line_end - line_start)
		assert_true(line.contains("_accept_token()"),
			"'%s' must name the derived button: %s" % [phrase, line.strip_edges()])
		assert_false(line.contains("Click"),
			"clicking does nothing here — _process_post_battle reads ui_accept only: %s" % line.strip_edges())


func test_the_trusted_turn_prompt_names_the_button_that_claims_it() -> void:
	## Same inversion, different file, found by applying cowir-controller's corrected question to my
	## own lane rather than assuming it was clean. The trust window is claimed with ui_cancel —
	## button index 0, the SOUTH face — and the line said "press B", which is that face only on a
	## Nintendo pad. An Xbox player was told B when the button that takes the turn back is Ⓐ.
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	var events: Array = InputMap.action_get_events("ui_cancel")
	var indices: Array = []
	for e in events:
		if e is InputEventJoypadButton:
			indices.append(int((e as InputEventJoypadButton).button_index))
	assert_true(indices.has(JOY_BUTTON_A),
		"CONTROL: the claim action really is the SOUTH face, so 'B' really was wrong: %s" % str(indices))
	if Input.get_connected_joypads().is_empty():
		assert_eq(bm._trust_interrupt_token(), "X",
			"with no pad it must name the key that actually claims the turn")
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var i: int = src.find("Trusted — press")
	assert_gt(i, -1, "the trusted-turn prompt must still exist")
	var line: String = src.substr(src.rfind("\n", i) + 1, src.find("\n", i) - src.rfind("\n", i) - 1)
	assert_true(line.contains("_trust_interrupt_token()"),
		"the prompt must name the derived button: %s" % line.strip_edges())
