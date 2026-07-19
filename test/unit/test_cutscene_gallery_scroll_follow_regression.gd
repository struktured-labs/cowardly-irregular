extends GutTest

## Regression: same class as PartyChatMenu scroll-follow bug (PR #166,
## intercom msg 2802). CutsceneGallery (Theater) has an _item_scroll
## ScrollContainer for the per-world unlock list, but pre-fix D-pad
## selection never called ensure_control_visible — as struktured's
## unlock list grows past the visible window, the highlight would render
## off-screen with no way to scroll from the gamepad.
##
## Proactive fix (before it hits playtest): _ensure_selected_item_visible
## helper called at the end of _update_display() so all navigation paths
## (D-pad up/down, mouse wheel, tab switches, initial render) track
## through the same choke point.


const GALLERY_SRC := "res://src/ui/CutsceneGallery.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_ensure_selected_item_visible_helper_exists() -> void:
	var src := _read(GALLERY_SRC)
	assert_gt(src.find("func _ensure_selected_item_visible("), -1,
		"CutsceneGallery must have a _ensure_selected_item_visible helper")
	var fn := src.find("func _ensure_selected_item_visible(")
	var body := src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	assert_gt(body.find("ensure_control_visible"), -1,
		"helper must call ScrollContainer.ensure_control_visible on the selected row — that's the whole point")


func test_update_display_invokes_helper() -> void:
	# Wire pin — _update_display is the choke point that every nav path
	# routes through (ui_up/down, mouse wheel, tab switch, initial render,
	# replay-finished return). Pinning the wire here covers all six.
	var src := _read(GALLERY_SRC)
	var fn := src.find("func _update_display(")
	assert_gt(fn, -1, "_update_display must exist")
	var body := src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	assert_gt(body.find("_ensure_selected_item_visible"), -1,
		"_update_display must invoke _ensure_selected_item_visible — otherwise the helper is orphan code and gamepad users can't reach items past the visible window")


func test_helper_guards_on_null_scroll_and_invalid_selection() -> void:
	# Test contexts / instantiation ordering may reach the helper before
	# _item_scroll is built; the helper must handle both cleanly.
	var src := _read(GALLERY_SRC)
	var fn := src.find("func _ensure_selected_item_visible(")
	var body := src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	assert_gt(body.find("_item_scroll == null") + body.find("is_instance_valid(_item_scroll)"), -1,
		"helper must guard on null / invalid _item_scroll")
	assert_gt(body.find("_selected_item_idx < 0") + body.find("_selected_item_idx >= _item_rows.size()"), -1,
		"helper must guard on out-of-range selection")
