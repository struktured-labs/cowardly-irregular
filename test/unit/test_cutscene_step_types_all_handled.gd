extends GutTest

## Ratchet (dead-field audit 2026-07-02): every step type used in ANY
## data/cutscenes/*.json must have a match arm in _execute_step. 170+
## hand-authored files × a silent-warn default means a typo'd or
## newly-invented step type ships as a no-op nobody notices — the
## give_item/grant_item alias pair shows near-misses already happen.


func test_every_authored_step_type_has_a_handler() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/cutscene/CutsceneDirector.gd")
	var fn: int = src.find("func _execute_step")
	assert_gt(fn, -1)
	var body: String = src.substr(fn, src.find("\nfunc ", fn + 1) - fn)
	var dir := DirAccess.open("res://data/cutscenes")
	assert_not_null(dir)
	var missing: Dictionary = {}
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".json"):
			var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/cutscenes/" + f))
			if data is Dictionary:
				for step in data.get("steps", []):
					if not (step is Dictionary):
						continue
					var t: String = str(step.get("type", ""))
					if t != "" and not body.contains("\"%s\"" % t):
						if not missing.has(t):
							missing[t] = f
		f = dir.get_next()
	assert_eq(missing.size(), 0,
		"step types with NO handler arm (type → first file): %s" % str(missing))


func test_unknown_step_default_warns() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/cutscene/CutsceneDirector.gd")
	assert_true(src.contains("Unknown step type"),
		"the default arm must warn — a silent no-op is how typo'd steps ship")
