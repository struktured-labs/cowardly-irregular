shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float horizon : hint_range(0.0, 0.5) = 0.0;
uniform float near_scale : hint_range(0.05, 0.5) = 0.22;
uniform float ground_y : hint_range(0.3, 0.95) = 0.52;
uniform float curvature : hint_range(0.0, 0.2) = 0.01;
// Camera rotation now driven by Camera2D.rotation instead of UV-space rotation.
// This eliminates texture sampling degradation past ~180 degrees.
// Kept as uniform for optional effects (wobble, shake) but not used for main yaw.
uniform float world_rotation = 0.0;
uniform vec4 sky_top : source_color = vec4(0.25, 0.35, 0.65, 1.0);
uniform vec4 sky_bottom : source_color = vec4(0.55, 0.65, 0.85, 1.0);
uniform vec4 fog_color : source_color = vec4(0.50, 0.60, 0.78, 1.0);
// Day/night tint (multiplied with final color)
uniform vec4 time_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Per-world effects (default 0.0 = inactive)
uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float dissolve_progress : hint_range(0.0, 1.0) = 0.0;
// Parallax sky clouds
uniform float cloud_density : hint_range(0.0, 1.0) = 0.0;
uniform vec4 cloud_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float cloud_scroll : hint_range(0.0, 1000.0) = 0.0;

// Simple value noise for clouds
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float cloud_fbm(vec2 p) {
	float v = 0.0;
	v += 0.5 * vnoise(p); p *= 2.01;
	v += 0.25 * vnoise(p); p *= 2.02;
	v += 0.125 * vnoise(p);
	return v;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec4 result;

	float h_raw = uv.y - horizon;

	if (h_raw <= 0.0) {
		float sky_t = uv.y / max(horizon, 0.001);
		result = mix(sky_top, sky_bottom, sky_t);
		// Parallax clouds in sky region
		if (cloud_density > 0.0) {
			vec2 cloud_uv = vec2(uv.x * 4.0 + cloud_scroll * 0.1, sky_t * 2.0 + cloud_scroll * 0.02);
			float clouds = cloud_fbm(cloud_uv);
			float cloud_mask = smoothstep(0.4, 0.7, clouds) * cloud_density;
			cloud_mask *= smoothstep(0.0, 0.3, sky_t) * smoothstep(1.0, 0.7, sky_t);
			result = mix(result, cloud_color, cloud_mask * 0.6);
		}
	} else if (h_raw < near_scale) {
		// Smooth gradient from sky_bottom → fog_color near horizon
		float fog_t = smoothstep(0.0, near_scale, h_raw);
		result = mix(sky_bottom, fog_color, fog_t);
	} else {
		float h = h_raw;

		float x_width = near_scale / h;
		float depth = 1.0 - h;
		float planet = 1.0 - curvature * depth * depth;
		float sx = (uv.x - 0.5) * x_width * planet + 0.5;

		float sy = ground_y + near_scale * log(max(h, 0.001));

		// Camera yaw is now driven by Camera2D.rotation — no UV rotation needed.
		// This fixes texture sampling degradation past ~180 degrees.

		float edge_x = smoothstep(0.0, 0.06, sx) * smoothstep(1.0, 0.94, sx);
		float edge_y = smoothstep(0.0, 0.06, sy);
		float edge = edge_x * edge_y;

		vec2 sample_uv = clamp(vec2(sx, sy), vec2(0.0), vec2(1.0));
		vec4 tex = texture(screen_tex, sample_uv);

		result = mix(fog_color, tex, edge);

		// Distance fog: far ground (small h, near horizon) fades toward fog_color
		// h ranges from near_scale (horizon) to ~1.0 (camera feet)
		float ground_range = 1.0 - near_scale;
		float dist_t = 1.0 - clamp((h - near_scale) / ground_range, 0.0, 1.0);
		float fog_amount = dist_t * dist_t * 0.7;  // Quadratic falloff, max 70% fog
		result = mix(result, fog_color, fog_amount);

		// Horizon fade zone (smooth transition from fog band to ground)
		float fade_zone = near_scale * 0.5;
		if (h_raw < near_scale + fade_zone) {
			float t = (h_raw - near_scale) / fade_zone;
			result = mix(fog_color, result, smoothstep(0.0, 1.0, t));
		}
	}

	// Scanline effect (W5 Digital: CRT/terminal aesthetic)
	if (scanline_intensity > 0.0) {
		float scanline = mod(FRAGCOORD.y, 2.0) < 1.0 ? 1.0 : 1.0 - scanline_intensity;
		result.rgb *= scanline;
	}

	// Dissolve effect (W5→W6 transition: perspective fragmenting)
	if (dissolve_progress > 0.0) {
		float noise = fract(sin(dot(uv * 43.0, vec2(12.9898, 78.233))) * 43758.5453);
		if (noise < dissolve_progress) {
			result = fog_color;
		}
		// Flatten perspective as dissolve progresses
		result = mix(result, fog_color, dissolve_progress * 0.5);
	}

	// Day/night tint
	result.rgb *= time_tint.rgb;

	COLOR = result;
}
