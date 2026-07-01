extends GutTest

## 2026-07-01 playtest tuning: user reported mountain-edge collision
## "leakage" — physics fires at the flat 2D tile edge, but Mode 7
## log() foreshortening makes the mountain look distant, so the wall
## reads as invisible.
##
## Root cause diagnosed by cowir-overworld (msg 2008): fundamental
## Mode 7 property, not a discrete bug. log(h) depth compression means
## no fixed collision margin can match at all distances.
##
## Option-1 fix (smallest surface, reversible): raise near_scale
## (less horizontal compression) + lower default & medieval curvature
## (less warp at the player). Steampunk/industrial/digital keep their
## per-world curvature — they have different intended feels.
##
## Pins the tuning values so a future edit that reverts them (or a
## refactor that silently drops the WORLD_PRESETS override) is caught.

const MODE7_PATH := "res://src/exploration/Mode7Overlay.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_default_near_scale_relaxed() -> void:
	var src := _read(MODE7_PATH)
	assert_true(src.contains("var near_scale: float = 0.55"),
		"default near_scale must be 0.55 (was 0.45 pre-tuning) — less horizontal compression → closer visual/physics parity on approach")


func test_default_curvature_softened() -> void:
	var src := _read(MODE7_PATH)
	assert_true(src.contains("var curvature: float = 0.005"),
		"default curvature must be 0.005 (was 0.01 pre-tuning) — less warp near player, better feel for new worlds added without their own preset")


func test_medieval_preset_matches_default() -> void:
	# Medieval was the world user was playtesting. Must have the
	# softened 0.005 (not the pre-tuning 0.01) because per-world
	# presets override the default at apply_world_preset time.
	var src := _read(MODE7_PATH)
	var idx: int = src.find("\"medieval\":")
	assert_gt(idx, -1)
	var window: String = src.substr(idx, 300)
	assert_true(window.contains("\"curvature\": 0.005"),
		"medieval world preset must set curvature = 0.005 to match the tuned default (per playtest report)")


func test_other_worlds_keep_their_curvature() -> void:
	# Steampunk (0.02), industrial (0.0), and digital (0.005) each
	# have deliberate feels. Confirm the tuning didn't accidentally
	# rewrite them.
	var src := _read(MODE7_PATH)
	var steampunk_idx: int = src.find("\"steampunk\":")
	var industrial_idx: int = src.find("\"industrial\":")
	assert_gt(steampunk_idx, -1)
	assert_gt(industrial_idx, -1)
	# Just spot-check that steampunk still has 0.02 and industrial still 0.0.
	var s_window: String = src.substr(steampunk_idx, 300)
	assert_true(s_window.contains("\"curvature\": 0.02"),
		"steampunk curvature must stay 0.02 — dense factory-town feel")
	var i_window: String = src.substr(industrial_idx, 300)
	assert_true(i_window.contains("\"curvature\": 0.0"),
		"industrial curvature must stay 0.0 — deliberately flat/oppressive")
