extends GutTest

## Regression (2026-07-09): BYOKConfigPanel had NO initial focus and no
## focus-neighbor wiring — controller/keyboard users opened it and the D-pad
## did nothing (mouse-only, violating the controller-first rule). Pins the
## initial focus grab and the full neighbor chain so a refactor that drops
## _wire_focus_chain() fails loudly.

const PanelScript := preload("res://src/ui/BYOKConfigPanel.gd")


func _make_panel():
	var p = PanelScript.new()
	add_child_autofree(p)
	return p


func _resolves(from: Control, path: NodePath, expected: Control) -> bool:
	return path != NodePath("") and from.get_node_or_null(path) == expected


func test_initial_focus_lands_on_first_field() -> void:
	var p = _make_panel()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(get_viewport().gui_get_focus_owner(), p._base_url_field,
		"opening the panel must focus the Base URL field — gamepad users need a starting point")


func test_vertical_spine_is_wired_with_wrap() -> void:
	var p = _make_panel()
	assert_true(_resolves(p._base_url_field, p._base_url_field.focus_neighbor_bottom, p._format_picker),
		"base_url ↓ format")
	assert_true(_resolves(p._format_picker, p._format_picker.focus_neighbor_bottom, p._model_field),
		"format ↓ model")
	assert_true(_resolves(p._model_field, p._model_field.focus_neighbor_bottom, p._api_key_field),
		"model ↓ api_key")
	assert_true(_resolves(p._api_key_field, p._api_key_field.focus_neighbor_bottom, p._test_btn),
		"api_key ↓ test")
	assert_true(_resolves(p._base_url_field, p._base_url_field.focus_neighbor_top, p._save_btn),
		"base_url ↑ wraps to save")
	assert_true(_resolves(p._cancel_btn, p._cancel_btn.focus_neighbor_bottom, p._base_url_field),
		"cancel ↓ wraps to base_url")


func test_button_row_is_wired_horizontally() -> void:
	var p = _make_panel()
	assert_true(_resolves(p._test_btn, p._test_btn.focus_neighbor_right, p._save_btn), "test → save")
	assert_true(_resolves(p._save_btn, p._save_btn.focus_neighbor_right, p._cancel_btn), "save → cancel")
	assert_true(_resolves(p._cancel_btn, p._cancel_btn.focus_neighbor_left, p._save_btn), "cancel ← save")
	assert_true(_resolves(p._save_btn, p._save_btn.focus_neighbor_top, p._api_key_field), "save ↑ api_key")


func test_all_interactive_controls_accept_focus() -> void:
	var p = _make_panel()
	for c in [p._base_url_field, p._format_picker, p._model_field, p._api_key_field, p._test_btn, p._save_btn, p._cancel_btn]:
		assert_eq(c.focus_mode, Control.FOCUS_ALL,
			"%s must accept keyboard+gamepad focus" % c.get_class())
