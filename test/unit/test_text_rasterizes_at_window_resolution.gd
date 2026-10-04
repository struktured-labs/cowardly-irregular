extends GutTest

## Regression (struktured 2026-10-03): "some of the fonts are crap in battle, like the description of the ability below the menu is hard to read … look for aliasing across the board".
## Under stretch mode "viewport" every glyph was rasterized at 1280x720 and the frame was then nearest-upscaled (2x on his 1440p screens, 1.5x at 1080p),
## so small antialiased text came out soft and blocky on every surface. "canvas_items" keeps the 1280x720 layout but rasterizes text at window resolution.


func test_the_window_stretches_canvas_items_not_a_720p_frame() -> void:
	assert_eq(str(ProjectSettings.get_setting("display/window/stretch/mode")), "canvas_items",
		"stretch mode \"viewport\" rasterizes all text at 720p and upscales the frame; keep \"canvas_items\"")
	assert_eq(int(ProjectSettings.get_setting("display/window/size/viewport_width")), 1280, "SCOPE: the design canvas stays 1280 wide")
	assert_eq(int(ProjectSettings.get_setting("display/window/size/viewport_height")), 720, "SCOPE: the design canvas stays 720 tall")


func test_the_scanline_overlay_counts_game_pixels_not_window_pixels() -> void:
	var sh: Shader = load("res://src/shaders/crt_scanlines.gdshader")
	assert_not_null(sh, "SCOPE: the scanline shader loads")
	var code := sh.code
	assert_true(code.contains("FRAGCOORD.y * SCREEN_PIXEL_SIZE.y * canvas_height"),
		"under canvas_items FRAGCOORD counts window pixels; rows must convert back to game pixels or a 1440p window draws the lines half as thick")
	var src := FileAccess.get_file_as_string("res://src/ui/autogrind/AutogrindDashboard.gd")
	assert_true(src.contains("set_shader_parameter(\"canvas_height\""), "the dashboard must hand the shader the design height")
