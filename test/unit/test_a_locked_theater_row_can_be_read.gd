extends GutTest

## The Theater opens with every row "??? (locked)"; at Color(0.3, 0.3, 0.35) on its near-black backdrop that measured
## 2.4:1 on a rendered frame, so a new player's first Theater was a screen of barely-visible text.

const Gallery := preload("res://src/ui/CutsceneGallery.gd")


func _chan(v: float) -> float:
	return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)


func _lum(c: Color) -> float:
	return 0.2126 * _chan(c.r) + 0.7152 * _chan(c.g) + 0.0722 * _chan(c.b)


func _ratio(a: Color, b: Color) -> float:
	return (maxf(_lum(a), _lum(b)) + 0.05) / (minf(_lum(a), _lum(b)) + 0.05)


func test_a_locked_row_clears_large_text_contrast() -> void:
	assert_gt(_ratio(Gallery.LOCKED_COLOR, Gallery.BG_COLOR), 4.0, "locked rows read against the backdrop")


func test_locked_still_reads_dimmer_than_unlocked() -> void:
	assert_lt(_lum(Gallery.LOCKED_COLOR), _lum(Gallery.DIM_COLOR), "a locked row stays dimmer than secondary text")
