extends GutTest

## "Restore the shipped autogrind profiles" was reachable only through the grind editor's Shift+D, a key no pad has.
## The console's OPTIONS ring now offers it as a row that opens the editor with that same prompt up, so a pad player
## reaches the question through the ring and answers it with Confirm or Back (cowir-controller's ruling, no new binding).
## Arms: CONTROL (the ring offers the row) · the row opens the editor with the prompt up · ring row + pad Confirm
## restores · ring row + pad Back restores nothing · after the editor closes the console holds the restored rules.

const AutogrindState := preload("res://test/unit/helpers/autogrind_state.gd")
const UI := "res://src/ui/autogrind/AutogrindUI.gd"
const PLANTED := "zz_planted_profile"

var _ag: Dictionary
var _vp: SubViewport
var _ui: Control


func before_each() -> void:
	_ag = AutogrindState.snapshot()
	AutogrindSystem._test_disable_persistence = true
	AutobattleSystem._test_disable_persistence = true
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	add_child_autofree(_vp)
	_ui = load(UI).new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vp.add_child(_ui)
	await get_tree().process_frame
	_ui._is_grinding = false
	var profiles: Array = AutogrindSystem.autogrind_profiles.get("profiles", [])
	var active: int = int(AutogrindSystem.autogrind_profiles.get("active", 0))
	if active < profiles.size():
		profiles[active]["name"] = PLANTED


func after_each() -> void:
	var ed = _ui._rules_editor_open if _ui and is_instance_valid(_ui) else null
	if ed and is_instance_valid(ed):
		ed.queue_free()
	if _ui and is_instance_valid(_ui):
		_ui.queue_free()
	AutogrindState.restore(_ag)


func _pad(button: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = true
	return e


func _ring_ids() -> Array:
	var out: Array = []
	for opt in (_ui._options_ring_spec().get("options", []) as Array):
		out.append(str(opt.get("id", "")))
	return out


## Commits the ring row and returns the editor it opened.
func _choose_row() -> Control:
	assert_eq(AutogrindSystem.get_active_autogrind_profile_name(), PLANTED, "CONTROL: the plant is what the system reads")
	_ui._commit_autogrind_option("restore_defaults")
	var ed: Control = _ui._rules_editor_open
	assert_not_null(ed, "PRECONDITION: the row opened the rules editor")
	return ed


func test_the_ring_offers_the_row() -> void:
	assert_has(_ring_ids(), "restore_defaults", "the options ring has no row to restore the shipped profiles, so a pad cannot reach it")


func test_the_row_opens_the_editor_with_the_prompt_up() -> void:
	var ed := _choose_row()
	if ed == null:
		return
	assert_not_null(ed._reset_confirm, "the editor opened without the restore prompt, so the row asks nothing")
	assert_eq(AutogrindSystem.get_active_autogrind_profile_name(), PLANTED, "and opening it restores nothing on its own")


func test_ring_row_then_pad_confirm_restores() -> void:
	var ed := _choose_row()
	if ed == null:
		return
	ed._input(_pad(JOY_BUTTON_B))
	assert_ne(AutogrindSystem.get_active_autogrind_profile_name(), PLANTED, "ring row + the pad's Confirm did not restore the shipped profiles")
	assert_null(ed._reset_confirm, "and the prompt closes")


func test_ring_row_then_pad_back_restores_nothing() -> void:
	var ed := _choose_row()
	if ed == null:
		return
	ed._input(_pad(JOY_BUTTON_A))
	assert_null(ed._reset_confirm, "the pad's Back did not close the prompt")
	assert_eq(AutogrindSystem.get_active_autogrind_profile_name(), PLANTED, "and Back must restore nothing")


func test_the_console_holds_the_restored_rules_after_the_editor_closes() -> void:
	var ed := _choose_row()
	if ed == null:
		return
	ed._input(_pad(JOY_BUTTON_B))
	ed.closed.emit()
	assert_null(_ui._rules_editor_open, "CONTROL: closing the editor hands control back to the console")
	assert_eq(_ui.rules, AutogrindSystem.get_autogrind_rules(), "the console kept its old rules after a restore")
