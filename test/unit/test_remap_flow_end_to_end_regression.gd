extends GutTest

## End-to-end coverage for the remap flow, which produced TWO real defects on 2026-09-09 and had
## no test walking it: a rebind that never reached the InputMap, and a reloaded rebind rendering
## "?" because JSON yields floats and FACE_GLYPHS is int-keyed.
##
## AUDITED THE REST OF THE FLOW AND IT IS A NEGATIVE — conflict display refreshes (
## _update_all_labels calls _update_conflict_display), reset-to-preset is reachable
## (ControlsMenu:846) and profile cycling is reachable (:797/:803). Nothing else was broken. This
## pins the walk so the next change to it cannot quietly break a step nobody tests.

const CONFIG := "user://input/controls.json"

var _saved_profile: String = ""
var _saved_custom: Dictionary = {}
var _saved_config: String = ""
var _had_config: bool = false


## set_custom_binding calls save_config(), which writes user://. Deploy suites run UNSANDBOXED, so
## snapshot the real file and restore it. My own throwaway probes leaked a rebind into this file on
## 2026-09-09 and three later suites went red looking like a code defect.
func before_each() -> void:
	_saved_profile = InputProfileManager.active_profile
	_saved_custom = InputProfileManager.custom_bindings.duplicate(true)
	_had_config = FileAccess.file_exists(CONFIG)
	_saved_config = FileAccess.get_file_as_string(CONFIG) if _had_config else ""


func after_each() -> void:
	InputProfileManager.custom_bindings = _saved_custom.duplicate(true)
	InputProfileManager.active_profile = _saved_profile
	InputProfileManager.apply_profile(_saved_profile)
	if _had_config:
		DirAccess.make_dir_recursive_absolute("user://input")
		var f := FileAccess.open(CONFIG, FileAccess.WRITE)
		if f:
			f.store_string(_saved_config)
			f.close()
	elif FileAccess.file_exists(CONFIG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIG))


func _buttons(action: String) -> Array:
	var out := []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton:
			out.append(ev.button_index)
	return out


## THE WALK: rebind, land in the engine, survive a reload, still render a glyph.
func test_a_rebind_lands_persists_and_renders() -> void:
	InputProfileManager.apply_profile("Standard")
	assert_false(_buttons("ui_accept").has(3), "PRECONDITION: ui_accept is not already on 3")

	InputProfileManager.set_custom_binding("ui_accept", [3])
	assert_true(_buttons("ui_accept").has(3), "step 1: the rebind must reach the InputMap")
	assert_eq(InputProfileManager.active_profile, "Custom", "step 2: and switch to the Custom slot")

	InputProfileManager.save_config()
	InputProfileManager.custom_bindings = {}
	InputProfileManager.active_profile = "Standard"
	InputProfileManager.load_config()
	InputProfileManager.apply_profile("Custom")
	assert_true(_buttons("ui_accept").has(3), "step 3: and survive a save/load round trip")
	assert_ne(InputProfileManager.glyph_for_action("ui_accept", "Xbox 360 Controller"), "?",
		"step 4: and still render a real glyph — a float index renders '?' everywhere")


## Rebinding two actions onto one button must be REPORTED, not silently accepted.
func test_a_conflict_is_detected() -> void:
	InputProfileManager.apply_profile("Standard")
	assert_eq(InputProfileManager.detect_conflicts().size(), 0,
		"PRECONDITION: a stock profile has no conflicts, else the arm below proves nothing")
	InputProfileManager.set_custom_binding("ui_accept", [3])
	InputProfileManager.set_custom_binding("ui_cancel", [3])
	var conflicts: Array = InputProfileManager.detect_conflicts()
	assert_gt(conflicts.size(), 0, "two actions on one button must surface as a conflict")


## Reset must restore the stock table AND reach the engine, not just the dictionary.
func test_reset_restores_the_preset_and_applies_it() -> void:
	InputProfileManager.apply_profile("Standard")
	var stock := _buttons("ui_accept")
	InputProfileManager.set_custom_binding("ui_accept", [3])
	assert_ne(_buttons("ui_accept"), stock, "PRECONDITION: the rebind changed the live map")
	InputProfileManager.reset_custom_to_preset()
	assert_eq(_buttons("ui_accept"), stock,
		"reset must put the stock binding back into the InputMap, not only into custom_bindings")
	assert_eq(InputProfileManager.detect_conflicts().size(), 0, "and clear any conflict with it")


## CONTROL: the flow must be walking a real corpus — if REMAPPABLE_ACTIONS were empty every arm
## above would pass vacuously.
func test_there_are_remappable_actions_to_walk() -> void:
	assert_gt((InputProfileManager.REMAPPABLE_ACTIONS as Array).size(), 3,
		"the remap screen must offer several actions, else this whole file is vacuous")
	assert_true((InputProfileManager.REMAPPABLE_ACTIONS as Array).has("ui_accept"),
		"and ui_accept specifically, which every arm above rebinds")
