extends GutTest

## Web UX fix (2026-07-10): VirtualGamepad's `OS.has_feature("web")` blanket
## painted permanent touch buttons over EVERY desktop-browser player's
## screen (caught by the new web-boot smoke's screenshot). Now it gates on
## REAL touch detection, with first-touch recovery: a finger on a
## mis-detected device summons the pad instantly.

func test_detection_drops_the_web_blanket() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/VirtualGamepad.gd")
	var i := src.find("func _is_touch_device")
	var body := src.substr(i, 500)
	assert_false("has_feature(\"web\")" in body,
		"the web blanket must stay gone — desktop-browser players get a clean screen")
	assert_true("is_touchscreen_available()" in body, "real detection remains")


## ⛔ DRIVEN, NOT GREPPED. This asserted `"_create_buttons()" in body` — the literal call inside
## `_input` — and went red when that build was hoisted into a single `_build()` helper so the
## first-touch path and the resize rebuild could not drift apart. The behaviour was identical.
## A guard pinned to a CALL SITE reds on a correct refactor and passes on a build that produces
## nothing; feeding the pad a real touch cannot do either.
func test_first_touch_summons_the_pad() -> void:
	var sv := SubViewport.new()
	sv.size = Vector2i(800, 480)
	add_child_autofree(sv)
	var pad = load("res://src/ui/VirtualGamepad.gd").new()
	sv.add_child(pad)
	await get_tree().process_frame

	## Headless has no touchscreen, so _ready leaves it hidden — which is the mis-detected device
	## this recovery exists for.
	assert_false(bool(pad._visible), "CONTROL: the pad must start hidden, or there is nothing to recover from")
	assert_eq(int(pad._buttons.size()), 0, "CONTROL: …and must have built nothing yet")

	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = Vector2(400, 240)
	pad._input(touch)
	await get_tree().process_frame

	assert_true(bool(pad._visible), "a real touch on a hidden pad must show it (false-negative recovery)")
	assert_gt(int(pad._buttons.size()), 6,
		"…and must BUILD it: a d-pad, a diamond, shoulders and a centre row, got %d" % pad._buttons.size())
