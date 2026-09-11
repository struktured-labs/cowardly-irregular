extends GutTest

## The choice menu's hint row ("[A/Enter/Click] Confirm    [B/Esc/RClick] Cancel") and the
## key-item popup's "Press A / Z to continue" were the last two literal button caps on the
## cutscene lane's surfaces — the class tasks 1-2 fixed on the skip prompt and the dialogue
## advance hint. On a Nintendo-family pad (8BitDo) confirm fires from the cap printed Ⓑ, so both
## named a button that does the other thing. Both now resolve the physical cap through
## InputProfileManager each time they are shown.

const XBOX := "Xbox Wireless Controller"
const NINTENDO := "8BitDo SN30 Pro"


## Literal expectations per convention — never derived from the functions under test.
func _confirm_caps() -> Dictionary:
	if InputProfileManager.nintendo_mode:
		return {XBOX: "Ⓑ", NINTENDO: "Ⓐ"}
	return {XBOX: "Ⓐ", NINTENDO: "Ⓑ"}


func _cancel_caps() -> Dictionary:
	if InputProfileManager.nintendo_mode:
		return {XBOX: "Ⓐ", NINTENDO: "Ⓑ"}
	return {XBOX: "Ⓑ", NINTENDO: "Ⓐ"}


func test_choice_menu_hint_names_the_physical_caps_per_pad_family() -> void:
	var ok := _confirm_caps()
	var no := _cancel_caps()
	for pad in [XBOX, NINTENDO]:
		assert_eq(DialogueChoiceMenu.hint_text(true, pad),
			"[%s/Enter/Click] Confirm    [%s/Esc/RClick] Cancel    (↑↓/D-pad)" % [ok[pad], no[pad]], pad)
		assert_eq(DialogueChoiceMenu.hint_text(false, pad),
			"[%s/Enter/Click] Confirm    (↑↓/D-pad)" % ok[pad], "%s, story choice" % pad)
	assert_ne(ok[XBOX], ok[NINTENDO], "control: the two families print different confirm caps")


func test_key_item_hint_names_the_physical_cap_per_pad_family() -> void:
	var ok := _confirm_caps()
	assert_eq(KeyItemPopup.continue_hint_text(XBOX), "Press %s / Z to continue" % ok[XBOX])
	assert_eq(KeyItemPopup.continue_hint_text(NINTENDO), "Press %s / Z to continue" % ok[NINTENDO])


func test_choice_menu_builds_its_hint_from_the_helper() -> void:
	var menu := DialogueChoiceMenu.new()
	add_child_autofree(menu)
	var runner := func() -> void:
		await menu.present(["Tell me more.", "Farewell."])
	runner.call()
	await get_tree().process_frame
	assert_not_null(menu._hint_label, "control: present() builds the hint row")
	if menu._hint_label:
		assert_eq(menu._hint_label.text, DialogueChoiceMenu.hint_text(true),
			"_build_ui must build the hint from hint_text, not a literal")
	menu.dismiss()
	await get_tree().process_frame
	await get_tree().process_frame


func test_key_item_popup_builds_its_hint_from_the_helper() -> void:
	var host := Node.new()
	add_child_autofree(host)
	var popup := KeyItemPopup.show_item(host, {"name": "Crimson Shard", "description": "A shard of the Elder Flame."})
	assert_not_null(popup._hint, "control: _present builds the hint label")
	if popup._hint:
		assert_eq(popup._hint.text, KeyItemPopup.continue_hint_text(),
			"_present must build the hint from continue_hint_text, not a literal")


func test_no_literal_cap_survives_in_either_surface() -> void:
	var menu_src := FileAccess.get_file_as_string("res://src/llm/DialogueChoiceMenu.gd")
	var popup_src := FileAccess.get_file_as_string("res://src/ui/KeyItemPopup.gd")
	assert_false(menu_src.is_empty() or popup_src.is_empty(), "control: both sources readable")
	assert_eq(menu_src.find("\"[A/"), -1, "DialogueChoiceMenu: literal '[A/' hint came back")
	assert_eq(menu_src.find("[B/Esc"), -1, "DialogueChoiceMenu: literal '[B/Esc' hint came back")
	assert_eq(popup_src.find("\"Press A /"), -1, "KeyItemPopup: literal 'Press A /' hint came back")
