extends GutTest

## Regression: live playtest 2026-07-18 (intercom 2802) — struktured
## "I don't know how to scroll party chats when they exceed about eight
## options — there's a scroll bar but with my gamepad I can't manipulate it."
##
## PartyChatMenu's ScrollContainer didn't follow the D-pad selection.
## When _selection moved past the visible window, the highlight rendered
## off-screen; the only way to scroll was the mouse-only scrollbar.
## Controller-first rule: if a scrollbar needs a mouse, it's broken.
##
## Fix: _ensure_selection_visible() calls ScrollContainer.ensure_control_visible
## on the current selection's row, invoked at the end of every _highlight()
## call so both D-pad, mouse-wheel, and mouse-hover selection changes track.


const PARTY_CHAT_MENU := "res://src/ui/PartyChatMenu.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_menu_stores_scroll_container_reference() -> void:
	# Prior state: scroll was a local var inside _build_panel. Without a
	# field reference _highlight() can't reach it to call
	# ensure_control_visible.
	var src := _read(PARTY_CHAT_MENU)
	assert_gt(src.find("var _scroll: ScrollContainer"), -1,
		"PartyChatMenu must expose _scroll as a field so _highlight can call ensure_control_visible")


func test_ensure_selection_visible_helper_exists() -> void:
	var src := _read(PARTY_CHAT_MENU)
	assert_gt(src.find("func _ensure_selection_visible("), -1,
		"PartyChatMenu must have a _ensure_selection_visible helper")
	# And it must call ensure_control_visible.
	var fn := src.find("func _ensure_selection_visible(")
	var body := src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	assert_gt(body.find("ensure_control_visible"), -1,
		"helper must call ScrollContainer.ensure_control_visible on the selected row")


func test_highlight_invokes_ensure_selection_visible() -> void:
	# Wire pin: _highlight() must call _ensure_selection_visible at the end,
	# not just define the helper as orphan code. All three selection-change
	# paths (D-pad up/down, mouse wheel, mouse hover) route through
	# _highlight, so pinning the wire here covers all three.
	var src := _read(PARTY_CHAT_MENU)
	var fn := src.find("func _highlight(")
	assert_gt(fn, -1, "_highlight must exist")
	var body := src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	assert_gt(body.find("_ensure_selection_visible"), -1,
		"_highlight must invoke _ensure_selection_visible — otherwise the scroll follow helper is orphan code and gamepad users can't reach items 9+")


func test_helper_guards_on_null_scroll_and_invalid_selection() -> void:
	# Test contexts often instantiate a partial UI; the helper must handle
	# null _scroll and out-of-range _selection cleanly rather than crash.
	var src := _read(PARTY_CHAT_MENU)
	var fn := src.find("func _ensure_selection_visible(")
	var body := src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	assert_gt(body.find("_scroll == null") + body.find("is_instance_valid(_scroll)"), -1,
		"helper must guard on null / invalid _scroll")
	assert_gt(body.find("_selection < 0") + body.find("_selection >= _row_nodes.size()"), -1,
		"helper must guard on out-of-range _selection")
