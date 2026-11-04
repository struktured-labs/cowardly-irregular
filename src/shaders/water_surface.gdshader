shader_type canvas_item;
// Moving water on the drawn WATER tile (struktured 2026-11-01: the water "looks like just lighting"). Everything is in
// whole pixels and whole time steps, so it stays pixel art: the tile's own pattern drifts inside its atlas cell, a band
// of glints travels across the surface, and rings spread from ripple_center (a fountain), fading with distance.

uniform vec4 region;                                  // this tile's atlas rect in UV: xy origin, zw size
uniform vec2 tile_px = vec2(32.0, 32.0);
uniform vec2 ripple_center = vec2(-100000.0, -100000.0);
uniform float step_hz = 8.0;
uniform vec3 foam = vec3(0.86, 0.94, 1.0);

varying vec2 world;

void vertex() {
	world = VERTEX;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float t = floor(TIME * step_hz) / step_hz;
	vec2 local = (UV - region.xy) / region.zw;
	vec2 px = floor(local * tile_px);
	vec2 drift = floor(vec2(t * 4.0, t * 2.0));
	vec2 src = mod(px + drift, tile_px);
	vec4 c = texture(TEXTURE, region.xy + (src + 0.5) / tile_px * region.zw);
	vec2 p = floor(world);
	float band = sin((p.x * 0.6 + p.y * 1.4) * 0.08 - t * 2.5);
	float glint = step(0.96, band) * step(0.55, hash(p));
	vec2 dv = (p - ripple_center) * vec2(1.0, 2.2);
	float d = length(dv);
	float ring = step(0.86, fract(d / 12.0 - t * 0.8)) * clamp(1.0 - d / 140.0, 0.0, 1.0);
	c.rgb = mix(c.rgb, foam, clamp(glint * 0.85 + ring * 0.5, 0.0, 0.9));
	COLOR = c;
}
