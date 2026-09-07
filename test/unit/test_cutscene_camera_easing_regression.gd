extends GutTest

## Cadence #9 (2026-07-16): cinematic easing for cutscene camera pans.
## camera_focus + camera_restore were linear tweens (Godot's default) —
## film-flat feel. Change to SINE ease-in-out for smoother acceleration
## through the middle of the pan; complements cowir-battle's fable pass
## timing work. Existing scenes look better without change: same start /
## end / duration, just the speed profile through the middle is eased.
##
## Optional JSON step fields:
##   "ease":  "in_out" (default) | "in" | "out" | "linear"
##   "trans": "sine"   (default) | "quad" | "cubic" | "linear"


const DIRECTOR := "res://src/cutscene/CutsceneDirector.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_camera_helper_exists_and_uses_sine_ease_in_out_default() -> void:
	# Source-level pin: the shared _run_camera_tween helper must set the
	# default transition and ease. A refactor that dropped set_trans /
	# set_ease would silently revert to linear.
	var src := _read(DIRECTOR)
	assert_gt(src.find("func _run_camera_tween("), -1,
		"CutsceneDirector must have a shared _run_camera_tween helper")
	assert_gt(src.find("Tween.TRANS_SINE"), -1,
		"camera helper must default to Tween.TRANS_SINE — linear pans read flat/mechanical")
	assert_gt(src.find("Tween.EASE_IN_OUT"), -1,
		"camera helper must default to Tween.EASE_IN_OUT — smooth start + settle at target is the cinematic feel")


func test_camera_focus_and_restore_both_route_through_helper() -> void:
	# Both step handlers must use the shared helper — a divergent
	# implementation drifts the ease behavior between pan-out and pan-back.
	var src := _read(DIRECTOR)
	var focus_idx := src.find("func _step_camera_focus(")
	assert_gt(focus_idx, -1, "_step_camera_focus must exist")
	var focus_end := src.find("\nfunc ", focus_idx + 1)
	var focus_body := src.substr(focus_idx, focus_end - focus_idx)
	assert_gt(focus_body.find("_run_camera_tween"), -1,
		"_step_camera_focus must route through _run_camera_tween helper")

	var restore_idx := src.find("func _step_camera_restore(")
	assert_gt(restore_idx, -1, "_step_camera_restore must exist")
	var restore_end := src.find("\nfunc ", restore_idx + 1)
	var restore_body := src.substr(restore_idx, restore_end - restore_idx)
	assert_gt(restore_body.find("_run_camera_tween"), -1,
		"_step_camera_restore must route through _run_camera_tween helper")


func test_camera_helper_reads_optional_ease_and_trans_fields() -> void:
	# Optional author override — scene JSON can pin a specific curve
	# (e.g. "ease": "out" for a punchy zoom-in beat).
	var src := _read(DIRECTOR)
	var helper_idx := src.find("func _run_camera_tween(")
	assert_gt(helper_idx, -1)
	var helper_end := src.find("\nfunc ", helper_idx + 1)
	var body := src.substr(helper_idx, helper_end - helper_idx if helper_end > -1 else 800)
	assert_gt(body.find('step.get("ease"'), -1,
		"helper must read the optional 'ease' field from the step")
	assert_gt(body.find('step.get("trans"'), -1,
		"helper must read the optional 'trans' field from the step")


func test_camera_helper_still_skip_snaps() -> void:
	# Skip-contract preservation: hold-B during a pan must snap the camera
	# to its target. Focus and restore both keep their own _skipping
	# short-circuit before calling the helper (the helper is the smooth path).
	var src := _read(DIRECTOR)
	var focus_idx := src.find("func _step_camera_focus(")
	var focus_body := src.substr(focus_idx, src.find("\nfunc ", focus_idx + 1) - focus_idx)
	assert_gt(focus_body.find("if _skipping:"), -1,
		"_step_camera_focus must keep its _skipping short-circuit — cinematic ease can't be awaited under skip")
	var restore_idx := src.find("func _step_camera_restore(")
	var restore_body := src.substr(restore_idx, src.find("\nfunc ", restore_idx + 1) - restore_idx)
	assert_gt(restore_body.find("if _skipping:"), -1,
		"_step_camera_restore must keep its _skipping short-circuit + hard offset snap")
