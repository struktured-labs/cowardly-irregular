extends GutTest

## struktured 2026-11-19, playing .808 in a 3440x1362 window: the Mug description drew its second line on its first,
## and the whole UI was in a thin monospace he called "not video gamey, just different". That monospace is the Latin
## FALLBACK. The pixel face is built in code; a window that changes size changes the engine's global font
## oversampling, the engine clears the size cache of every font that follows the global value, and a face with no
## file behind it has nothing to redraw from. Every tool and test ran in a window that never changed size.

var _ts: TextServer
var _was: float


func before_each() -> void:
	_ts = TextServerManager.get_primary_interface()
	_was = _ts.font_get_global_oversampling()


func after_each() -> void:
	_ts.font_set_global_oversampling(_was)


## What a resize does to the fonts, without a window: the global oversampling moves to a new value.
func _resize_the_window() -> void:
	_ts.font_set_global_oversampling(_was + 0.89140625)


func _ink(f: FontFile, ch: String) -> int:
	var size := Vector2i(UiFont.nominal(), 0)
	var r: Rect2 = f.get_glyph_uv_rect(0, size, ch.unicode_at(0))
	return int(r.size.x * r.size.y)


func test_the_face_still_draws_its_letters_after_the_window_changes_size() -> void:
	var f: FontFile = UiFont.display()
	assert_gt(_ink(f, "A"), 0, "CONTROL: the face draws 'A' before the resize")
	var h_before: float = f.get_height(13)
	var w_before: float = f.get_string_size("Attack and steal in one action", HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	_resize_the_window()
	assert_gt(_ink(f, "A"), 0, "'A' is still the face's own drawing after the resize")
	assert_gt(_ink(UiFont._outlined, "A"), 0, "and the rimmed face's")
	assert_eq(f.get_string_size("Attack and steal in one action", HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, w_before, "his Mug description measures the same width, so it wraps where it did")
	var solo: Font = f.duplicate()
	solo.fallbacks = []
	assert_eq(solo.get_height(13), 12.0, "the face alone is still one 12 px line at size 13")
	assert_almost_eq(f.get_height(13), h_before, 1.0, "and the chain's line is within a pixel of what it was")


func test_a_description_keeps_its_lines_apart_after_the_window_changes_size() -> void:
	_resize_the_window()
	var f: Font = UiFont.display()
	# What Win98Menu puts on its description label when it builds it, AFTER the resize as in his session.
	var spacing: int = FontFallbacks.line_spacing_correction(f, 13)
	assert_gt(float(f.get_height(13)) + float(spacing), 8.0, "a second line lands most of a line below the first, not on top of it (line_spacing %d)" % spacing)


func test_a_face_that_follows_the_window_is_emptied_by_it() -> void:
	# CONTROL for the measure: the same build with the engine's default (follow the global value) loses its glyphs.
	var follower: FontFile = UiFont._build(false)
	follower.oversampling = 0.0
	# Setting oversampling clears the cache, so this follower starts empty; draw one glyph back in the way _build does.
	var size := Vector2i(UiFont.nominal(), 0)
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	follower.set_cache_ascent(0, UiFont.nominal(), UiFont.ASCENT)
	follower.set_texture_image(0, size, 0, img)
	follower.set_glyph_uv_rect(0, size, "A".unicode_at(0), Rect2(0, 0, 5, 7))
	assert_gt(_ink(follower, "A"), 0, "CONTROL: the follower draws 'A' before the resize")
	_resize_the_window()
	assert_eq(_ink(follower, "A"), 0, "a face that follows the global oversampling is emptied by a resize: the defect")
	assert_eq(UiFont.OWN_OVERSAMPLING, 1.0, "the shipped face names its own")
	assert_eq(UiFont.display().oversampling, 1.0, "and the built face carries it")
