extends GutTest

## The briefing-skipped scene turns on a very small crown landing (cowir-main 24231): the step names a cue, and the cue exists.

const SCENE := "res://data/cutscenes/world1_briefing_skipped.json"
const MANIFEST := "res://data/sfx_manifest.json"
const CUE := "scene_tiny_crown_lands"


func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(parsed is Dictionary, "VOID: %s did not parse" % path)
	return parsed if parsed is Dictionary else {}


func _steps() -> Array:
	return _json(SCENE).get("steps", [])


func test_the_scene_plays_the_crown_once_and_the_cue_loads() -> void:
	var named: Array[String] = []
	for step in _steps():
		if step is Dictionary and str(step.get("type", "")) == "play_sfx":
			named.append(str(step.get("sfx", "")))
	assert_gt(_steps().size(), 0, "PREMISE: the scene has steps")
	assert_eq(named, [CUE] as Array[String], "the scene's one sound is the crown; the Elder's lines stay bare")
	var sfx: Dictionary = _json(MANIFEST).get("sfx", {})
	assert_true(sfx.has(CUE), "%s is in the manifest, or the step is silent" % CUE)
	assert_true(ResourceLoader.exists("res://" + str((sfx.get(CUE, {}) as Dictionary).get("file", ""))), "%s loads" % CUE)


## It lands right after the line that says so, and it is over inside the half-second the scene waits before he speaks.
func test_the_crown_is_heard_where_it_is_narrated_and_done_before_he_speaks() -> void:
	var steps := _steps()
	var at := -1
	for i in steps.size():
		if steps[i] is Dictionary and str(steps[i].get("sfx", "")) == CUE:
			at = i
	assert_gt(at, 0, "PREMISE: the crown step exists and is not the first step")
	if at <= 0 or at + 1 >= steps.size():
		return
	assert_true("crown" in str((steps[at - 1] as Dictionary).get("text", "")).to_lower(), "the step before it is the line that names the crown")
	var next: Dictionary = steps[at + 1]
	assert_eq(str(next.get("type", "")), "wait", "a beat of quiet follows it")
	var sfx: Dictionary = _json(MANIFEST).get("sfx", {})
	var d := float((sfx.get(CUE, {}) as Dictionary).get("duration_seconds", 0.0))
	assert_gt(d, 0.0, "PREMISE: the cue has an authored length")
	assert_lte(d, float(next.get("duration", 0.0)), "the crown (%.2fs) has stopped before the wait ends" % d)
	var s = load("res://" + str((sfx.get(CUE, {}) as Dictionary).get("file", "")))
	if s:
		assert_almost_eq(s.get_length(), d, 0.05, "its authored duration describes the asset")
