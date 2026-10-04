extends GutTest

## Regression (cowir-main label sweep, 2026-10-04): the Controls screen's footer said "Keyboard: Z Confirm · X Back" while .555
## had bound Confirm to X and Back to Z, so the one screen a player opens to learn their keys taught them backwards. It also ran
## 14px past its 768-wide panel. The keys are now read from the live InputMap and the line is clipped to the panel.

const ControlsMenuScript := preload("res://src/ui/ControlsMenu.gd")

var _saved: Dictionary = {}


func before_each() -> void:
	for a in ["ui_accept", "ui_cancel"]:
		_saved[a] = InputMap.action_get_events(a).duplicate()


func after_each() -> void:
	for a in _saved:
		InputMap.action_erase_events(a)
		for e in _saved[a]:
			InputMap.action_add_event(a, e)


func _key(code: Key) -> InputEventKey:
	var k := InputEventKey.new()
	k.keycode = code
	return k


func _menu() -> Control:
	var m: Control = ControlsMenuScript.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(m)
	return m


func test_the_footer_names_the_keys_bound_today() -> void:
	var m := _menu()
	await get_tree().process_frame
	var text: String = m._footer_text()
	var accept := InputProfileManager.first_key_label("ui_accept", "?")
	var cancel := InputProfileManager.first_key_label("ui_cancel", "?")
	assert_string_contains(text, "%s Confirm" % accept, "the footer names the key bound to Confirm")
	assert_string_contains(text, "%s Back" % cancel, "the footer names the key bound to Back")
	assert_false(text.contains("Z Confirm") and accept != "Z", "the stale pre-.555 'Z Confirm' must not survive")


func test_the_footer_follows_a_rebind() -> void:
	InputMap.action_erase_events("ui_accept")
	InputMap.action_add_event("ui_accept", _key(KEY_K))
	InputMap.action_erase_events("ui_cancel")
	InputMap.action_add_event("ui_cancel", _key(KEY_J))
	var m := _menu()
	await get_tree().process_frame
	var text: String = m._footer_text()
	assert_string_contains(text, "K Confirm", "derived, not frozen: a rebind to K shows K")
	assert_string_contains(text, "J Back", "derived, not frozen: a rebind to J shows J")


func test_the_footer_stays_inside_its_panel() -> void:
	var m := _menu()
	await get_tree().process_frame
	await get_tree().process_frame
	var footer: Label = m._footer_label
	assert_not_null(footer, "CONTROL: the menu builds its footer")
	var panel := footer.get_parent() as Control
	assert_gt(panel.size.x, 0.0, "SCOPE: the panel has a width to measure against")
	assert_lte(footer.position.x + footer.size.x, panel.size.x + 0.5,
		"the footer must end inside its panel (spans %.0f..%.0f of %.0f)" % [footer.position.x, footer.position.x + footer.size.x, panel.size.x])
