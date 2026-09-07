extends GutTest

## Live-playtest find 2026-07-03: the session autosaved to slot 98 every
## few minutes, but the Load screen never listed slot 98 — players
## couldn't load the autosave by hand (Continue DOES scan it; see
## test_autosave_slot_isolation_regression for that pin). The UI half
## of autosave was write-only.


func test_save_screen_lists_the_autosave_slot() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/ui/SaveScreen.gd")
	assert_true(src.contains("_create_slot_panel(SaveSystem.AUTO_SAVE_SLOT"),
		"the Load screen must show slot 98 — a save the UI can't display is write-only")


func test_save_mode_refuses_the_autosave_slot() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/ui/SaveScreen.gd")
	var sel: int = src.find("if current_mode == Mode.SAVE:")
	var window: String = src.substr(sel, 400)
	assert_true(window.contains("slot == SaveSystem.AUTO_SAVE_SLOT"),
		"manual saves must not overwrite the system-managed autosave slot")


func test_slot_label_names_all_three_kinds() -> void:
	var screen = load("res://src/ui/SaveScreen.gd").new()
	autofree(screen)
	assert_eq(screen._slot_label(0), "Slot 1")
	assert_eq(screen._slot_label(SaveSystem.AUTO_SAVE_SLOT), "Autosave")
	assert_eq(screen._slot_label(SaveSystem.QUICK_SAVE_SLOT), "Quick Save")
