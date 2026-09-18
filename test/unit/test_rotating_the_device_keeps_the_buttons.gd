extends GutTest

## The virtual gamepad bakes every position from the viewport size at build time — `_compute_scale`
## and `_create_buttons` ran once, in `_ready`, and nothing watched `size_changed`.
##
## ⛔ MEASURED BEFORE THE FIX, 800x480 -> 480x800 (a phone rotating, or a browser window resized):
##     scale        1.000  ->  1.000     should be 800/480 = 1.667
##     A button     (746, 380) unchanged — x=746 in a 480-WIDE viewport, OFF SCREEN
##     d-pad        (90, 380)  unchanged — the old bottom edge, now mid-screen
##     children     25 -> 25, nothing rebuilt
## On a touch device that is the player losing A/B/X/Y with no way to get them back.
##
## ⚠️ THIS IS THE WEB AND TOUCH TARGET, WHICH IS WHY IT IS WORTH THE REBUILD COST. The pad only
## exists when `DisplayServer.is_touchscreen_available()` or a real ScreenTouch arrives, so a
## desktop player never sees any of this.
##
## 📌 The arms drive a real SubViewport and read the buttons' own recorded positions, not the
## source, because the defect is arithmetic against a viewport and source text cannot show it.

const VG := preload("res://src/ui/VirtualGamepad.gd")

const LANDSCAPE := Vector2i(800, 480)
const PORTRAIT := Vector2i(480, 800)


## Builds the pad inside a viewport of a known size. `_is_touch_device()` is false headless, so
## `_ready` does not build.
##
## ⛔ DRIVES THE THREE-STEP SEQUENCE, NOT `_build()`, AND THAT IS WHAT MAKES THE FAIL-FIRST POSSIBLE.
## `_build()` exists only after the fix, so calling it aborted this helper against the old source —
## it returned Array's default and all five arms scored Risky, EC=4, having asserted NOTHING. The
## three calls below exist in BOTH versions, so the same file can be run against either.
func _pad_in(size: Vector2i) -> Array:
	var sv := SubViewport.new()
	sv.size = size
	add_child_autofree(sv)
	var pad = VG.new()
	sv.add_child(pad)
	await get_tree().process_frame
	pad._visible = true
	pad._compute_scale()
	pad._create_buttons()
	pad._draw_dpad()
	await get_tree().process_frame
	return [sv, pad]


func _pos(pad, key: String) -> Vector2:
	return pad._buttons[key]["pos"] if pad._buttons.has(key) else Vector2(-1, -1)


## ⛔ THE CONTROL, and it has to come first: if the fixture never builds a pad inside the viewport
## it was given, every arm below compares two wrong numbers.
func test_the_pad_builds_against_the_viewport_it_is_in() -> void:
	var r = await _pad_in(LANDSCAPE)
	var pad = r[1]
	assert_gt(pad._buttons.size(), 6, "CONTROL: a real pad has a d-pad, a diamond, shoulders and a centre row")
	var a := _pos(pad, "ui_accept")
	assert_lt(a.x, float(LANDSCAPE.x), "CONTROL: the A button must start INSIDE the landscape viewport")
	assert_gt(a.x, float(LANDSCAPE.x) * 0.5, "CONTROL: …and on the right-hand side, which is where it is placed")


## ⛔ THE DEFECT. Every button must be inside the viewport after a rotation.
func test_every_button_stays_on_screen_after_a_rotation() -> void:
	var r = await _pad_in(LANDSCAPE)
	var sv: SubViewport = r[0]
	var pad = r[1]
	assert_lt(_pos(pad, "ui_accept").x, float(LANDSCAPE.x), "CONTROL: on screen before the rotation")

	sv.size = PORTRAIT
	await get_tree().process_frame
	await get_tree().process_frame

	var offenders: Array = []
	for key in pad._buttons:
		var p: Vector2 = pad._buttons[key]["pos"]
		if p.x < 0.0 or p.y < 0.0 or p.x > float(PORTRAIT.x) or p.y > float(PORTRAIT.y):
			offenders.append("%s at %s" % [key, p])
	assert_true(offenders.is_empty(),
		"after rotating to %s these buttons are off screen: %s — the layout was baked from the old "
		% [PORTRAIT, offenders] + "viewport and nothing watched size_changed")


## The scale must follow the new height too, or the buttons are the wrong SIZE on screen even when
## their centres are inside it.
func test_the_scale_follows_the_new_viewport() -> void:
	var r = await _pad_in(LANDSCAPE)
	var sv: SubViewport = r[0]
	var pad = r[1]
	var before: float = pad._scale
	assert_almost_eq(before, float(LANDSCAPE.y) / 480.0, 0.01, "CONTROL: 480 tall is the reference height")

	sv.size = PORTRAIT
	await get_tree().process_frame
	await get_tree().process_frame
	assert_almost_eq(pad._scale, float(PORTRAIT.y) / 480.0, 0.01,
		"the scale is viewport height / REFERENCE_HEIGHT and must be recomputed — it stayed at %.3f" % before)


## ⛔ ANTI-ACCUMULATION. A rebuild that does not tear down leaves the old visuals and touch areas
## parented, so the pad doubles on every resize and the stale hitboxes still answer.
func test_a_rebuild_does_not_accumulate_nodes() -> void:
	var r = await _pad_in(LANDSCAPE)
	var sv: SubViewport = r[0]
	var pad = r[1]
	var before: int = pad.get_child_count()
	assert_gt(before, 10, "CONTROL: the pad builds real nodes")

	sv.size = PORTRAIT
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(pad.get_child_count(), before,
		"a resize must REPLACE the layout, not append one: %d nodes before, %d after" % [before, pad.get_child_count()])


## ⛔ THE STUCK-INPUT SIBLING. A finger down when the device rotates would leave that action pressed
## with no button left to lift it — the same shape as a menu closing mid-hold.
func test_a_rotation_mid_press_does_not_strand_the_action() -> void:
	var r = await _pad_in(LANDSCAPE)
	var sv: SubViewport = r[0]
	var pad = r[1]

	pad._press_action("ui_accept")
	pad._touch_map[0] = "ui_accept"
	Input.flush_buffered_events()
	assert_true(Input.is_action_pressed("ui_accept"),
		"CONTROL: the press must actually land, or the release below has nothing to undo")

	sv.size = PORTRAIT
	await get_tree().process_frame
	await get_tree().process_frame
	Input.flush_buffered_events()
	assert_false(Input.is_action_pressed("ui_accept"),
		"rotating mid-press must release the held action — the button it came from no longer exists, "
		+ "so nothing else can ever lift it")
	assert_true(pad._touch_map.is_empty(),
		"…and the touch map must be dropped: its indices name buttons that are gone")


## ⛔ DERIVED, NOT LISTED. This was a hand-list of the ten actions the pad binds today, which is a
## teardown that silently stops covering the eleventh button somebody adds. The pad is autofreed by
## now so its own key set is gone — InputMap's action list is the population that outlives it, and
## releasing an action nobody pressed costs nothing.
func after_each() -> void:
	for a in InputMap.get_actions():
		Input.action_release(a)
	Input.flush_buffered_events()
