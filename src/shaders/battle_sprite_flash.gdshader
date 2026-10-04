shader_type canvas_item;
// True white/element flash + chunky pixel dissolve for battle sprites — modulate tints can't reach white on dark pixels, and dissolve gives deaths an SNES-style exit. WebGL2-safe (in-shader hash, no derivatives).
// Secondary-job accent: the artist palette entries a sheet names (manifest "secondary_accent") lean toward the secondary job's colour, shading kept. Off at accent_count 0; no other pixel is touched.

uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.0;
uniform float dissolve_grid = 48.0;
uniform int accent_count = 0;
uniform vec3 accent_from[8];
uniform vec4 accent_to : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float accent_amount : hint_range(0.0, 1.0) = 0.0;
uniform float accent_tolerance = 0.04;
// Luma of the brightest named entry: that shade becomes the full target colour and the rest of the ramp scales with it
uniform float accent_peak = 1.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

varying vec4 v_modulate;

void vertex() {
	// modulate x self_modulate, so a recoloured pixel keeps the status tints and fades the rest of the sprite gets
	v_modulate = COLOR;
}

void fragment() {
	// COLOR arrives as texture * modulate, so existing tints keep composing under the flash
	vec4 base = COLOR;
	if (accent_count > 0 && accent_amount > 0.0) {
		vec4 art = texture(TEXTURE, UV);
		bool hit = false;
		for (int i = 0; i < 8; i++) {
			if (i < accent_count && distance(art.rgb, accent_from[i]) <= accent_tolerance) {
				hit = true;
			}
		}
		if (hit) {
			// The artist's ramp, rescaled onto the target: his highlight becomes the target colour, his shadows its shadows
			vec3 lit = clamp(accent_to.rgb * (luma(art.rgb) / max(accent_peak, 0.05)), 0.0, 1.0);
			base.rgb = mix(base.rgb, lit * v_modulate.rgb, accent_amount);
		}
	}
	base.rgb = mix(base.rgb, flash_color.rgb, flash_amount * flash_color.a);
	float n = hash21(floor(UV * dissolve_grid));
	base.a *= step(dissolve_amount, n);
	COLOR = base;
}
