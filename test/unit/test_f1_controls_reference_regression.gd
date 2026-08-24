extends GutTest

## struktured 2026-08-23: "it should be really easy to know all the buttons, like an oevrlay
## of keyboard mouse buttons that u can see with F1 or something."
##
## HowToPlayOverlay already held the reference and was reachable from exactly two places —
## the title screen and Controls → How to Play. Both are behind a menu you have to already
## know how to open, and neither is reachable mid-battle, which is where he got stuck.
## F1 binds it globally, in any state, above every other overlay.

const GL := "res://src/GameLoop.gd"
const OVERLAY := "res://src/ui/HowToPlayOverlay.gd"


func _fn_body(src: String, fn: String) -> String:
	var i := src.find("func " + fn)
	assert_gt(i, -1, fn + " present")
	var next := src.find("\nfunc ", i + 1)
	return src.substr(i, (next - i) if next > -1 else -1)


## Behavioural: build the real reference text and read it. A reference that has stopped
## naming the controls is the failure this whole feature exists to prevent, and it cannot
## be caught by pinning that F1 is wired.
func test_the_reference_names_keyboard_and_mouse_and_gamepad() -> void:
	var text: String = load(OVERLAY).build_text()
	assert_gt(text.length(), 200, "the reference must have a body — an empty one wires fine and helps nobody")
	for col in ["Gamepad", "Keyboard", "Mouse"]:
		assert_true(text.contains(col), "the reference must carry a %s column" % col)
	for binding in ["L-Click", "R-Click", "Arrow Keys", "D-Pad"]:
		assert_true(text.contains(binding), "the reference must name %s" % binding)
	assert_false(text.contains("zzz_not_a_real_binding"),
		"CONTROL: a fabricated binding must NOT be found, else contains() matches anything")


## The reference has to say how to reach itself — it renders on the title screen too, which
## is where a player first learns the key exists.
func test_the_reference_documents_its_own_hotkey() -> void:
	var text: String = load(OVERLAY).build_text()
	assert_true(text.contains("F1"), "F1 must appear in the reference it opens")


## F1 is bound globally and unconditionally — same tier as F12, which is the only other
## key in this file that works in every state. Ordering pins that: it sits above the
## state-gated hotkeys (F2/F3 bail out on TITLE and CUTSCENE), so a wedged player reaches it.
func test_f1_is_global_and_not_state_gated() -> void:
	var body := _fn_body(FileAccess.get_file_as_string(GL), "_input")
	# "KEY_F1" is a SUBSTRING of "KEY_F12" and the screenshot line comes first — the trailing
	# colon is what makes this the F1 handler rather than F12's.
	var f1 := body.find("KEY_F1:")
	var f2 := body.find("KEY_F2 ")
	assert_gt(f1, -1, "GameLoop._input must handle F1")
	assert_gt(f2, -1, "CONTROL: F2 is still handled here, so the finds are real")
	assert_lt(f1, f2, "F1 precedes the state-gated F2/F3 block — it must work while wedged")
	var seg := body.substr(f1, 260)
	assert_true(seg.contains("_toggle_help_overlay"), "F1 opens the reference")
	assert_false(seg.contains("LoopState."),
		"the F1 handler must not consult game state — a player stuck in a menu still needs it")


## Above everything. 128 was the highest CanvasLayer in GameLoop before this; the reference
## is useless if the thing you are stuck in draws over it.
func test_the_overlay_draws_above_every_other_layer() -> void:
	var src := FileAccess.get_file_as_string(GL)
	var body := _fn_body(src, "_toggle_help_overlay")
	var i := body.find("_help_layer.layer = ")
	assert_gt(i, -1, "the help layer must set an explicit layer")
	var assigned := int(body.substr(i + 20, 5).strip_edges())
	var highest := 0
	for part in src.split(".layer = "):
		var n := int(part.substr(0, 4).strip_edges())
		if n > highest and n != assigned:
			highest = n
	assert_gt(assigned, highest,
		"help layer %d must outrank every other layer in GameLoop (highest other: %d)" % [assigned, highest])


## Toggling off must free both the overlay and its layer. A leaked CanvasLayer per F1 press
## is the same orphan class as the wedge this shipped alongside.
func test_f1_toggles_closed_and_frees_its_layer() -> void:
	var body := _fn_body(FileAccess.get_file_as_string(GL), "_toggle_help_overlay")
	assert_true(body.contains("_close_help_overlay"), "a second F1 closes it")
	var close_body := _fn_body(FileAccess.get_file_as_string(GL), "_close_help_overlay")
	assert_true(close_body.contains("_help_overlay.queue_free()"), "the overlay is freed")
	assert_true(close_body.contains("_help_layer.queue_free()"), "and so is its CanvasLayer")
	assert_true(close_body.contains("_help_overlay = null"), "and the handle is cleared, so F1 re-opens")
