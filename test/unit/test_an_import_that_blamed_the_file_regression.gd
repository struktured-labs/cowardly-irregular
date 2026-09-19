extends GutTest

## Importing a REJECTED export told the player the file was the wrong kind.
##
##   AutogrindUI._import_scripts loops every file from list_exports(), and EVERY success
##   branch logs while NO refusal branch did. The tail then said, unconditionally on
##   imported == 0, "No compatible files to import."
##
## That is affirmatively wrong rather than merely silent: the file WAS compatible, it was
## refused, and ScriptShareManager had already formatted the reason — last_import_reason()
## is used 15 lines up in the PASTE path and nowhere in this loop.
##
## ⚠️ EVERY REFUSAL HERE IS UNEXPECTED, WHICH IS WHY THEY ALL SPEAK. Reporting a refusal the
## design INTENDS is how a diagnostic becomes noise — cowir-sprites measured 116 of 145 NPCs
## taking the sprite-absence path. Nothing on this loop is that: each file came from
## list_exports(), so the player can see it and asked for it to be imported.
##
## Located by cowir-adhoc, who declined to fix it (read-only lane, and a peer's yes is not
## struktured's). Constraint from cowir-controller.

const UI_PATH := "res://src/ui/autogrind/AutogrindUI.gd"


func _body() -> String:
	var src: String = FileAccess.get_file_as_string(UI_PATH)
	assert_gt(src.length(), 5000, "CONTROL: the UI source must be readable")
	var i: int = src.find("func _import_scripts")
	assert_gt(i, -1, "CONTROL: _import_scripts must be locatable")
	return src.substr(i, src.find("\nfunc ", i + 20) - i)


func test_every_refusal_branch_says_something() -> void:
	var body: String = _body()
	var refusals: int = body.count("refused += 1")
	gut.p("    refusal branches that report: %d" % refusals)
	assert_gte(refusals, 4,
		"each refusal kind must account for itself: unreadable file, empty bundle, " +
		"script refused, rules refused")


func test_the_no_compatible_message_is_not_unconditional() -> void:
	## The defect itself. "No compatible files" after a refusal blames the file for being
	## the wrong kind when it was the right kind and was rejected.
	var body: String = _body()
	assert_false(body.contains("if imported == 0:\n\t\t_log_message"),
		"the tail must not claim incompatibility on a bare imported == 0")
	assert_true(body.contains("imported == 0 and refused == 0"),
		"it must only claim incompatibility when nothing was REFUSED")


func test_a_refused_import_can_reach_the_recorded_reason() -> void:
	var body: String = _body()
	assert_true(body.contains("_refusal_suffix()"),
		"a refusal must be able to carry ScriptShareManager's recorded reason")
	var src: String = FileAccess.get_file_as_string(UI_PATH)
	assert_true(src.contains("last_import_reason()"),
		"and the helper must read it from the share manager")


func test_the_empty_character_id_does_not_borrow_a_stale_reason() -> void:
	## char_id == "" short-circuits, so apply is never called and last_import_reason() still
	## holds the PREVIOUS file's reason. That branch must name itself instead.
	var body: String = _body()
	var at: int = body.find('if char_id == ""')
	assert_gt(at, -1, "the empty-id case must be handled separately")
	var arm: String = body.substr(at, 220)
	assert_false(arm.contains("_refusal_suffix()"),
		"the empty-id branch must NOT use the recorded reason — apply never ran, so it is stale")


func test_no_side_effecting_apply_runs_twice() -> void:
	## I wrote this defect while fixing the other one: an `if not apply(...)` beside an
	## `if apply(...)` reads as two branches and is two APPLICATIONS. Each of these mutates
	## the character's saved script.
	var body: String = _body()
	for fn in ["apply_script_bundle", "apply_character_script", "apply_autogrind_rules"]:
		assert_eq(body.count(fn + "("), 1,
			"%s is side-effecting and must be called exactly ONCE per file" % fn)
