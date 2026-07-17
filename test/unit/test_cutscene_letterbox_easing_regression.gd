extends GutTest

## Cadence #11 (2026-07-16): cinematic easing for letterbox bar slide.
## letterbox_in / letterbox_out used linear tweens — bars slid at flat
## constant velocity, mechanical feel. Change to SINE ease-in-out default,
## matching PR #158 camera pan easing so a scene that opens with
## letterbox_in + camera_focus feels like one unified cinematic move.
##
## Same start / end / duration as pre-fix — only the middle velocity is
## eased. Existing scenes look better without any JSON change.
##
## Optional JSON step fields (parallel to camera_focus):
##   "ease":  "in_out" (default) | "in" | "out" | "linear"
##   "trans": "sine"   (default) | "quad" | "cubic" | "linear"


const DIRECTOR := "res://src/cutscene/CutsceneDirector.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_letterbox_ease_helper_exists_and_uses_sine_default() -> void:
	var src := _read(DIRECTOR)
	assert_gt(src.find("func _apply_letterbox_ease("), -1,
		"CutsceneDirector must have a _apply_letterbox_ease helper — mirrors PR #158's _run_camera_tween pattern")
	# Locate the helper body only so we don't false-positive on camera easing.
	var idx := src.find("func _apply_letterbox_ease(")
	var end := src.find("\nfunc ", idx + 1)
	var body := src.substr(idx, end - idx if end > -1 else 800)
	assert_gt(body.find("Tween.TRANS_SINE"), -1,
		"letterbox ease helper must default to Tween.TRANS_SINE — linear letterbox reads mechanical")
	assert_gt(body.find("Tween.EASE_IN_OUT"), -1,
		"letterbox ease helper must default to Tween.EASE_IN_OUT — smooth accel + settle is the cinema feel")


func test_letterbox_in_and_out_both_apply_ease() -> void:
	# Both step handlers must call the helper — a divergent implementation
	# means the "in" pan reveals slowly while the "out" pan snaps flat, or
	# vice versa. Consistency matters at frame transitions.
	var src := _read(DIRECTOR)
	var in_idx := src.find("func _step_letterbox_in(")
	assert_gt(in_idx, -1, "_step_letterbox_in must exist")
	var in_end := src.find("\nfunc ", in_idx + 1)
	var in_body := src.substr(in_idx, in_end - in_idx)
	assert_gt(in_body.find("_apply_letterbox_ease"), -1,
		"_step_letterbox_in must apply ease via the shared helper")

	var out_idx := src.find("func _step_letterbox_out(")
	assert_gt(out_idx, -1, "_step_letterbox_out must exist")
	var out_end := src.find("\nfunc ", out_idx + 1)
	var out_body := src.substr(out_idx, out_end - out_idx)
	assert_gt(out_body.find("_apply_letterbox_ease"), -1,
		"_step_letterbox_out must apply ease via the shared helper (letterbox_out was linear before this pin)")


func test_letterbox_helper_reads_optional_ease_and_trans_fields() -> void:
	var src := _read(DIRECTOR)
	var idx := src.find("func _apply_letterbox_ease(")
	var end := src.find("\nfunc ", idx + 1)
	var body := src.substr(idx, end - idx if end > -1 else 800)
	assert_gt(body.find('step.get("ease"'), -1,
		"helper must read the optional 'ease' field so authors can override")
	assert_gt(body.find('step.get("trans"'), -1,
		"helper must read the optional 'trans' field so authors can override")


func test_letterbox_skip_contract_still_snaps() -> void:
	# Skip contract: hold-B during a letterbox transition must apply the
	# final letterbox state instantly (no cinematic ease under skip).
	var src := _read(DIRECTOR)
	for step_name in ["_step_letterbox_in", "_step_letterbox_out"]:
		var idx := src.find("func %s(" % step_name)
		assert_gt(idx, -1, "%s must exist" % step_name)
		var end := src.find("\nfunc ", idx + 1)
		var body := src.substr(idx, end - idx)
		assert_gt(body.find("if _skipping:"), -1,
			"%s must keep its _skipping short-circuit — cinematic ease can't be awaited under skip" % step_name)
		assert_gt(body.find("_apply_letterbox("), -1,
			"%s must call _apply_letterbox() in the skip branch (hard snap to final state)" % step_name)
