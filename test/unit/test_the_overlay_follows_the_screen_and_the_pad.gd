extends GutTest

## The controller overlay — the surface whose entire job is telling the player which button to
## press — was placed once and drawn once, and watched neither of the two things it is derived from.
##
## ⛔ MEASURED BEFORE THE FIX, on a real SubViewport, 1280x720 -> 640x480:
##     pos          (950, 520) UNCHANGED   right edge 1270 in a 640-wide viewport
##                                         bottom     710  in a 480-tall viewport
##     OFF SCREEN   x: true · y: true      the whole overlay, both axes
##     joy_connection_changed connections FROM the overlay: 0
##
## Two independent defects with one shape. GameLoop computed `Vector2(vp.x - 330, vp.y - 200)` at
## CREATION and the overlay is cached across an autogrind session, so a window resize strands it.
## And `_draw` resolves every face letter through `Input.get_connected_joypads()` and
## `InputProfileManager.face_glyph_for_index`, while `queue_redraw` was reachable ONLY from
## `set_context` — so a pad plugged in mid-session never reaches the letters.
##
## 📌 SIX OTHER FILES ALREADY LISTEN for `joy_connection_changed` — ControlsMenu, AutogrindUI,
## AutogrindGridEditor, GamepadFilter, ControllerMappings, InputProfileManager. The convention
## existed; the one surface drawing the buttons was outside it.
##
## ⚠️ The pad-connected branch of `_face_print` cannot be driven headless — there are no pads — so
## these arms pin the WIRING on the real Input singleton and the no-pad answer, not a glyph.

const CO := preload("res://src/ui/ControllerOverlay.gd")

const BIG := Vector2i(1280, 720)
const SMALL := Vector2i(640, 480)


## Builds the overlay in a viewport of a known size and places it the way the app does, so the
## fixture is the same on both versions of the source: pre-fix the caller owns the position, and
## post-fix `_reanchor` computes the same corner, so this line is simply redundant rather than wrong.
func _overlay_in(size: Vector2i) -> Array:
	var sv := SubViewport.new()
	sv.size = size
	add_child_autofree(sv)
	var o = CO.new()
	sv.add_child(o)
	await get_tree().process_frame
	var vp: Vector2 = sv.get_visible_rect().size
	o.position = Vector2(vp.x - 330.0, vp.y - 200.0)
	o.size = CO.OVERLAY_SIZE
	await get_tree().process_frame
	return [sv, o]


func _fully_inside(o, vp: Vector2) -> bool:
	return o.position.x >= 0.0 and o.position.y >= 0.0 \
		and o.position.x + CO.OVERLAY_SIZE.x <= vp.x \
		and o.position.y + CO.OVERLAY_SIZE.y <= vp.y


## ⛔ THE CONTROL, first: if the fixture does not put the overlay on screen to begin with, the
## resize arm below compares two wrong numbers and passes for the wrong reason.
func test_the_overlay_starts_inside_the_viewport_it_is_in() -> void:
	var r = await _overlay_in(BIG)
	var sv: SubViewport = r[0]
	var o = r[1]
	assert_true(_fully_inside(o, sv.get_visible_rect().size),
		"CONTROL: the overlay must start fully on screen, got %s in %s" % [o.position, BIG])
	assert_gt(o.position.x, 0.0, "CONTROL: …and anchored right, which is where the app puts it")


## ⛔ THE DEFECT.
func test_the_overlay_stays_on_screen_when_the_window_shrinks() -> void:
	var r = await _overlay_in(BIG)
	var sv: SubViewport = r[0]
	var o = r[1]
	assert_true(_fully_inside(o, sv.get_visible_rect().size), "CONTROL: on screen before the resize")

	sv.size = SMALL
	await get_tree().process_frame
	await get_tree().process_frame

	var vp: Vector2 = sv.get_visible_rect().size
	assert_true(_fully_inside(o, vp),
		"after shrinking to %s the overlay sits at %s, so its right edge is %.0f and its bottom %.0f "
			% [SMALL, o.position, o.position.x + CO.OVERLAY_SIZE.x, o.position.y + CO.OVERLAY_SIZE.y]
		+ "in a %.0fx%.0f viewport — the corner was computed once at creation" % [vp.x, vp.y])


