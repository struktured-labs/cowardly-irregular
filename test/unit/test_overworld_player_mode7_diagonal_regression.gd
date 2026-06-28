extends GutTest

## tick 348: OverworldPlayer gates its Mode 7 horizontal-compensation
## (input_dir.x *= 2.0) on Mode7Overlay.is_active.
##
## Pre-fix the 2x X-boost fired UNCONDITIONALLY before normalize.
## In Mode 7 contexts (overworlds with the shader on), this compensates
## for the shader's horizontal compression so axis-aligned motion
## feels equal. In non-Mode-7 contexts (villages, interiors, flat-
## camera dungeons), there's no compression to compensate for — so
## the 2x boost makes diagonal movement bias toward horizontal.
## Diagonal up-right visibly walked more right than up because
## input_dir.x got pre-normalize boosted to 2x while y stayed at 1x:
##   raw (1,1) → boost (2,1) → normalize (0.894, 0.447)
##
## Symptom: "movement in villages feels weird — my character drifts
## sideways when I try to walk diagonally upward."
##
## Fix: add Mode7Overlay.is_active static flag set by apply_camera,
## gate the boost on it. is_active defaults to false so pure non-
## Mode-7 launches (test runs, fresh game in a village before any
## overworld load) don't apply the boost.

const MODE7_PATH := "res://src/exploration/Mode7Overlay.gd"
const PLAYER_PATH := "res://src/exploration/OverworldPlayer.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: is_active flag exists on Mode7Overlay ───────────────

func test_is_active_flag_exists() -> void:
	var src := _read(MODE7_PATH)
	assert_true(src.contains("static var is_active: bool"),
		"Mode7Overlay must declare static is_active flag")


# ── Source pin: apply_camera sets the flag ──────────────────────────

func test_apply_camera_sets_flag() -> void:
	var src := _read(MODE7_PATH)
	var fn_idx: int = src.find("static func apply_camera")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nstatic func ", fn_idx + 1)
	if next_fn < 0:
		next_fn = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("is_active = mode7"),
		"apply_camera must mirror the mode7 param to is_active so OverworldPlayer can gate its boost")


# ── Source pin: OverworldPlayer gates boost on is_active ────────────

func test_player_gates_x_boost() -> void:
	var src := _read(PLAYER_PATH)
	# Find the input_dir.x boost site.
	var boost_idx: int = src.find("input_dir.x *= 2.0")
	assert_gt(boost_idx, -1, "the X-boost line must still exist")
	# Slice 200 chars before to capture the if-guard.
	var before: String = src.substr(maxi(0, boost_idx - 200), 200)
	assert_true(before.contains("Mode7Overlay.is_active"),
		"input_dir.x *= 2.0 must be guarded by `if Mode7Overlay.is_active`")


# ── Behavioral: flag toggles correctly via apply_camera ─────────────

func test_apply_camera_toggles_is_active() -> void:
	# Use a dummy Camera2D — we only care about the flag, not the
	# zoom/offset side-effects.
	var cam := Camera2D.new()
	add_child_autofree(cam)

	# Snapshot.
	var prior: bool = Mode7Overlay.is_active

	Mode7Overlay.apply_camera(cam, true)
	assert_true(Mode7Overlay.is_active,
		"apply_camera(cam, true) must set is_active to true")

	Mode7Overlay.apply_camera(cam, false)
	assert_false(Mode7Overlay.is_active,
		"apply_camera(cam, false) must set is_active to false")

	# Restore.
	Mode7Overlay.is_active = prior


# ── Behavioral: default is false (safe for non-overworld launches) ──

func test_default_is_false() -> void:
	# Source pin — Godot may have static-var ordering issues otherwise.
	var src := _read(MODE7_PATH)
	assert_true(src.contains("static var is_active: bool = false"),
		"is_active must default to false so pure non-Mode-7 launches don't accidentally enable the boost")
