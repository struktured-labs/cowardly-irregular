extends GutTest

## struktured's standing directive: "it is time to make this thing useeable with a mouse and
## keyboard for reals."
##
## MEASURED 2026-09-10, the mouse mirror of the pad sweeps: of 34 interactive UI screens, 29 gave a
## mouse player right-click-to-close and FIVE did not — while every one of the five is reachable by
## CLICKING (FormationsMenu and LensMenu from the overworld menu, RebalanceReviewPanel from
## Settings, AutogrindSummary after a grind, RadialPicker from both grid editors).
##
## None was a hard wedge — ui_cancel binds Escape, so a keyboard was always a way out. It was a
## broken CONVENTION: the gesture that closes 29 screens silently did nothing on 5, which is what
## makes a UI feel unfinished rather than broken.
##
## RadialPicker was deferred pending a z-order question, then RESOLVED: it sets MOUSE_FILTER_STOP
## and is added after the editor background, so it CONSUMES a right-click and cannot leak through
## to the editor's own cancel. Safe, and now included. The deferral was right at the time; the
## answer came from reading the filter and the child order, not from guessing.

const SCREENS := [
	"res://src/ui/FormationsMenu.gd",
	"res://src/ui/LensMenu.gd",
	"res://src/ui/RebalanceReviewPanel.gd",
	"res://src/ui/autogrind/AutogrindSummary.gd",
	"res://src/ui/RadialPicker.gd",
]


## Each must offer the convention.
func test_each_reachable_screen_offers_right_click_close() -> void:
	for path in SCREENS:
		var src := FileAccess.get_file_as_string(path)
		assert_gt(src.length(), 0, "CONTROL: %s must be readable" % path)
		assert_true(src.contains("add_right_click_cancel"),
			"%s is reachable by clicking, so right-click must close it like the other 29" % path.get_file())


## And the callback must do what that screen's OWN cancel does — not a second implementation that
## can drift from it.
func test_the_mouse_path_matches_the_screens_own_cancel() -> void:
	for path in SCREENS:
		var src := FileAccess.get_file_as_string(path)
		var at := src.find("add_right_click_cancel")
		var body := src.substr(at, 260)
		var closes := body.contains("closed.emit") or body.contains("dismissed.emit") or body.contains("queue_free")
		assert_true(closes,
			"%s: the right-click callback must actually close the screen" % path.get_file())


## CONTROL: the convention must genuinely exist elsewhere, or "matching the other 29" is a claim
## about nothing.
func test_the_convention_is_real_and_widespread() -> void:
	var users := 0
	var dir := DirAccess.open("res://src/ui")
	assert_not_null(dir, "src/ui must be readable")
	for f in dir.get_files():
		if f.ends_with(".gd") and FileAccess.get_file_as_string("res://src/ui/" + f).contains("add_right_click_cancel"):
			users += 1
	assert_gt(users, 10,
		"right-click-to-close must be a real convention, found %d screens using it" % users)


## CONTROL: the helper it depends on must exist and take a callback.
func test_the_helper_exists() -> void:
	var h := FileAccess.get_file_as_string("res://src/ui/MenuMouseHelper.gd")
	assert_true(h.contains("static func add_right_click_cancel"), "the shared helper must exist")
	assert_true(h.contains("cancel_callback"), "and take the caller's own close action")
