extends GutTest

## Friend playtest 2026-07-03: "the horizon fog is a bit too heavy-
## handed." Two stacked fog sources both maxed to 100% at the horizon —
## the quadratic distance fog capped at 0.7, and the horizon band's mix
## started at pure fog. Fog is now a single tuned dial (fog_strength,
## default 0.45) that scales BOTH sources, and the band is narrower.
## Per-world presets can override for genuinely dense worlds.


func _shader_src() -> String:
	return FileAccess.get_file_as_string("res://src/shaders/mode7.gdshader")


func test_shader_exposes_fog_strength_dial() -> void:
	var s := _shader_src()
	assert_true(s.contains("uniform float fog_strength"),
		"the fog dial must be a uniform so per-world presets can override without a shader edit")


func test_distance_fog_scales_by_fog_strength_not_hardcoded_0_7() -> void:
	var s := _shader_src()
	assert_false(s.contains("* 0.7;"),
		"hardcoded 0.7 max was the too-heavy default — replaced with the fog_strength dial")
	assert_true(s.contains("dist_t * dist_t * fog_strength"),
		"distance fog must scale by the dial")


func test_horizon_band_narrowed_and_dial_gated() -> void:
	# 2026-07-05: the horizon-band HEIGHT is now the dedicated `horizon_band`
	# uniform (decoupled from near_scale — that coupling made it a ~55% slab
	# after the mountain-edge fix raised near_scale to 0.55). Fade zone anchors
	# to horizon_band. The fog_strength-dial gating is preserved.
	var s := _shader_src()
	assert_true(s.contains("horizon_band * 1.5"),
		"horizon fade zone must anchor to horizon_band (the decoupled band height), not near_scale")
	assert_true(s.contains("(1.0 - fog_strength)"),
		"the horizon-band mix must respect fog_strength or the two dials fight each other")


func test_sky_side_band_also_scales_by_fog_strength() -> void:
	# 2026-07-04: sky-side band gained fog_strength scaling so it isn't a hard
	# 100%-fog strip. 2026-07-05: the band's smoothstep now spans the slim
	# `horizon_band` (0.18) instead of near_scale (0.55) — same dial gating, but
	# the gradient reads over an 18% strip, not a 55% slab (user re-flagged the
	# height). fog_strength scaling retained.
	var s := _shader_src()
	assert_true(s.contains("smoothstep(0.0, horizon_band, h_raw) * fog_strength"),
		"sky-side fog_t must scale by fog_strength over the slim horizon_band, not the tall near_scale")


func test_overlay_pushes_the_fog_strength_uniform() -> void:
	var g := FileAccess.get_file_as_string("res://src/exploration/Mode7Overlay.gd")
	assert_true(g.contains("set_shader_parameter(\"fog_strength\""),
		"Mode7Overlay must push fog_strength or the shader default is the only value that ever ships")
	assert_true(g.contains("preset[\"fog_strength\"]"),
		"per-world presets must be able to override the dial")
