extends GutTest

## BattleDialogue sizes its body from one font's line height, and the body is a RichTextLabel that draws the READ-tier
## face. It measured with ThemeDB.fallback_font, which the face install points at the DISPLAY face, so above 100% the
## box grew by the wrong face's metrics (adhoc census 2026-11-14). Speaker and hint stay Labels on the display face.

const BD := preload("res://src/ui/BattleDialogue.gd")

var _saved_scale: float = 1.0


func before_each() -> void:
	if GameState and "text_size_scale" in GameState:
		_saved_scale = float(GameState.text_size_scale)


func after_each() -> void:
	if GameState and "text_size_scale" in GameState:
		GameState.text_size_scale = _saved_scale
	UiFont.read_tier = UiFont.READ_TIER_DEFAULT
	UiFont.install(UiFont.READ_TIER_DEFAULT)


func _expected_body_h(font: Font, body_px: int) -> float:
	return ceil(74.0 * maxf(1.0, float(font.get_height(body_px))) / maxf(1.0, float(font.get_height(13))))


func test_the_body_grows_by_the_face_it_is_drawn_in() -> void:
	UiFont.install(UiFont.READ_TIER_DEFAULT)
	assert_true(UiFont.is_installed(), "CONTROL: the face is installed")
	GameState.text_size_scale = 2.0
	var box = BD.new()
	add_child_autofree(box)
	var m: Dictionary = box._dialogue_metrics()
	var body_px: int = int(m["body_px"])
	assert_gt(body_px, 13, "CONTROL: 200% Text Size grows the body past the authored slot")
	var by_body: float = _expected_body_h(UiFont.body(), body_px)
	var by_display: float = _expected_body_h(UiFont.display(), body_px)
	assert_ne(by_body, by_display, "CONTROL: the two faces size this body differently, or this arm cannot tell them apart")
	assert_eq(float(m["body_h"]), by_body, "the RichTextLabel body is sized by the read-tier face it draws")


func test_the_choice_hint_measures_its_own_label() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/llm/DialogueChoiceMenu.gd")
	assert_true(src.contains("UiFont.of(_hint_label)"), "the hint is sized by the font its Label resolves")
	assert_false(src.contains("ThemeDB.fallback_font"), "and by nothing that can drift from it")
