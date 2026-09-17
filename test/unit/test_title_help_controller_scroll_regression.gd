extends GutTest

## The Help overlay must accept D-pad scroll for the long content.
## Was: only ui_cancel intercepted; gamepad users had to fall back to mouse wheel.
##
## The overlay moved out of TitleScreen into HowToPlayOverlay so it could be reached
## in-game as well as from the title screen. This guard FOLLOWED it — the anchor changed,
## the behaviour it defends did not. Re-pointing rather than deleting is deliberate: the
## clamp below is itself a regression fix and would otherwise have been silently dropped.

const TITLE_PATH := "res://src/ui/HowToPlayOverlay.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_help_intercept_handles_ui_up_and_ui_down() -> void:
	var text := _read(TITLE_PATH)
	var idx := text.find("# Help overlay intercept")
	assert_gt(idx, -1, "help overlay intercept comment must exist (anchor)")
	var window := text.substr(idx, 800)
	# The raw read OR the latched reader — the INTERCEPT is the fact, not its spelling. Converted
	# 2026-09-17: the stick's Y axis carries no echo flag, so one push scrolled five steps.
	for dir in ["ui_down", "ui_up"]:
		var raw: bool = window.contains('is_action_pressed("%s")' % dir)
		var latched: bool = window.contains('nav == "%s"' % dir) and text.contains("MenuNav.step(")
		assert_true(raw or latched,
			"help overlay must intercept %s to scroll the content" % dir)
	# …and whichever spelling it uses, one push must equal one press — that is behavioural and
	# lives in test_the_help_overlay_scrolls_once_per_push, not here.
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
