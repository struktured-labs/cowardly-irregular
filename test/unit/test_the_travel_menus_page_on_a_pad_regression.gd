extends GutTest

## TeleportMenu's fast scroll was `ui_page_up` / `ui_page_down`. Those are Godot BUILT-IN actions
## with a keyboard-only default, and project.godot declares neither — so the menu paged 8 rows on
## PageUp and a controller had no fast scroll at all. FastTravelMenu had none on either input.
##
## Both now go through MenuPaging, which carries PageUp/PageDown AND L1/R1 (battle_defer /
## battle_advance). The destination list grows all game in both menus, which is what makes the
## missing half worth fixing rather than documenting.
##
## The arms drive the real menus with real events. MenuPaging's own dispatch is covered by its
## suite; what is checked here is that these two menus are wired to it and move by a page.

const TeleportScript = preload("res://src/ui/TeleportMenu.gd")
const FastTravelScript = preload("res://src/ui/FastTravelMenu.gd")


func _pad(button: int) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	ev.pressed = true
	return ev


func _key(code: int) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	return ev


## The defect itself: the shoulder buttons must be a page jump, not nothing.
func test_a_shoulder_pages_the_teleport_list() -> void:
	var menu = TeleportScript.new()
	add_child_autofree(menu)
	assert_gt(TeleportScript.DESTINATIONS.size(), MenuPaging.PAGE_ROWS,
		"the list must be longer than one page or this menu cannot demonstrate paging")

	menu._selected = 0
	assert_ne(MenuPaging.page_delta(_pad(JOY_BUTTON_RIGHT_SHOULDER)), 0,
		"the right shoulder must read as a page input")
	menu._input(_pad(JOY_BUTTON_RIGHT_SHOULDER))
	assert_eq(menu._selected, MenuPaging.PAGE_ROWS,
		"a shoulder press must move a whole page, not one row and not zero")


func test_the_keyboard_page_keys_still_work_on_the_teleport_list() -> void:
	var menu = TeleportScript.new()
	add_child_autofree(menu)
	menu._selected = 0
	menu._input(_key(KEY_PAGEDOWN))
	assert_eq(menu._selected, MenuPaging.PAGE_ROWS,
		"PageDown kept its page jump; the fix adds a pad binding, it does not remove the keys")


func test_paging_up_from_the_top_matches_this_menu_s_own_wrap() -> void:
	var menu = TeleportScript.new()
	add_child_autofree(menu)
	var n: int = TeleportScript.DESTINATIONS.size()
	menu._selected = 0
	menu._input(_pad(JOY_BUTTON_LEFT_SHOULDER))
	assert_eq(menu._selected, ((0 - MenuPaging.PAGE_ROWS) % n + n) % n,
		"a page jump wraps exactly as this menu's single-step move already wraps")


## A control that reports a page and is never wired to the menu is the bug in a new costume.
func test_a_shoulder_pages_the_fast_travel_list() -> void:
	var menu = FastTravelScript.new()
	add_child_autofree(menu)
	menu._rows = []
	for i in range(25):
		menu._rows.append({"id": "crystal_%d" % i, "name": "Crystal %d" % i, "cost": 0})
	menu._selected = 0
	menu._input(_pad(JOY_BUTTON_RIGHT_SHOULDER))
	assert_eq(menu._selected, MenuPaging.PAGE_ROWS,
		"the fast travel list must page on a shoulder like every other long menu")


func test_an_empty_fast_travel_list_does_not_move_or_crash() -> void:
	var menu = FastTravelScript.new()
	add_child_autofree(menu)
	menu._rows = []
	menu._selected = 0
	menu._input(_pad(JOY_BUTTON_RIGHT_SHOULDER))
	assert_eq(menu._selected, 0, "an empty list has nowhere to page to")


## Both footers must NAME the control, derived per pad. A binding nobody is told about is
## the same invisibility as one that does not exist — this menu's original defect.
func test_both_footers_advertise_the_page_control() -> void:
	for path in ["res://src/ui/TeleportMenu.gd", "res://src/ui/FastTravelMenu.gd"]:
		var src := FileAccess.get_file_as_string(path)
		assert_ne(src, "", "%s must be readable" % path)
		assert_true(src.contains("to page"), "%s must tell the player a page jump exists" % path)
		assert_true(src.contains('hint_for_action("battle_defer")')
			and src.contains('hint_for_action("battle_advance")'),
			"%s must DERIVE both page tokens per pad, never freeze a letter" % path)

## ⛔ HERMETIC ABOUT THE PROFILE. This file asks InputProfileManager for a name or glyph, so it
## inherits whatever `user://input/controls.json` holds; a remap test writes a "Custom" profile there
## and an interrupted run skips its cleanup. Two suites red that way on 2026-09-17 in one sandbox.
var _saved_profile: String = ""


func before_all() -> void:
	_saved_profile = InputProfileManager.active_profile
	InputProfileManager.apply_profile("Standard")


func after_all() -> void:
	if _saved_profile != "":
		InputProfileManager.apply_profile(_saved_profile)
