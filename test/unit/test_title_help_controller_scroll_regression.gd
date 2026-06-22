extends GutTest

## TitleScreen Help overlay must accept D-pad scroll for the long content.
## Was: only ui_cancel intercepted; gamepad users had to fall back to mouse wheel.

const TITLE_PATH := "res://src/ui/TitleScreen.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_help_intercept_handles_ui_up_and_ui_down() -> void:
	var text := _read(TITLE_PATH)
	var idx := text.find("# Help overlay intercept")
	assert_gt(idx, -1, "help overlay intercept comment must exist (anchor)")
	var window := text.substr(idx, 800)
	assert_true(window.contains("is_action_pressed(\"ui_down\")"),
		"help overlay must intercept ui_down to scroll the content")
	assert_true(window.contains("is_action_pressed(\"ui_up\")"),
		"help overlay must intercept ui_up to scroll the content")
	assert_true(window.contains("_scroll_help("),
		"help overlay scrolling must route through _scroll_help so behavior is centralized")


func test_scroll_helper_drives_the_richtextlabel_scroll_bar() -> void:
	var text := _read(TITLE_PATH)
	var idx := text.find("func _scroll_help")
	assert_gt(idx, -1, "_scroll_help helper must be defined")
	var body := text.substr(idx, 400)
	assert_true(body.contains("get_v_scroll_bar()"),
		"_scroll_help must drive the RichTextLabel's vertical scroll bar")
	assert_true(body.contains("clampf("),
		"_scroll_help must clamp scroll value within [min, max - page]")
