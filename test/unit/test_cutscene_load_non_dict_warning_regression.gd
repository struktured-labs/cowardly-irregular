extends GutTest

## CutsceneDirector._load_cutscene_data already push_error'd on file
## missing / open failed / parse error, but the last branch silently
## swallowed a non-Dict JSON root:
##
##   return json.data if json.data is Dictionary else {}
##
## A corrupted cutscene file that parsed to an Array, String, or null
## (someone wraps `[steps]` instead of `{steps: [...]}`) would return
## {} with no warning. play_cutscene then no-ops the cutscene silently,
## leaving the story completion flag unset — the exact 'looping
## cutscene that never completes' bug class tick 12 had to back-fill
## the rat king for.
##
## Fix: push_error on the non-Dict-root path naming the actual type
## returned, so a malformed cutscene shows up in test runs and the
## dev knows WHAT shape the file actually has.

const DIRECTOR := "res://src/cutscene/CutsceneDirector.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _body_of(func_name: String) -> String:
	var src := _read(DIRECTOR)
	var idx := src.find("func " + func_name)
	assert_gt(idx, -1, func_name + " must exist")
	var next_fn := src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_non_dict_root_pushes_error() -> void:
	var body := _body_of("_load_cutscene_data")
	assert_true(body.contains("parsed but root is not a Dictionary"),
		"non-Dict-root cutscene must push_error (was silent return-empty)")
	# Type info must be in the message so dev knows WHAT shape the file
	# actually had (Array? String? null?) — vague 'not a Dict' is harder
	# to diagnose.
	assert_true(body.contains("type=%s") and body.contains("typeof(json.data)"),
		"non-Dict-root warning must include the actual type of the parsed root")


func test_existing_failure_paths_preserved() -> void:
	# Don't accidentally drop the pre-existing push_errors when adding
	# the new one.
	var body := _body_of("_load_cutscene_data")
	assert_true(body.contains("Cutscene file not found:"),
		"missing-file push_error must still exist")
	assert_true(body.contains("Failed to open:"),
		"open-failed push_error must still exist")
	assert_true(body.contains("JSON parse error in"),
		"parse-error push_error must still exist")


func test_success_path_returns_dict_directly() -> void:
	# Once we've checked is Dictionary, the return should be plain
	# (json.data), not the original ternary fall-through. Pinning this
	# guards against a future cleanup re-introducing the silent
	# fall-through (the original bug shape).
	var body := _body_of("_load_cutscene_data")
	# The body must contain the bare 'return json.data' line, not
	# the ternary form.
	var idx := body.find("return json.data")
	assert_gt(idx, -1, "success-path return must exist")
	var after := body.substr(idx, 30)
	assert_false(after.contains(" if "),
		"return must be bare 'return json.data', not a ternary that could re-introduce silent {} fallback")
