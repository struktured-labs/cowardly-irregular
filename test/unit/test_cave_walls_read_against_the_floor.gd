extends GutTest

## Regression (cowir-main's .605 Lightning Dragon Cave frame): cave walls (base 0.35) and floor (0.28) were the same
## dark texture a shade apart, so under dungeon lighting a maze floor read as one field and corridors were guesswork.
## Walls now sit well below the floor in brightness and carry a bright top rim, so every corridor edge reads.


func _tile(gen: TileGenerator, t: int, variant: int = 0) -> Image:
	var img := Image.create(TileGenerator.TILE_SIZE, TileGenerator.TILE_SIZE, false, Image.FORMAT_RGBA8)
	gen._draw_tile(img, t, TileGenerator.PALETTES[t], variant)
	return img


func _luma(img: Image, y0: int, y1: int) -> float:
	var sum := 0.0
	var n := 0
	for y in range(y0, y1):
		for x in range(img.get_width()):
			var c := img.get_pixel(x, y)
			sum += 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
			n += 1
	return sum / float(n)


func test_the_floor_is_clearly_brighter_than_the_wall_body() -> void:
	var gen := TileGenerator.new()
	var floor_l := 0.0
	var wall_l := 0.0
	for v in 4:
		floor_l += _luma(_tile(gen, TileGenerator.TileType.CAVE_FLOOR, v), 6, TileGenerator.TILE_SIZE) / 4.0
		wall_l += _luma(_tile(gen, TileGenerator.TileType.CAVE_WALL, v), 8, TileGenerator.TILE_SIZE - 7) / 4.0
	assert_gt(floor_l - wall_l, 0.12, "floor %.3f vs wall body %.3f: a maze needs its walls to read" % [floor_l, wall_l])


func test_a_wall_carries_a_bright_top_rim() -> void:
	var gen := TileGenerator.new()
	var img := _tile(gen, TileGenerator.TileType.CAVE_WALL)
	assert_gt(_luma(img, 0, 3), _luma(img, 8, TileGenerator.TILE_SIZE - 7) + 0.10, "the wall's top edge is lit, so a corridor's edge reads")
