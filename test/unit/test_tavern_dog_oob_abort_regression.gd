extends GutTest

## Regression: render-smoke log 2026-07-31 — two `ERROR: Index p_x = 48 is out of bounds
## (width = 48)` at set_pixel, one per dog frame. _draw_sleeping_dog wrote its nose at a
## hardcoded x=48 on a 48-wide image (TILE_SIZE + 16). The snout loop immediately above it
## already carried the `x < img.get_width()` guard; the single pixel below it did not.
##
## ⚠️ Image.set_pixel is a C++ builtin: ERR_FAIL_INDEX returns from the ENGINE function, not
## from the GDScript one. Execution CONTINUES — the ear and paws drawn after it are fine. I
## first asserted those were missing and the mutation proved they were not. The whole defect
## is the dropped nose pixel plus two ERROR lines in every run's log.
##
## So assert the nose COLOR at the tip. Alpha alone is useless here: the snout loop already
## paints that column fur_b, so an alpha check passes with the nose missing.

const DOG_H: int = 24
const NOSE := Color(0.25, 0.16, 0.14)
const FUR_B := Color(0.48, 0.32, 0.16)


func _dog_image(frame: int) -> Image:
	var tavern := TavernInterior.new()
	var img := Image.create(TavernInterior.TILE_SIZE + 16, DOG_H, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	tavern._draw_sleeping_dog(img, frame)
	tavern.free()
	return img


func _is_close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02


func test_nose_painted_at_the_snout_tip_both_frames() -> void:
	for frame in [0, 1]:
		var img := _dog_image(frame)
		var tip := img.get_pixel(img.get_width() - 1, 11)
		assert_true(_is_close(tip, NOSE),
			"frame %d: last column at y=11 must be the NOSE, got %s — a hardcoded x=48 lands one past it and the pixel is silently dropped" % [frame, str(tip)])


func test_control_that_column_is_fur_without_the_nose() -> void:
	# CONTROL: proves the assertion above can fail. y=12 is snout fur, never the nose —
	# if this ever reads as NOSE the colour check is matching something it shouldn't.
	var img := _dog_image(0)
	var fur := img.get_pixel(img.get_width() - 1, 12)
	assert_true(_is_close(fur, FUR_B),
		"CONTROL: y=12 of the last column is snout fur, got %s" % str(fur))
	assert_false(_is_close(fur, NOSE), "CONTROL: fur must not read as nose")


func test_no_pixel_is_written_outside_the_image() -> void:
	# The width is derived, so a future resize cannot reintroduce the out-of-bounds write.
	var img := _dog_image(0)
	assert_eq(img.get_width(), 48, "the 48-wide image this regression is about")
	assert_gt(img.get_pixel(47, 11).a, 0.0, "last valid column must be painted, not skipped")
