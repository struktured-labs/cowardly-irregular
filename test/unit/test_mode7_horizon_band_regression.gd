extends GutTest

## 2026-07-05 playtest (struktured via cowir-adhoc): the Mode 7 horizon band
## rendered as an opaque solid-blue slab taking up ~55% of the screen.
##
## Root cause: the sky-side band height was `near_scale` (the SAME uniform that
## controls ground perspective). near_scale was raised 0.45→0.55 for the
## mountain-edge fix (4ebb4282), which unintentionally GREW the band. With
## horizon=0 in every preset, the band spanned the top ~55% of the screen,
## filled by mix(sky_bottom, fog_color, fog_t) — near-solid sky_bottom blue.
##
## Fix: dedicated `horizon_band` uniform (0.18) decoupled from near_scale. The
## band shrinks to a slim strip; Mode 7 distance-fogged terrain fills up toward
## a thinner horizon = atmospheric. near_scale stays 0.55 for ground perspective,
## so the mountain-edge fix is untouched. Band gradient thins toward the horizon.
##
## Pins: the decoupling, the slim default, the shader wiring, and — critically —
## that ground perspective still references near_scale (mountain-edge fix intact).

const MODE7_PATH := "res://src/exploration/Mode7Overlay.gd"
const SHADER_PATH := "res://src/shaders/mode7.gdshader"
const OverlayScript := preload("res://src/exploration/Mode7Overlay.gd")


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_horizon_band_defaults_to_slim_strip() -> void:
	var overlay = OverlayScript.new()
	assert_almost_eq(overlay.horizon_band, 0.18, 0.001,
		"horizon_band default must be the slim 0.18 strip, not the old ~0.55 slab")
	overlay.free()


func test_horizon_band_decoupled_from_near_scale() -> void:
	# The whole point of the fix: two independent vars. near_scale owns ground
	# perspective (0.55, from the mountain-edge fix); horizon_band owns only the
	# sky-side band height (0.18). They must not be the same value/field.
	var overlay = OverlayScript.new()
	assert_almost_eq(overlay.near_scale, 0.55, 0.001, "near_scale unchanged (ground perspective)")
	assert_ne(overlay.horizon_band, overlay.near_scale,
		"band height must be decoupled from near_scale — that coupling was the bug")
	overlay.free()


func test_shader_declares_horizon_band_uniform() -> void:
	var src := _read(SHADER_PATH)
	assert_true(src.contains("uniform float horizon_band"),
		"shader must expose a horizon_band uniform for the decoupled band height")


func test_shader_band_branch_uses_horizon_band_not_near_scale() -> void:
	# The band-region condition must gate on horizon_band. If it reverts to
	# `h_raw < near_scale` the slab is back.
	var src := _read(SHADER_PATH)
	assert_true(src.contains("h_raw < horizon_band"),
		"the sky-side band branch must cut off at horizon_band (slim strip), not near_scale (slab)")


func test_ground_perspective_still_uses_near_scale() -> void:
	# Guard the mountain-edge fix: the ground projection math must keep
	# near_scale. If the decoupling accidentally swapped these to horizon_band,
	# the perspective compression (and mountain-edge parity) would break.
	var src := _read(SHADER_PATH)
	assert_true(src.contains("float x_width = near_scale / h"),
		"ground horizontal projection must still use near_scale")
	assert_true(src.contains("near_scale * log("),
		"ground vertical projection must still use near_scale")


func test_overlay_plumbs_horizon_band() -> void:
	var src := _read(MODE7_PATH)
	assert_true(src.contains("horizon_band = float(preset[\"horizon_band\"])"),
		"apply_preset must read a per-world horizon_band override")
	assert_true(src.contains("set_shader_parameter(\"horizon_band\", horizon_band)"),
		"setup must push horizon_band to the shader material")


func test_preset_without_override_keeps_default() -> void:
	# The medieval preset (struktured's playtest world) carries no horizon_band
	# key, so applying it must leave the 0.18 default intact — worlds opt in to a
	# custom band, they don't lose it. Also confirms apply_preset doesn't crash on
	# the new key path.
	var overlay = OverlayScript.new()
	overlay.apply_preset("medieval")
	assert_almost_eq(overlay.horizon_band, 0.18, 0.001,
		"a preset with no horizon_band key must leave the 0.18 default")
	overlay.free()
