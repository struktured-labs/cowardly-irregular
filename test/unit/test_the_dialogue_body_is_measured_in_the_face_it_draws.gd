extends GutTest

## Regression (adhoc census 2026-11-14): CutsceneDialogue._box_metrics took ONE fallback font for the speaker, the hint
## AND the body's line height. Under the pixel UI face the speaker and hint are Labels (display face) but the body is a
## RichTextLabel, which draws the READING face, so the grown panel was sized from the wrong font's lines.

var _saved_scale := 1.0


func before_each() -> void:
	_saved_scale = float(GameState.text_size_scale)


func after_each() -> void:
	GameState.text_size_scale = _saved_scale
	UiFont.read_tier = UiFont.READ_TIER_DEFAULT
	UiFont.install(UiFont.READ_TIER_DEFAULT)


## The text height _box_metrics must give when its body lines come from `f` (same arithmetic, same viewport cap).
func _text_h_from(f: Font, d: CutsceneDialogue, speaker_h: float, hint_h: float) -> float:
	var body_px: int = d._scaled_font_size(16)
	var line_h: float = maxf(1.0, float(f.get_height(body_px)))
	var g: float = line_h / maxf(1.0, float(f.get_height(16)))
	var text_y: float = float(CutsceneDialogue.TILE_SIZE * 2 - 8) + speaker_h + 4.0
	var text_h: float = ceil(float(CutsceneDialogue.BOX_HEIGHT - CutsceneDialogue.TILE_SIZE * 4 - 30) * g * g)
	var box_h: float = text_y + text_h + hint_h + 6.0
	var cap: float = d.get_viewport().get_visible_rect().size.y - float(CutsceneDialogue.MARGIN * 2)
	if cap >= float(CutsceneDialogue.BOX_HEIGHT) and box_h > cap:
		text_h = maxf(line_h, text_h - (box_h - cap))
	return text_h


func test_the_body_lines_are_measured_in_the_reading_face() -> void:
	UiFont.install(UiFont.READ_TIER_DEFAULT)
	assert_true(UiFont.is_installed(), "CONTROL: the pixel face is installed")
	assert_ne(UiFont.body(), UiFont.display(), "CONTROL: at the default read tier the body is not the pixel face")
	var seen_apart := false
	for p in SettingsMenu.TEXT_SIZE_PRESETS:
		if float(p) <= 1.0:
			continue
		GameState.text_size_scale = float(p)
		var d := CutsceneDialogue.new()
		add_child_autofree(d)
		var m: Dictionary = d._box_metrics()
		var speaker_h: float = float(UiFont.display().get_height(d._scaled_font_size(18)))
		var hint_h: float = float(UiFont.display().get_height(d._scaled_font_size(12)))
		var want: float = _text_h_from(UiFont.body(), d, speaker_h, hint_h)
		var wrong: float = _text_h_from(UiFont.display(), d, speaker_h, hint_h)
		if not is_equal_approx(want, wrong):
			seen_apart = true
		assert_almost_eq(float(m["text_h"]), want, 0.5,
			"at Text Size %s the body box is sized from the reading face's lines (%s), not the pixel face's (%s)" % [p, want, wrong])
	assert_true(seen_apart, "CONTROL: at some grown size the two faces give different heights, so this arm can fail")
