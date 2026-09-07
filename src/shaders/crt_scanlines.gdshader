// CRT scanline overlay — emulates horizontal scanlines of a tube monitor.
// Previously implemented as ~120 ColorRect nodes per viewport; one shader
// uniform now does the same job with a single draw call.
shader_type canvas_item;

// Spacing between dark lines, measured in pixels of the rendered surface.
// Default 3 matches the original per-third-row ColorRect pattern.
uniform float line_spacing : hint_range(1.0, 8.0) = 3.0;

// Opacity of each dark line (0.0 = invisible, 1.0 = opaque black).
uniform float line_intensity : hint_range(0.0, 1.0) = 0.18;

void fragment() {
	// SCREEN_PIXEL_SIZE.y would sample viewport size; use FRAGCOORD.y for
	// pixel-accurate vertical banding regardless of scaling.
	float row = floor(FRAGCOORD.y);
	// mod() is stable here because line_spacing is >= 1.0 by hint_range.
	float darken = (mod(row, line_spacing) < 1.0) ? line_intensity : 0.0;
	COLOR = vec4(0.0, 0.0, 0.0, darken);
}
