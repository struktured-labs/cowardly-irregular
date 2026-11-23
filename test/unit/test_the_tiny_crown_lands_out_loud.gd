extends GutTest

## The briefing-skipped scene turns on a very small crown landing (cowir-main 24231): the prop that shows it names the cue
## on its LANDING frame (cutscenes 24250), the cue exists, and it is over before the Elder speaks.

const SCENE := "res://data/cutscenes/world1_briefing_skipped.json"
const MANIFEST := "res://data/sfx_manifest.json"
const SPRITES := "res://data/sprite_manifest.json"
const CUE := "scene_tiny_crown_lands"
const PROP := "tiny_crown"


func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(parsed is Dictionary, "VOID: %s did not parse" % path)
	return parsed if parsed is Dictionary else {}


func _steps() -> Array:
	return _json(SCENE).get("steps", [])


## Index of the step that shows the crown, or -1.
func _crown_step(steps: Array) -> int:
	for i in steps.size():
		if steps[i] is Dictionary and str(steps[i].get("type", "")) == "show_prop" and str(steps[i].get("prop", "")) == PROP:
			return i
	return -1


func test_the_crown_names_its_cue_once_and_the_cue_loads() -> void:
	var steps := _steps()
	assert_gt(steps.size(), 0, "PREMISE: the scene has steps")
	var named: Array[String] = []
	for step in steps:
		if step is Dictionary and str(step.get("sfx", "")) != "":
			named.append("%s:%s" % [str(step.get("type", "")), str(step.get("sfx", ""))])
	assert_eq(named, ["show_prop:" + CUE] as Array[String], "the scene's one sound is the crown, played by the prop that shows it; no loose step plays it twice and the Elder's lines stay bare")
	var sfx: Dictionary = _json(MANIFEST).get("sfx", {})
	assert_true(sfx.has(CUE), "%s is in the manifest, or the crown lands in silence" % CUE)
	assert_true(ResourceLoader.exists("res://" + str((sfx.get(CUE, {}) as Dictionary).get("file", ""))), "%s loads" % CUE)


## The ring belongs to the frame the crown touches the rim, not to the frame it is still falling on.
func test_the_cue_is_on_the_landing_frame() -> void:
	var steps := _steps()
	var at := _crown_step(steps)
	assert_gt(at, 0, "PREMISE: a show_prop step shows the crown, after the line that names it")
	if at <= 0:
		return
	assert_true("crown" in str((steps[at - 1] as Dictionary).get("text", "")).to_lower(), "the step before it is the line that names the crown")
	var row: Dictionary = (_json(SPRITES).get("prop_art", {}) as Dictionary).get(PROP, {})
	assert_gt(int(row.get("frames", 0)), 1, "PREMISE: the crown is a strip of frames")
	var frame := int((steps[at] as Dictionary).get("sfx_at_frame", 0))
	assert_gt(frame, 0, "frame 0 is the crown still in the air: a cue there sounds before it lands")
	assert_lt(frame, int(row.get("frames", 0)), "the landing frame is one the strip has")


func test_the_crown_has_stopped_before_he_speaks() -> void:
	var steps := _steps()
	var at := _crown_step(steps)
	assert_gt(at, 0, "PREMISE: the crown step exists")
	if at <= 0 or at + 1 >= steps.size():
		return
	var next: Dictionary = steps[at + 1]
	assert_eq(str(next.get("type", "")), "wait", "a beat of quiet follows the crown")
	var sfx: Dictionary = _json(MANIFEST).get("sfx", {})
	var d := float((sfx.get(CUE, {}) as Dictionary).get("duration_seconds", 0.0))
	assert_gt(d, 0.0, "PREMISE: the cue has an authored length")
	var row: Dictionary = (_json(SPRITES).get("prop_art", {}) as Dictionary).get(PROP, {})
	var fps := float(row.get("fps", 0.0))
	assert_gt(fps, 0.0, "PREMISE: the strip has a frame rate")
	if fps <= 0.0:
		return
	var lands_at := float(int((steps[at] as Dictionary).get("sfx_at_frame", 0))) / fps
	assert_lte(lands_at + d, float(next.get("duration", 0.0)), "the crown lands at %.3f s and rings %.2f s: it must be over inside the wait" % [lands_at, d])
	var s = load("res://" + str((sfx.get(CUE, {}) as Dictionary).get("file", "")))
	if s:
		assert_almost_eq(s.get_length(), d, 0.05, "its authored duration describes the asset")
