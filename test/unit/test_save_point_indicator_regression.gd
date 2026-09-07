extends GutTest

## Regression: SavePoint's proximity indicator must include the button
## glyph so players know HOW to save, not just THAT they're near a
## crystal. Pre-fix the label said "Save" — fine for JRPG-veterans who
## know to mash A, opaque for newcomers. Updated to "[A] Save" matching
## the game's existing input-hint convention (battle hint bar uses the
## same [L] / [R] / [A] / [B] glyph format).

const SAVE_POINT_PATH := "res://src/exploration/SavePoint.gd"


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_setup_indicator_includes_button_glyph() -> void:
	var text = _read(SAVE_POINT_PATH)
	# Locate _setup_indicator body.
	var fn_idx = text.find("func _setup_indicator()")
	assert_true(fn_idx > -1, "_setup_indicator must exist")
	var fn_end = text.find("\n\nfunc ", fn_idx)
	var body = text.substr(fn_idx, fn_end - fn_idx) if fn_end > -1 else text.substr(fn_idx, 1500)
	# Must surface the [A] button glyph + label, not just "Save"
	assert_true(body.find("\"[A] Save\"") > -1,
		"_setup_indicator must set indicator.text to '[A] Save' (includes button glyph for newcomers)")
	# Catch anyone reverting to the legacy bare "Save" string
	assert_false(body.find("_indicator.text = \"Save\"") > -1,
		"Legacy bare 'Save' text must be gone — pinned to prevent reverts")


func test_indicator_label_actually_renders_with_glyph() -> void:
	# Behavioral: instantiate a SavePoint, run _setup_indicator, confirm
	# the indicator Label has the expected text. (We use _setup_indicator
	# directly rather than driving the full _ready flow to keep the test
	# focused on the indicator contract.)
	var script = load(SAVE_POINT_PATH)
	var sp = script.new()
	add_child_autofree(sp)
	sp._setup_indicator()
	assert_not_null(sp._indicator, "_setup_indicator must populate _indicator field")
	if sp._indicator:
		assert_eq((sp._indicator as Label).text, "[A] Save",
			"Indicator label must be exactly '[A] Save'")
		assert_false(sp._indicator.visible,
			"Indicator must start hidden (visibility flips true on body entry)")


func test_indicator_width_can_fit_glyph_without_truncation() -> void:
	# Layout invariant: the indicator's size must be wide enough to
	# accommodate the "[A] Save" text at the chosen font size without
	# clipping (Godot Label truncates when text overflows size.x). The
	# specific width chosen (64) is enough at font_size 10 — but pin
	# it so anyone shrinking the indicator catches the regression.
	var script = load(SAVE_POINT_PATH)
	var sp = script.new()
	add_child_autofree(sp)
	sp._setup_indicator()
	if sp._indicator:
		assert_gte(sp._indicator.size.x, 56.0,
			"Indicator width must be >= 56px to fit '[A] Save' at font_size 10 without truncation")
		assert_eq(sp._indicator.horizontal_alignment, HORIZONTAL_ALIGNMENT_CENTER,
			"Indicator must stay center-aligned over the crystal")
