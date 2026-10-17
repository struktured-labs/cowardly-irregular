extends GutTest

## The merchant's walk sprite is a bare-headed man in a GREEN apron; his dialogue portrait was a man in a red beret and
## a red coat, generated months apart from a different prompt. About thirty keepers and merchants speak with that
## face, and their shop screen shows it. The portrait is redrawn from the sprite (tools/match_portrait_to_walker.py).
## Measured here by the one thing both must share: what he wears is green, not red.

const SHEET := "res://assets/sprites/npcs/merchant/overworld.png"
const PORTRAIT := "res://assets/sprites/portraits/npcs/merchant.png"


func _img(path: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img != null:
		img.convert(Image.FORMAT_RGBA8)
	return img


func clothing(img: Image, region: Rect2i) -> Dictionary:
	## Shares of the region's opaque pixels that are clearly green and clearly red.
	var green := 0
	var red := 0
	var total := 0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			total += 1
			if c.g > c.r * 1.15 and c.g > c.b * 1.15:
				green += 1
			elif c.r > c.g * 1.6 and c.r > c.b * 1.6:
				red += 1
	return {"green": float(green) / maxf(1.0, float(total)), "red": float(red) / maxf(1.0, float(total)), "n": total}


func test_the_portrait_wears_what_the_sprite_wears() -> void:
	var sheet := _img(SHEET)
	var portrait := _img(PORTRAIT)
	assert_not_null(sheet, "CONTROL: the merchant's walk sheet is on disk")
	assert_not_null(portrait, "CONTROL: the merchant's portrait is on disk")
	if sheet == null or portrait == null:
		return
	# The torso band of a 32px cell (y 14-26), scaled to the sheet's own cell: 48px since the 2026-10-16 redraw.
	var cell := sheet.get_height() / 4
	var body := clothing(sheet, Rect2i(0, roundi(14.0 * cell / 32.0), cell, roundi(12.0 * cell / 32.0)))
	assert_gt(float(body["green"]), 0.25, "CONTROL: the sprite's torso is a green apron (%.2f green)" % body["green"])
	var bust := clothing(portrait, Rect2i(0, 170, 256, 86))
	assert_gt(int(bust["n"]), 4000, "CONTROL: the portrait has shoulders to measure")
	assert_gt(float(bust["green"]), 0.25, "the portrait's shoulders wear the green apron (%.2f green)" % bust["green"])
	# Brown leather and skin also read red-dominant (0.15 on the redrawn bust); the red coat measured 0.84.
	assert_lt(float(bust["red"]), 0.40, "and not a red coat (%.2f red)" % bust["red"])


func test_the_measure_tells_green_from_red() -> void:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color8(40, 120, 50))
	assert_gt(float(clothing(img, Rect2i(0, 0, 16, 16))["green"]), 0.9, "a green apron reads as green")
	img.fill(Color8(140, 40, 45))
	var r := clothing(img, Rect2i(0, 0, 16, 16))
	assert_gt(float(r["red"]), 0.9, "a red coat reads as red")
	assert_lt(float(r["green"]), 0.1)