## Growing is the same defect with the opposite symptom: the overlay drifts to the middle of the
## screen instead of off it, which is why a guard that only shrinks would pass a half fix.
func test_the_overlay_re_anchors_when_the_window_grows() -> void:
	var r = await _overlay_in(SMALL)
	var sv: SubViewport = r[0]
	var o = r[1]
	var before: Vector2 = o.position

	sv.size = BIG
	await get_tree().process_frame
	await get_tree().process_frame

	assert_true(_fully_inside(o, sv.get_visible_rect().size), "still on screen after growing")
	assert_gt(o.position.x, before.x,
		"the overlay is bottom-right anchored, so a wider window must move it right — it stayed at %s" % [before])


## ⛔ THE SECOND DEFECT, and it is not about geometry at all. Every face letter is resolved per pad
## at draw time; nothing asked to be redrawn when the pad changes.
func test_the_overlay_asks_to_be_redrawn_when_a_pad_arrives() -> void:
	var r = await _overlay_in(BIG)
	var o = r[1]
	var mine: int = 0
	for c in Input.get_signal_connection_list("joy_connection_changed"):
		if c["callable"].get_object() == o:
			mine += 1
	assert_eq(mine, 1,
		"the overlay draws its face letters from Input.get_connected_joypads() and the active "
		+ "profile, so it must listen for joy_connection_changed — %d connection(s) from it" % mine)


## …and it must let go. The overlay is freed at the end of an autogrind session (GameLoop calls
## _destroy_controller_overlay), and a connection outliving its object is the stranded-state shape
## this lane keeps finding.
func test_the_listener_does_not_outlive_the_overlay() -> void:
	var sv := SubViewport.new()
	sv.size = BIG
	add_child_autofree(sv)
	var o = CO.new()
	sv.add_child(o)
	await get_tree().process_frame

	var before: int = Input.get_signal_connection_list("joy_connection_changed").size()
	o.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var after: int = Input.get_signal_connection_list("joy_connection_changed").size()
	assert_eq(after, before - 1,
		"freeing the overlay must drop its joy_connection_changed connection: %d -> %d" % [before, after])


## A viewport smaller than the overlay must not push it to a NEGATIVE corner — off the top-left is
## off screen exactly as much as off the bottom-right, and the max() that prevents it is the kind
## of line that gets dropped as redundant.
func test_a_viewport_smaller_than_the_overlay_does_not_go_negative() -> void:
	var r = await _overlay_in(BIG)
	var sv: SubViewport = r[0]
	var o = r[1]

	sv.size = Vector2i(200, 120)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_gte(o.position.x, 0.0, "a viewport narrower than the overlay must clamp, not go negative: %s" % [o.position])
	assert_gte(o.position.y, 0.0, "…on both axes: Y must clamp too, not go negative")


## With no pad attached the position initial is the only true answer — face_glyph_for_index would
## hand back a family's letter as if it were neutral. Pins the file's own stated contract, and is
## the reason the arms above pin wiring rather than glyphs.
func test_with_no_pad_the_face_prints_its_position() -> void:
	assert_true(Input.get_connected_joypads().is_empty(),
		"precondition: this suite runs headless with no pads, or the assert below means nothing")
	var r = await _overlay_in(BIG)
	var o = r[1]
	assert_eq(o._face_print(1, "E"), "E", "no pad: the east position prints its own initial")
	assert_eq(o._face_print(0, "S"), "S", "…and south prints its own")


## ⛔ THE OWNERSHIP MOVE ITSELF, and without this arm it is untested. Every arm above places the
## overlay by hand the way GameLoop used to, so dropping the `_reanchor()` call in `_ready` left
## them all green — measured, not assumed. GameLoop no longer sets a position at all, so an overlay
## that does not place itself on entry sits at (0, 0) until the first resize.
##
## 📌 This arm reds against the pre-fix source for a different reason than the others: the contract
## it pins did not exist there. That is correct for a fix that moves ownership, and it is why it is
## stated here rather than counted as another fail-first on the original defect.
func test_the_overlay_places_itself_without_being_told() -> void:
	var sv := SubViewport.new()
	sv.size = BIG
	add_child_autofree(sv)
	var o = CO.new()
	sv.add_child(o)
	await get_tree().process_frame

	assert_true(_fully_inside(o, sv.get_visible_rect().size),
		"nobody set a position: the overlay must anchor itself on entry, got %s" % [o.position])
	assert_gt(o.position.x, float(BIG.x) * 0.5, "…bottom-right, not the top-left default")
	assert_gt(o.position.y, float(BIG.y) * 0.5, "…on both axes: Y must anchor bottom, not stay at the top-left default")
