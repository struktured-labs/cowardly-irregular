extends GutTest

## While the EXP tally counted, the victory prompt read "X: finish · X: continue": the same button named twice on one
## line, for two things that happen one after the other. It names the one thing the press does now.

const Overlay := preload("res://src/battle/VictoryOverlay.gd")


func test_the_tally_prompt_names_the_button_once() -> void:
	var text: String = Overlay.tally_prompt("X")
	assert_eq(text.count("X:"), 1, "the confirm button appears once in '%s'" % text)
	assert_false("·" in text, "one action, not a list ('%s')" % text)


func test_the_live_prompt_is_built_from_it() -> void:
	var src := FileAccess.get_file_as_string("res://src/battle/VictoryOverlay.gd")
	var i := src.find("func _build_prompt")
	assert_gt(i, -1, "CONTROL: the prompt builder exists")
	var next := src.find("\nfunc ", i + 1)
	var body := src.substr(i) if next < 0 else src.substr(i, next - i)
	assert_true("prompt.text = tally_prompt(_confirm_token())" in body, "the on-screen prompt uses the single-action text")
	assert_false(": finish" in body, "the doubled wording is gone")
