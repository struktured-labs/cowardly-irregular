extends GutTest

## HOW TO PLAY is the screen a player opens BECAUSE they cannot work out the controls — and every
## cell in it branches on whether a pad is attached, built once in `_ready` and never refreshed.
##
## ⛔ SO PLUGGING A CONTROLLER IN WHILE IT IS OPEN LEFT THE KEYBOARD VOCABULARY ON SCREEN:
##     no pad    `_face_cell` -> "S face"        `_close_glyph` -> a key name
##     with pad  `_face_cell` -> "Ⓐ Button"      `_close_glyph` -> the pad's glyph
## That is the exact moment the overlay exists for, on the one surface whose entire job is telling
## the player which button to press. Reachable from the title screen, from ControlsMenu, and from
## GameLoop's F1 — three entrances, none of which rebuilds it.
##
## ⚠️ HEADLESS HAS NO PADS, so the derived TEXT cannot actually change here. These arms overwrite
## the content with a SENTINEL and require it re-derived, which measures "this was rebuilt" — the
## contract. Same technique as the two footer guards in this lane, and for the same reason.

const OVERLAY := preload("res://src/ui/HowToPlayOverlay.gd")
const SENTINEL := "ZZZ_STALE_SENTINEL"


func _overlay() -> Node:
	var sv := SubViewport.new()
	sv.size = Vector2i(1280, 720)
	add_child_autofree(sv)
	var o = OVERLAY.new()
	sv.add_child(o)
	await get_tree().process_frame
	await get_tree().process_frame
	return o


## ⛔ THE CONTROL, first: if the overlay does not build derived content, every arm below is
## rewriting an empty string with another empty string.
func test_the_overlay_builds_derived_content() -> void:
	var o = await _overlay()
	assert_not_null(o._scroll_target, "CONTROL: the content label must exist")
	assert_gt(o._scroll_target.text.length(), 100,
		"CONTROL: it must hold the help body, got %d chars" % o._scroll_target.text.length())
	assert_true(o._scroll_target.text.contains(InputProfileManager.hint_for_action("ui_cancel")),
		"CONTROL: the close hint must be DERIVED to begin with, or staleness costs nothing")


## ⛔ THE DELIVERY, not the function — a handler that exists and is never reached passes any arm
## that calls it directly and fails every player.
func test_the_overlay_listens_for_a_pad_change() -> void:
	var o = await _overlay()
	var mine: int = 0
	for c in Input.get_signal_connection_list("joy_connection_changed"):
		if c["callable"].get_object() == o:
			mine += 1
	assert_eq(mine, 1,
		"every cell here branches on whether a pad is attached, so the overlay must hear "
		+ "joy_connection_changed — %d connection(s) from it" % mine)


## ⛔ THE DEFECT.
func test_plugging_a_pad_in_rebuilds_the_help() -> void:
	var o = await _overlay()
	o._scroll_target.text = SENTINEL

	Input.joy_connection_changed.emit(0, true)
	await get_tree().process_frame

	assert_ne(o._scroll_target.text, SENTINEL,
		"a controller arrived while HOW TO PLAY was open and the text was not re-derived — the "
		+ "player is reading keyboard instructions on the screen they opened to learn their pad")
	assert_gt(o._scroll_target.text.length(), 100, "…and the rebuild must produce the real body")


## …and a pad LEAVING is the same gap with the opposite sign: pad glyphs left naming a device that
## is gone, which is the harm .308-.338 removed.
func test_unplugging_a_pad_rebuilds_the_help() -> void:
	var o = await _overlay()
	o._scroll_target.text = SENTINEL

	Input.joy_connection_changed.emit(0, false)
	await get_tree().process_frame

	assert_ne(o._scroll_target.text, SENTINEL, "a pad leaving must re-derive the help text too")


## ⚠️ THERE IS NO SCROLL ARM HERE, AND THAT IS A MEASUREMENT RATHER THAN AN OVERSIGHT. The handler
## holds the reader's position across a rebuild, because a SHORTER body clamps a RichTextLabel's
## scroll value to 0 and growing it back does not restore it (440 -> 0 -> 0, measured). But headless
## has no pad, so the rebuilt text is IDENTICAL and the clamp cannot occur: an arm asserting the
## position survives passed with the preservation REMOVED — 6/6 green on the mutation it was written
## to catch. It is stated here instead, because an arm that cannot fail reads as cover and is worse
## than none.


## The overlay is created and freed repeatedly — three entrances open a fresh one each time — so a
## connection outliving it is the stranded-state shape this lane keeps finding.
func test_the_listener_does_not_outlive_the_overlay() -> void:
	var sv := SubViewport.new()
	sv.size = Vector2i(1280, 720)
	add_child_autofree(sv)
	var o = OVERLAY.new()
	sv.add_child(o)
	await get_tree().process_frame

	var before: int = Input.get_signal_connection_list("joy_connection_changed").size()
	o.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	assert_eq(Input.get_signal_connection_list("joy_connection_changed").size(), before - 1,
		"freeing the overlay must drop its joy_connection_changed connection: %d -> %d"
			% [before, Input.get_signal_connection_list("joy_connection_changed").size()])
