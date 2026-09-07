extends GutTest

## Defensive regression: SpriteUtils._outlined_pixel() must use the
## image's actual height for the Y bounds check, not reuse the width.
##
## Bug shape:
##   • Pre-fix: `var s = img.get_width()` and then both `px < s` and
##     `py < s` were checked against width. Wrong on non-square
##     images.
##   • SNES party sprites are 32 wide × 48 tall (SNES_WIDTH=32,
##     SNES_HEIGHT=48 in this file). On those:
##       - If outline target was near the top: py < s == 32 worked
##         (height 48 > 32, so rows 32..47 were inaccessible — silent
##         outlining gap).
##       - If outline target was beyond y=32: bounds check passed
##         falsely, but img.set_pixel at py > height-1 logged a
##         runtime error.
##   • _outlined_pixel has zero callers TODAY, so this is purely a
##     defensive-correctness fix — the function will misbehave the
##     moment anyone wires it into a sprite generator. The other
##     drawing helpers in this file (_draw_shine_spot,
##     _draw_aa_ellipse_outline, _draw_rim_light, _draw_specular)
##     all use (get_width / get_height) correctly. This was the
##     outlier.
##
## Fix: separate `w := get_width(); h := get_height()` locals and
## check `px < w` / `py < h`.
##
## Tests:
##   • Source pin: the function reads both get_width() and
##     get_height() (not just width twice)
##   • Negative source pin: the bug shape `s = img.get_width()`
##     followed by `py < s` is GONE
##   • Behavioural: drive _outlined_pixel against a non-square (32×48)
##     image at y > 32 — the call completes without errors and the
##     center pixel is set

const SPRITE_UTILS_PATH := "res://src/battle/sprites/SpriteUtils.gd"


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


# ── Source pins ───────────────────────────────────────────────────────────────

func test_outlined_pixel_reads_both_width_and_height() -> void:
	var text := _read(SPRITE_UTILS_PATH)
	var idx := text.find("func _outlined_pixel")
	assert_gt(idx, -1, "_outlined_pixel must exist")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nstatic func ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	# Both width and height must be read inside the body (the bug was
	# reusing width for the height check).
	assert_true(body.contains("img.get_width()"),
		"_outlined_pixel must read img.get_width() for the X bounds")
	assert_true(body.contains("img.get_height()"),
		"_outlined_pixel must read img.get_height() for the Y bounds (NOT reuse width)")


func test_outlined_pixel_does_not_compare_py_to_width() -> void:
	# Pin against the regression of the legacy bug shape: a single `s`
	# local pulled from get_width() and then a `py < s` comparison. The
	# fix introduces distinct w / h locals so the wrong comparison can't
	# exist in non-comment code.
	var text := _read(SPRITE_UTILS_PATH)
	var idx := text.find("func _outlined_pixel")
	var rest := text.substr(idx)
	var next_fn := rest.find("\nstatic func ", 1)
	var body := rest.substr(0, next_fn) if next_fn > -1 else rest
	# Strip comments so the teaching doc that cites the legacy shape
	# doesn't trip its own lint.
	var lines := body.split("\n")
	var code_only: PackedStringArray = PackedStringArray()
	for line in lines:
		var ln: String = str(line)
		if ln.strip_edges().begins_with("#"):
			continue
		code_only.append(ln)
	var code := "\n".join(code_only)
	# The pre-fix code had `s = img.get_width()` and then `py < s`. The
	# fix's `w := img.get_width()` is fine; the buggy shape would be
	# `py < w` (since w replaces s). Either spelling is wrong because
	# py should compare against height. Assert no `py < w` in code.
	assert_false(code.contains("py < w"),
		"_outlined_pixel must NOT compare py against the width local — that's the bug. Should be `py < h`")
	# Belt and braces: the comparison `py < h` (the correct one) must appear.
	assert_true(code.contains("py < h"),
		"_outlined_pixel must compare py against the height local h")


# ── Behavioural ──────────────────────────────────────────────────────────────

const SpriteUtilsScript := preload("res://src/battle/sprites/SpriteUtils.gd")


func test_outlined_pixel_works_on_nonsquare_image() -> void:
	# Build a 32×48 (SNES party-sprite shape) image and call
	# _outlined_pixel at y=40 (would have been beyond width=32 pre-fix).
	# Assert no error and the center pixel is set.
	var img := Image.create(32, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# Target a row beyond width: y=40 (within height 48, beyond width 32).
	# Pre-fix `py < s=32` would have failed → no outline pixels drawn for
	# neighbors. The center pixel itself goes through _safe_pixel which
	# uses get_height() and would still set, but the surrounding outline
	# wouldn't draw correctly. We assert the function completes cleanly.
	SpriteUtilsScript._outlined_pixel(img, 16, 40, Color(1, 0, 0, 1))
	# The center pixel must be set (regardless of outline path).
	var center := img.get_pixel(16, 40)
	assert_almost_eq(center.r, 1.0, 0.001,
		"center pixel must be set to red after _outlined_pixel")
	assert_almost_eq(center.a, 1.0, 0.001,
		"center pixel must be opaque after _outlined_pixel")


func test_outlined_pixel_neighbor_outline_drawn_on_nonsquare() -> void:
	# Confirm the outline neighbors are also handled correctly on a
	# non-square image. With the pre-fix bug, neighbors below the
	# width-defined limit were inaccessible. The fix enables them.
	var img := Image.create(32, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# Center at (16, 40): py-1 = 39, py = 40, py+1 = 41. All > width 32
	# would have been mis-clipped pre-fix. Width is 32 so px ∈ {15, 16, 17}.
	SpriteUtilsScript._outlined_pixel(img, 16, 40, Color(1, 0, 0, 1))
	# Check a neighbor that's beyond the pre-fix width threshold: (16, 41).
	# Should be either the dark outline color OR transparent (the outline
	# only draws on transparent pixels per the function logic). What
	# matters is that the function ATTEMPTED the write without Godot
	# logging an out-of-bounds set_pixel call.
	var neighbor := img.get_pixel(16, 41)
	# The default outline_color has alpha 0.8. If outlining ran, this
	# pixel is set to the outline color (alpha > 0). If pre-fix clipped
	# it out, it'd be the initial transparent (alpha 0).
	assert_gt(neighbor.a, 0.0,
		"neighbor pixel below the pre-fix width clip must now be reached by the outline pass (alpha > 0)")
