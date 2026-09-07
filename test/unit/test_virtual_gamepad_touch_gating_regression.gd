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


func test_first_touch_summons_the_pad() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/VirtualGamepad.gd")
	var i := src.find("func _input(")
	var body := src.substr(i, 700)
	assert_true("InputEventScreenTouch" in body and "_create_buttons()" in body,
		"a real touch on a hidden pad must build + show it (false-negative recovery)")
