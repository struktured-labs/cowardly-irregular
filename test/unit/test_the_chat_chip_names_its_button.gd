extends GutTest

## The field's "💬 Party Chat (n)" chip told a player chats were waiting and never which button opens them: tick 470
## dropped a frozen "[L]" (wrong per pad family) and put nothing in its place, leaving a click, and this game requires
## no mouse. The chip now names the button DERIVED for the device (L / LB / L1 on a pad, the key with none), grows its
## panel to the text, and follows Text Size (its font was a fixed 16 px on a fixed 190 px panel).

const CHIP := "res://src/ui/PartyChatIndicator.gd"
const NINTENDO := "8BitDo SN30 Pro"
const XBOX := "Xbox Wireless Controller"
const PLAYSTATION := "DualSense Wireless Controller"

var _saved_text = null


func before_each() -> void:
	_saved_text = GameState.text_size_scale if "text_size_scale" in GameState else null


func after_each() -> void:
	if _saved_text != null:
		GameState.text_size_scale = _saved_text


func _chip() -> Control:
	var c: Control = load(CHIP).new()
	add_child_autofree(c)
	return c


func _presets() -> Array:
	var p: Array = (load("res://src/ui/SettingsMenu.gd") as GDScript).get_script_constant_map().get("TEXT_SIZE_PRESETS", [])
	assert_gt(p.size(), 1, "FLOOR: SettingsMenu.TEXT_SIZE_PRESETS must hold more than one step, or the preset loop proves nothing")
	return p


## The pad button party_chat is bound to, read off InputMap by the test itself.
func _chat_pad_index() -> int:
	for ev in InputMap.action_get_events("party_chat"):
		if ev is InputEventJoypadButton:
			return (ev as InputEventJoypadButton).button_index
	return -1


func test_the_floor_names_every_member_this_file_drives() -> void:
	var c := _chip()
	for m in ["text_for", "chat_button", "show_count", "_fit", "_on_joy_connection_changed"]:
		assert_true(c.has_method(m), "PartyChatIndicator.%s must exist" % m)
	for m in ["button_name_for_index", "hint_for_action"]:
		assert_true(InputProfileManager.has_method(m), "InputProfileManager.%s must exist" % m)


func test_with_no_pad_the_chip_names_the_key() -> void:
	if not Input.get_connected_joypads().is_empty():
		pass_test("a pad is visible to this run, so the no-pad path is not exercisable here")
		return
	var key: String = InputProfileManager.hint_for_action("party_chat")
	assert_ne(key, "", "CONTROL: party_chat has a keyboard key")
	var c := _chip()
	c.show_count(3)
	assert_string_contains(c._label.text, key, "with no pad the chip names the key that opens the chat")
	assert_string_contains(c._label.text, "(3)", "and still counts the chats")


func test_each_pad_family_reads_its_own_name_for_the_button() -> void:
	var idx := _chat_pad_index()
	assert_gt(idx, -1, "CONTROL: party_chat is bound to a pad button")
	var names: Array = []
	for dev in [NINTENDO, XBOX, PLAYSTATION]:
		var want: String = InputProfileManager.button_name_for_index(idx, dev)
		assert_ne(want, "", "CONTROL: %s names button %d" % [dev, idx])
		assert_eq(_chat_button_for(dev), want, "on %s the chip names the pad's own button" % dev)
		assert_string_contains(load(CHIP).text_for(2, dev), want, "and the chip's text carries it (%s)" % dev)
		names.append(want)
	assert_eq(names.size(), 3)
	assert_ne(names[0], names[1], "CONTROL: the families name it differently, so one shared letter could not pass")
	assert_ne(names[1], names[2], "CONTROL: Xbox and PlayStation differ too")


func _chat_button_for(dev: String) -> String:
	return load(CHIP).chat_button(dev)


## The three Text Size arms (CLAUDE.md): the font GROWS at every preset, the grown text FITS its built panel, and the
## chip stays on screen. A fit judged against a fixed panel is what the old 190 px box would fail at the large presets.
func test_the_chip_grows_with_the_text_and_still_fits() -> void:
	var sizes: Array = []
	for scale in _presets():
		GameState.text_size_scale = scale
		var c := _chip()
		c.show_count(12)
		await get_tree().process_frame
		var px: int = c._label.get_theme_font_size("font_size")
		sizes.append(px)
		var panel: Vector2 = c._panel.size
		var text_w: float = c._label.get_combined_minimum_size().x
		assert_lte(text_w, panel.x - 2.0, "at Text Size %s the text (%.0f px) fits its panel (%.0f px)" % [scale, text_w, panel.x])
		assert_lte(c._label.get_combined_minimum_size().y, panel.y, "and its height fits too (%s)" % scale)
		var vp: Vector2 = c.get_viewport_rect().size
		assert_true(Rect2(Vector2.ZERO, vp).encloses(c.get_global_rect()), "and the chip stays on screen at %s: %s" % [scale, c.get_global_rect()])
	for i in range(1, sizes.size()):
		assert_gt(sizes[i], sizes[i - 1], "the chip's font must grow at every Text Size step: %s" % [sizes])


func test_a_pad_plugged_in_refreshes_the_chip() -> void:
	var c := _chip()
	assert_true(Input.joy_connection_changed.is_connected(c._on_joy_connection_changed),
		"the chip re-reads its button when a pad is connected or pulled out")


## A Text Size change made in Settings reaches the chip it did not rebuild. Settings is opened through the overworld
## menu, which HIDES the field HUD, so the change lands on a hidden chip: this arm hides it first, as play does.
func test_a_live_text_size_change_reaches_the_hidden_chip() -> void:
	GameState.set_text_size_scale(1.0)
	var c := _chip()
	c.show_count(3)
	await get_tree().process_frame
	var before: Vector2 = c._panel.size
	var px_before: int = c._label.get_theme_font_size("font_size")
	c.visible = false
	GameState.set_text_size_scale(2.0)
	await get_tree().process_frame
	assert_true(GameState.text_size_scale_changed.is_connected(c._on_text_size_changed), "CONTROL: the chip listens for the change")
	var px_after: int = c._label.get_theme_font_size("font_size")
	assert_eq(px_after, TextScale.scaled(c.BASE_FONT_SIZE), "the hidden chip's font follows the new scale (%d -> %d)" % [px_before, px_after])
	assert_gt(px_after, px_before, "and it actually grew")
	assert_lte(c._label.get_combined_minimum_size().x, c._panel.size.x - 2.0, "the grown text still fits its re-fitted panel")
	assert_gt(c._panel.size.x, before.x, "so the panel grew with it (%s -> %s)" % [before, c._panel.size])
	GameState.set_text_size_scale(1.0)
