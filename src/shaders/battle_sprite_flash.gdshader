shader_type canvas_item;
// True white/element flash + chunky pixel dissolve for battle sprites — modulate tints can't reach white on dark pixels, and dissolve gives deaths an SNES-style exit. WebGL2-safe (in-shader hash, no derivatives).

uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.0;
uniform float dissolve_grid = 48.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	// COLOR arrives as texture * modulate, so existing tints keep composing under the flash
	vec4 base = COLOR;
	base.rgb = mix(base.rgb, flash_color.rgb, flash_amount * flash_color.a);
	float n = hash21(floor(UV * dissolve_grid));
	base.a *= step(dissolve_amount, n);
	COLOR = base;
}
