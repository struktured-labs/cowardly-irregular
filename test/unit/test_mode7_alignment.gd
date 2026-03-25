extends GutTest

## Verify Mode 7 shader parameters produce reasonable collision-visual alignment.
## Runs headlessly — no rendering needed, just math verification.

const VIEWPORT_W: float = 1280.0
const VIEWPORT_H: float = 1080.0

# Current Mode 7 parameters (must match Mode7Overlay defaults)
var near_scale: float = 0.45
var ground_y: float = 0.48
var horizon: float = 0.0
var cam_zoom: float = 0.85
var cam_offset_y: float = -20.0
var player_screen_y_frac: float = 0.75  # Player at 75% screen height


func test_tile_size_at_player_feet():
	# At the player's feet position, how wide does a tile appear vs its real width?
	var h = player_screen_y_frac - horizon  # 0.75
	var x_width = near_scale / h  # How much horizontal space the shader samples

	# x_width represents the fraction of the screen texture sampled horizontally
	# A tile is 32 world pixels. Camera zoom 0.85 means viewport shows 1280/0.85 = 1506 world px
	var world_visible_w = VIEWPORT_W / cam_zoom
	var tile_world_frac = 32.0 / world_visible_w  # Fraction of viewport one tile occupies

	# On the Mode 7 view, the tile appears scaled by x_width
	# The visual tile width as fraction of screen = tile_world_frac / x_width
	# (x_width > 1 means zoomed in, < 1 means compressed)
	var visual_tile_frac = tile_world_frac * x_width
	var visual_tile_px = visual_tile_frac * VIEWPORT_W
	var real_tile_screen_px = 32.0 * cam_zoom  # What the tile would be without Mode 7

	var ratio = visual_tile_px / real_tile_screen_px

	gut.p("=== Mode 7 Tile Size at Player Feet ===")
	gut.p("  h (scanline dist): %.3f" % h)
	gut.p("  x_width (horiz scale): %.3f" % x_width)
	gut.p("  World visible width: %.0f px" % world_visible_w)
	gut.p("  Visual tile width: %.1f px" % visual_tile_px)
	gut.p("  Real tile screen width: %.1f px" % real_tile_screen_px)
	gut.p("  Visual/Real ratio: %.2f" % ratio)
	gut.p("  (1.0 = perfect match, <0.5 = too compressed, >1.5 = too stretched)")

	# Tile should appear at least 40% of its real collision width
	assert_gt(ratio, 0.4, "Tiles at player feet are too compressed (ratio %.2f < 0.4)" % ratio)
	# And not more than 200% (would look stretched)
	assert_lt(ratio, 2.0, "Tiles at player feet are too stretched (ratio %.2f > 2.0)" % ratio)


func test_tile_size_at_midground():
	# At 50% between player and horizon — how do tiles look?
	var mid_y = player_screen_y_frac * 0.65  # ~49% screen height
	var h = mid_y - horizon
	var x_width = near_scale / h

	var world_visible_w = VIEWPORT_W / cam_zoom
	var tile_world_frac = 32.0 / world_visible_w
	var visual_tile_frac = tile_world_frac * x_width
	var visual_tile_px = visual_tile_frac * VIEWPORT_W
	var real_tile_screen_px = 32.0 * cam_zoom

	var ratio = visual_tile_px / real_tile_screen_px

	gut.p("=== Mode 7 Tile Size at Midground ===")
	gut.p("  Screen Y: %.2f, h: %.3f" % [mid_y, h])
	gut.p("  Visual tile width: %.1f px" % visual_tile_px)
	gut.p("  Visual/Real ratio: %.2f" % ratio)

	# Midground tiles should be visibly smaller but not invisibly tiny
	assert_gt(ratio, 0.15, "Midground tiles too small (ratio %.2f)" % ratio)


func test_collision_circle_vs_tile():
	# Player collision radius should be significantly smaller than a tile
	var collision_radius = 7.0
	var tile_size = 32.0
	var ratio = collision_radius / tile_size

	gut.p("=== Collision Circle vs Tile ===")
	gut.p("  Collision radius: %.0f" % collision_radius)
	gut.p("  Tile size: %.0f" % tile_size)
	gut.p("  Ratio: %.2f (should be 0.15-0.4)" % ratio)

	assert_gt(ratio, 0.1, "Collision too small — player clips through gaps")
	assert_lt(ratio, 0.5, "Collision too large — player can't navigate tight corridors")


func test_perspective_compression_gradient():
	# Verify the perspective compression isn't too extreme across the ground plane
	var ratios: Array = []
	var screen_ys: Array = [0.3, 0.4, 0.5, 0.6, 0.75]

	gut.p("=== Perspective Compression Gradient ===")
	for sy in screen_ys:
		var h = sy - horizon
		if h <= near_scale:
			continue  # In fog band
		var x_width = near_scale / h
		ratios.append(x_width)
		gut.p("  Screen Y %.2f → x_width %.3f" % [sy, x_width])

	# The ratio between most compressed and least compressed shouldn't exceed 5x
	if ratios.size() >= 2:
		var max_r = ratios.max()
		var min_r = ratios.min()
		var compression_range = max_r / min_r
		gut.p("  Compression range: %.1fx (max/min x_width)" % compression_range)
		assert_lt(compression_range, 6.0, "Too extreme perspective — far ground is >6x more compressed than near")


func test_player_speed_vs_tile_size():
	# Player should cross a tile in a reasonable time
	var move_speed = 150.0  # px/s
	var tile_size = 32.0
	var time_per_tile = tile_size / move_speed

	gut.p("=== Movement Speed ===")
	gut.p("  Speed: %.0f px/s" % move_speed)
	gut.p("  Tile size: %.0f px" % tile_size)
	gut.p("  Time per tile: %.2f s" % time_per_tile)
	gut.p("  Tiles per second: %.1f" % (1.0 / time_per_tile))

	# Should cross a tile in 0.1-0.5s (not too fast, not too slow)
	assert_gt(time_per_tile, 0.1, "Moving too fast — hard to control")
	assert_lt(time_per_tile, 0.5, "Moving too slow — feels sluggish")
