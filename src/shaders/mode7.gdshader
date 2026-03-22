shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float horizon : hint_range(0.0, 0.5) = 0.0;
uniform float near_scale : hint_range(0.05, 0.5) = 0.12;
uniform float ground_y : hint_range(0.3, 0.95) = 0.59;
uniform float curvature : hint_range(0.0, 0.2) = 0.02;
uniform float world_rotation : hint_range(-3.14159, 3.14159) = 0.0;
uniform vec4 sky_top : source_color = vec4(0.25, 0.35, 0.65, 1.0);
uniform vec4 sky_bottom : source_color = vec4(0.55, 0.65, 0.85, 1.0);
uniform vec4 fog_color : source_color = vec4(0.50, 0.60, 0.78, 1.0);

void fragment() {
	vec2 uv = SCREEN_UV;
	vec4 result;

	float h_raw = uv.y - horizon;

	if (h_raw <= 0.0) {
		float sky_t = uv.y / max(horizon, 0.001);
		result = mix(sky_top, sky_bottom, sky_t);
	} else if (h_raw < near_scale) {
		result = fog_color;
	} else {
		float h = h_raw;

		float x_width = near_scale / h;
		float depth = 1.0 - h;
		float planet = 1.0 - curvature * depth * depth;
		float sx = (uv.x - 0.5) * x_width * planet + 0.5;

		float sy = ground_y + near_scale * log(h);

		// Rotate sample coords around camera center in texture space
		float cr = cos(world_rotation);
		float sr = sin(world_rotation);
		float dx = sx - 0.5;
		float dy = sy - ground_y;
		sx = dx * cr - dy * sr + 0.5;
		sy = dx * sr + dy * cr + ground_y;

		float edge_x = smoothstep(0.0, 0.015, sx) * smoothstep(1.0, 0.985, sx);
		float edge_y = smoothstep(0.0, 0.015, sy);
		float edge = edge_x * edge_y;

		vec2 sample_uv = clamp(vec2(sx, sy), vec2(0.0), vec2(1.0));
		vec4 tex = texture(screen_tex, sample_uv);

		result = mix(fog_color, tex, edge);

		float fade_zone = near_scale * 0.5;
		if (h_raw < near_scale + fade_zone) {
			float t = (h_raw - near_scale) / fade_zone;
			result = mix(fog_color, result, smoothstep(0.0, 1.0, t));
		}
	}

	COLOR = result;
}
